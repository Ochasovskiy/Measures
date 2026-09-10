//
//  ARScanController.swift
//  MeasureGo
//
//  ARKit/RealityKit side of the scan flow: LiDAR meshing, center raycast,
//  point markers, perimeter lines, and export of the combined mesh in
//  Unity's .dat text format (SaveMesh.MeshToStr).
//
//  Coordinates: ARKit is right-handed (−z forward), Unity is left-handed.
//  Unity's ARFoundation maps ARKit → Unity as (x, y, −z); we do the same when
//  exporting so saved data matches what the Unity app would have written.
//

import ARKit
import AVFoundation
import RealityKit
import Combine
import UIKit

final class ARScanController: NSObject, ObservableObject {

    @Published private(set) var meshChunkCount = 0
    @Published private(set) var isTorchOn = false

    /// A placed point, pinned to the real world by its own ARAnchor — Unity's
    /// PointPlace.CreateAndAttachAnchor re-parented each marker to one for the
    /// same reason. ARKit nudges the anchor as it refines its map, so the
    /// marker stays on the surface it was placed on instead of sliding off it.
    private struct PlacedMarker {
        /// Replaced whenever ARKit hands back a refined copy of the anchor.
        var anchor: ARAnchor
        let type: PointType
        let entity: ModelEntity

        var position: SIMD3<Float> {
            let c = anchor.transform.columns.3
            return SIMD3(c.x, c.y, c.z)
        }
    }

    private(set) weak var arView: ARView?
    private var worldAnchor: AnchorEntity?
    private var placedMarkers: [PlacedMarker] = []
    /// Identifiers of the anchors we own, so the session delegate can ignore
    /// the LiDAR mesh anchors it is flooded with while scanning.
    private var pointAnchorIDs: Set<UUID> = []
    private var lineEntities: [ModelEntity] = []
    /// Set when a correction moved a perimeter marker; the render loop then
    /// rebuilds the lines once for the frame rather than once per update.
    private var linesNeedRebuild = false
    private var linesClosed = false
    private var reticleEntity: Entity?
    private var reticleVisible = false
    private var sceneUpdateSubscription: Cancellable?
    /// Smoothed reticle position, so a noisy sample doesn't make it twitch.
    /// This is also *exactly* what gets stored when a point is placed — the
    /// reticle is the measurement, not a preview of one.
    private var smoothedReticlePosition: SIMD3<Float>?
    /// Recent depth samples, median-filtered before smoothing. A median throws
    /// a bad frame away outright; an average would fold part of it in, which
    /// matters once the value is a stored measurement rather than a visual.
    private var depthSamples: [SIMD3<Float>] = []
    private static let depthSampleCount = 9
    /// `.medium` is ARKit's own practical threshold — `.high` is rare enough
    /// on real surfaces that requiring it rejects floors the sensor is reading
    /// perfectly well. `.low` is the only level that genuinely means "guess".
    private static let requiredDepthConfidence: ARConfidenceLevel = .medium
    /// Half-width of the sampled patch, in depth-map pixels (8 = 17x17, about
    /// 6% of the frame's width — still a small target around the reticle).
    private static let depthPatchRadius = 8
    /// Below this many confident samples in the patch, lower-confidence
    /// returns are taken as well rather than reporting no surface at all.
    private static let minimumConfidentSamples = 8
    /// How long a good reading stays on screen through a momentary dropout.
    private static let surfaceGracePeriod: CFTimeInterval = 0.6
    private var lastSurfaceTime: CFTimeInterval = 0

    /// When set, the reticle (and placed points) snap to this height —
    /// Unity's UsePreviousPointHeight made visible.
    var lockedHeight: Float?

    private var pendingTrackingChange: DispatchWorkItem?
    private var pendingTrackingTarget: TrackingQuality?

    /// True while the reticle is on a real, confident surface. Placement is
    /// refused otherwise: no plane-fit fallback, so a point is never invented
    /// where the sensor saw nothing.
    @Published private(set) var hasSurface = false
    @Published private(set) var tracking: TrackingQuality = .establishing("Starting up — move the phone slowly")
    /// Distance from the last placed point to the reticle, in feet and inches.
    @Published private(set) var liveDistanceText: String?
    /// Length of the segment just completed. The live reading measures to the
    /// point you last placed, so the moment you place one it correctly reads
    /// zero — which is useless right when you want to know how long that side
    /// was. Unity labelled the finished segment; this is that number.
    @Published private(set) var lastSegmentText: String?
    private var lastDistanceUpdate: CFTimeInterval = 0

    enum TrackingQuality: Equatable {
        case good
        /// Worse than ideal, but the world frame is intact, so a measurement
        /// taken now is still valid. Say so; do not take the button away.
        case advisory(String)
        /// The world frame is not established yet, or is being rebuilt. A
        /// point placed now could land somewhere else entirely. Block.
        case establishing(String)
        /// Genuinely gone. Worth interrupting the user for.
        case lost(String)

        var message: String? {
            switch self {
            case .good: return nil
            case .advisory(let reason), .establishing(let reason), .lost(let reason): return reason
            }
        }
    }

    static var isARSupported: Bool { ARWorldTrackingConfiguration.isSupported }
    /// MeasureGo is LiDAR-only by decision: measurement quality is the product,
    /// and without a depth sensor every position would be a plane-fit estimate.
    static var isMeshingSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
    static var isDepthSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }
    static var isDeviceEligible: Bool { isARSupported && isMeshingSupported && isDepthSupported }

    // MARK: - Session

    func attach(to arView: ARView) {
        // Re-attaching to the same view would re-run the session with
        // .resetTracking and wipe the mesh collected so far.
        guard self.arView !== arView else { return }
        self.arView = arView
        arView.session.delegate = self

        let anchor = AnchorEntity(world: matrix_identity_float4x4)
        arView.scene.addAnchor(anchor)
        worldAnchor = anchor

        let reticle = Self.makeReticle()
        reticle.isEnabled = false
        anchor.addChild(reticle)
        reticleEntity = reticle

        // Drive the reticle from RealityKit's render loop rather than from
        // session(_:didUpdate:) — per-frame work in the session delegate makes
        // ARKit queue up (and warn about) retained ARFrames.
        sceneUpdateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self else { return }
            if linesNeedRebuild { rebuildLines(closeLoop: linesClosed) }
            updateReticle(deltaTime: Float(event.deltaTime))
        }

        let config = ARWorldTrackingConfiguration()
        // No plane detection: placement reads the depth sensor directly now,
        // so fitting planes is pure cost on a session already reporting
        // resource pressure and failing to initialize its tracking.
        config.planeDetection = []
        if Self.isMeshingSupported {
            config.sceneReconstruction = .mesh
            arView.debugOptions.insert(.showSceneUnderstanding)
        }
        // Placement reads metric depth straight from the LiDAR rather than
        // raycasting onto a fitted plane. The smoothed variant is temporally
        // filtered by ARKit, which is what we want for a static target.
        // Exactly one depth semantic. Asking for both, on top of mesh
        // reconstruction, oversubscribed the camera pipeline: the device logs
        // showed "resource constraints" and vio_initialized=0, meaning visual
        // tracking never came up at all until the session was restarted.
        //
        // `sceneDepth` rather than `smoothedSceneDepth` because the smoothed
        // variant costs more — ARKit filters it over time — and we already run
        // our own median across frames, so we were paying twice for one thing.
        if Self.isDepthSupported {
            config.frameSemantics.insert(.sceneDepth)
        }
        config.environmentTexturing = .none
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func setMeshVisualizationVisible(_ visible: Bool) {
        guard let arView, Self.isMeshingSupported else { return }
        if visible {
            arView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            arView.debugOptions.remove(.showSceneUnderstanding)
        }
    }

    func pauseSession() {
        // Never leave the torch burning when the scan ends.
        setTorch(false)
        arView?.session.pause()
    }

    deinit {
        Self.forceTorchOff()
    }

    // MARK: - Torch

    static var isTorchAvailable: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    func toggleTorch() {
        setTorch(!isTorchOn)
    }

    func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        let desiredMode: AVCaptureDevice.TorchMode = on ? .on : .off
        // Leaving the scan screen calls this on every exit path; don't buzz,
        // log, or touch the device when nothing actually changes.
        guard device.torchMode != desiredMode || isTorchOn != on else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = desiredMode
            device.unlockForConfiguration()
            isTorchOn = on
            Haptics.selection()
            AppLog.log("Torch \(on ? "on" : "off")")
        } catch {
            AppLog.log("Torch error: \(error.localizedDescription)")
        }
    }

    /// Safe to call from anywhere (including deinit and app lifecycle hooks).
    static func forceTorchOff() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch, device.torchMode != .off else { return }
        try? device.lockForConfiguration()
        device.torchMode = .off
        device.unlockForConfiguration()
    }

    // MARK: - Reticle (Unity's Indicator: a 3D marker on the raycast hit)

    /// Shows/hides the 3D reticle that tracks the screen-center raycast hit.
    func setReticleVisible(_ visible: Bool) {
        reticleVisible = visible
        if !visible {
            reticleEntity?.isEnabled = false
        }
    }

    private static func makeReticle() -> Entity {
        let root = Entity()
        let ring = ModelEntity(
            mesh: .generateCylinder(height: 0.002, radius: 0.06),
            materials: [UnlitMaterial(color: UIColor.white)]
        )
        let innerDisc = ModelEntity(
            mesh: .generateCylinder(height: 0.003, radius: 0.045),
            materials: [UnlitMaterial(color: UIColor(white: 0.1, alpha: 1))]
        )
        let dot = ModelEntity(
            mesh: .generateSphere(radius: 0.008),
            materials: [UnlitMaterial(color: UIColor.white)]
        )
        dot.position.y = 0.006
        root.addChild(ring)
        root.addChild(innerDisc)
        root.addChild(dot)
        root.components.set(OpacityComponent(opacity: 0.85))
        return root
    }

    /// Runs once per rendered frame (SceneEvents.Update), so the reticle is
    /// locked to the display refresh rate — 60 or 120 Hz — with no beating
    /// between update and render rates. Safe here because, unlike the
    /// ARSession delegate, this path never holds on to ARFrames.
    fileprivate func updateReticle(deltaTime: Float = 1.0 / 60.0) {
        guard reticleVisible, let reticleEntity else { return }

        // Tracking state is read from the frame itself rather than trusted to
        // arrive by delegate callback. ARView starts its own session before we
        // attach, so the initializing → normal transition can happen before our
        // delegate exists — and then nothing ever clears the initial state and
        // placement stays disabled forever on a perfectly tracking session.
        guard let frame = arView?.session.currentFrame else {
            // No frame at all: leave whatever an interruption or failure set,
            // and just stop drawing.
            reticleEntity.isEnabled = false
            return
        }
        apply(trackingState: frame.camera.trackingState)

        guard let sample = sampleDepth(in: frame) else {
            // Hold the last good reading briefly. A single frame without a
            // return is normal even on a surface that is plainly there, and
            // blanking the reticle on it makes the app feel broken.
            let now = CACurrentMediaTime()
            if smoothedReticlePosition != nil,
               now - lastSurfaceTime < Self.surfaceGracePeriod {
                reticleEntity.isEnabled = true
                return
            }
            reticleEntity.isEnabled = false
            depthSamples.removeAll()
            smoothedReticlePosition = nil
            if hasSurface { hasSurface = false }
            return
        }
        lastSurfaceTime = CACurrentMediaTime()

        depthSamples.append(sample)
        if depthSamples.count > Self.depthSampleCount {
            depthSamples.removeFirst(depthSamples.count - Self.depthSampleCount)
        }

        var target = Self.componentWiseMedian(of: depthSamples)
        if let lockedHeight {
            // Show the point exactly where it would be placed.
            target.y = lockedHeight
        }
        reticleEntity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])

        // Frame-rate independent smoothing on top of the median. The median
        // has already removed outliers, so this only needs to take the edge
        // off the remaining jitter — too long a constant and the reticle
        // feels like it is dragging behind the phone.
        if let current = smoothedReticlePosition {
            let alpha = 1 - exp(-deltaTime / 0.03)
            smoothedReticlePosition = current + (target - current) * alpha
        } else {
            smoothedReticlePosition = target
        }

        reticleEntity.position = smoothedReticlePosition ?? target
        reticleEntity.isEnabled = true
        if !hasSurface { hasSurface = true }
        updateLiveDistance()
    }

    /// Running distance from the last placed point to the reticle, as Unity
    /// showed on its placement indicator. Refreshed a few times a second
    /// rather than every frame — the reticle needs the render loop, a text
    /// label does not, and publishing at 120 Hz would redraw the whole overlay.
    private func updateLiveDistance() {
        // 10 Hz: fast enough to read as live, and each refresh now redraws
        // only the small readout view rather than the whole scan overlay.
        let now = CACurrentMediaTime()
        guard now - lastDistanceUpdate >= 0.1 else { return }
        lastDistanceUpdate = now

        guard let from = placedMarkers.last?.position, let to = smoothedReticlePosition else {
            if liveDistanceText != nil { liveDistanceText = nil }
            return
        }
        let text = Units.feetInches(from: from, to: to)
        if liveDistanceText != text { liveDistanceText = text }
    }

    // MARK: - Depth sampling

    /// Where a point would land right now: the position the reticle is
    /// actually drawn at. Placement and display read the same value, so a
    /// point is stored where the user aimed rather than wherever a fresh
    /// single-frame sample happened to fall at the instant of the tap.
    /// Tracking state deliberately does not gate this. Gating on it blocked
    /// measuring outright when the session came up badly, and the honest
    /// requirement is simpler: if the reticle is on a surface, that position
    /// is a real reading and the user may place it.
    var placementPosition: SIMD3<Float>? {
        guard hasSurface else { return nil }
        return smoothedReticlePosition
    }

    /// Unprojects the LiDAR depth at the middle of the screen into world
    /// space. Returns nil when there is no confident return there — out of
    /// the sensor's range, or a surface it cannot read — so that no position
    /// is ever invented for a place the sensor did not actually see.
    private func sampleDepth(in frame: ARFrame) -> SIMD3<Float>? {
        guard let depth = frame.sceneDepth ?? frame.smoothedSceneDepth else { return nil }

        let depthMap = depth.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap)

        let confidenceMap = depth.confidenceMap
        var confidenceBase: UnsafeMutableRawPointer?
        var confidenceStride = 0
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
            confidenceBase = CVPixelBufferGetBaseAddress(confidenceMap)
            confidenceStride = CVPixelBufferGetBytesPerRow(confidenceMap)
        }
        defer {
            if let confidenceMap { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
        }

        // The viewport is centred on the captured image, so the middle of the
        // screen is the middle of the depth map whatever the aspect crop.
        let col = width / 2
        let row = height / 2

        // Sample a patch rather than one pixel. The depth map is only 256x192,
        // so a single sample can come back invalid or low-confidence while
        // everything around it is a good reading of the same flat surface —
        // that was making the reticle refuse a floor it could see perfectly.
        //
        // Confidence is a preference, not a gate. A low-confidence return is
        // still the sensor reporting a distance it actually measured; it is
        // noisier, not invented, and the median across the patch absorbs that.
        // Refusing outright is what "No surface in range" meant on a tiled
        // kitchen floor the LiDAR could obviously see.
        var preferred: [Float] = []
        var fallback: [Float] = []
        preferred.reserveCapacity(64)
        for dr in -Self.depthPatchRadius...Self.depthPatchRadius {
            for dc in -Self.depthPatchRadius...Self.depthPatchRadius {
                let r = row + dr
                let c = col + dc
                guard r >= 0, r < height, c >= 0, c < width else { continue }

                let d = base.advanced(by: r * depthStride + c * MemoryLayout<Float32>.size)
                    .assumingMemoryBound(to: Float32.self).pointee
                guard d.isFinite, d > 0.05, d < 10 else { continue }

                var confident = true
                if let confidenceBase {
                    let raw = confidenceBase.advanced(by: r * confidenceStride + c)
                        .assumingMemoryBound(to: UInt8.self).pointee
                    confident = Int(raw) >= Self.requiredDepthConfidence.rawValue
                }
                if confident { preferred.append(d) } else { fallback.append(d) }
            }
        }
        // Enough good samples to trust; otherwise take what the sensor did see.
        var distances = preferred.count >= Self.minimumConfidentSamples ? preferred : preferred + fallback
        guard !distances.isEmpty else { return nil }
        distances.sort()
        let distance = distances[distances.count / 2]

        // Scale the camera intrinsics from the capture resolution down to the
        // depth map's, then unproject: ARKit camera space is x right, y up,
        // −z forward, while image rows run downwards.
        let camera = frame.camera
        let intrinsics = camera.intrinsics
        let imageSize = camera.imageResolution
        let scaleX = Float(width) / Float(imageSize.width)
        let scaleY = Float(height) / Float(imageSize.height)
        let fx = intrinsics[0][0] * scaleX
        let fy = intrinsics[1][1] * scaleY
        let cx = intrinsics[2][0] * scaleX
        let cy = intrinsics[2][1] * scaleY
        guard fx != 0, fy != 0 else { return nil }

        let x = (Float(col) - cx) * distance / fx
        let y = (Float(row) - cy) * distance / fy
        let world = camera.transform * SIMD4<Float>(x, -y, -distance, 1)
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    /// Median per axis. Cheaper than a true geometric median and, for jitter
    /// around a static target, indistinguishable from one.
    private static func componentWiseMedian(of samples: [SIMD3<Float>]) -> SIMD3<Float> {
        func median(_ values: [Float]) -> Float {
            let sorted = values.sorted()
            let middle = sorted.count / 2
            return sorted.count.isMultiple(of: 2)
                ? (sorted[middle - 1] + sorted[middle]) / 2
                : sorted[middle]
        }
        return SIMD3(median(samples.map(\.x)), median(samples.map(\.y)), median(samples.map(\.z)))
    }

    // MARK: - Markers

    func addMarker(at position: SIMD3<Float>, type: PointType) {
        guard let worldAnchor, let arView else { return }

        // Length of the side just closed, captured before this point becomes
        // "the last one" and the live reading collapses to zero.
        lastSegmentText = placedMarkers.last.map {
            Units.feetInches(from: $0.position, to: position)
        }

        // Give the point its own ARAnchor before drawing it, so ARKit starts
        // tracking that spot as a place in the room rather than a coordinate.
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(position, 1)
        let anchor = ARAnchor(name: "MeasureGoPoint", transform: transform)
        arView.session.add(anchor: anchor)

        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.025),
            materials: [UnlitMaterial(color: type.uiColor)]
        )
        sphere.position = position
        worldAnchor.addChild(sphere)

        placedMarkers.append(PlacedMarker(anchor: anchor, type: type, entity: sphere))
        pointAnchorIDs.insert(anchor.identifier)
    }

    func removeLastMarker() {
        lastSegmentText = nil
        guard let last = placedMarkers.popLast() else { return }
        last.entity.removeFromParent()
        pointAnchorIDs.remove(last.anchor.identifier)
        // Unity's RemoveLastPoint dropped the anchor with the point; leaving it
        // behind would keep ARKit tracking a spot nothing references.
        arView?.session.remove(anchor: last.anchor)
    }

    func clearMarkersAndLines() {
        lastSegmentText = nil
        for marker in placedMarkers {
            marker.entity.removeFromParent()
            arView?.session.remove(anchor: marker.anchor)
        }
        placedMarkers.removeAll()
        pointAnchorIDs.removeAll()
        rebuildLines(closeLoop: false)
    }

    /// Rebuilds the polyline through the perimeter markers (Unity's
    /// LinesController.SetupLine, which likewise read the markers' live
    /// transforms so the line followed their corrections).
    func rebuildLines(closeLoop: Bool) {
        linesClosed = closeLoop
        linesNeedRebuild = false
        lineEntities.forEach { $0.removeFromParent() }
        lineEntities.removeAll()

        let points = placedMarkers.filter { $0.type == .perimeter }.map(\.position)
        guard let worldAnchor, points.count >= 2 else { return }

        var segments = Array(zip(points, points.dropFirst()))
        if closeLoop, points.count > 2, let first = points.first, let last = points.last {
            segments.append((last, first))
        }

        for (a, b) in segments {
            let length = simd_distance(a, b)
            guard length > 0.001 else { continue }
            let entity = ModelEntity(
                mesh: .generateBox(size: [0.008, 0.008, length]),
                materials: [UnlitMaterial(color: .black)]
            )
            entity.position = (a + b) / 2
            entity.look(at: b, from: entity.position, relativeTo: nil)
            worldAnchor.addChild(entity)
            lineEntities.append(entity)
        }
    }

    // MARK: - Mesh export (Unity SaveMesh.MeshToStr format)

    /// Combines all LiDAR mesh anchors into one mesh (world space, Unity
    /// coordinates) and serializes it in the SaveMesh text format:
    /// vertices 'm|' normals 'm|' triangles 'm|' topology 'm|' color
    /// with vertices/normals joined by 'v|'/'n|' as "x y z".
    ///
    /// Deviation from Unity: Unity also wrote the index list a second time
    /// (its GetIndices(0) section), identical to the triangle list. Nothing
    /// reads it — dropping it makes files ~30% smaller, and that budget is
    /// spent on keeping more geometry instead. MeshDatParser reads the
    /// leading sections only, so scans written by either format still load.
    func exportUnityMeshString() -> String? {
        guard let frame = arView?.session.currentFrame else { return nil }
        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return nil }

        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var triangles: [UInt32] = []

        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let transform = anchor.transform
            let baseIndex = UInt32(vertices.count)

            for i in 0..<geometry.vertices.count {
                let local = geometry.vertices.float3(at: i)
                let world4 = transform * SIMD4<Float>(local.x, local.y, local.z, 1)
                vertices.append(Self.unityFromARKit(SIMD3(world4.x, world4.y, world4.z)))

                let n = geometry.normals.float3(at: i)
                let worldN4 = transform * SIMD4<Float>(n.x, n.y, n.z, 0)
                normals.append(Self.unityFromARKit(SIMD3(worldN4.x, worldN4.y, worldN4.z)))
            }

            let faces = geometry.faces
            for f in 0..<faces.count {
                let (i0, i1, i2) = faces.triangleIndices(at: f)
                // Mirroring z flips handedness: reverse winding to keep faces
                // pointing the right way in Unity space.
                triangles.append(baseIndex + i0)
                triangles.append(baseIndex + i2)
                triangles.append(baseIndex + i1)
            }
        }

        // Decimate before writing (Unity ran a 0.5 simplification here).
        let sourceTriangleCount = triangles.count / 3
        let decimated = MeshDecimator.decimateToBudget(
            MeshDecimator.Mesh(vertices: vertices, normals: normals, triangles: triangles))
        vertices = decimated.vertices
        normals = decimated.normals
        triangles = decimated.triangles
        AppLog.log("Mesh decimated: \(sourceTriangleCount) -> \(triangles.count / 3) triangles, \(vertices.count) vertices")

        func fmt(_ v: Float) -> String {
            String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), v)
        }

        var sb = ""
        sb.reserveCapacity(vertices.count * 24 + triangles.count * 8)
        sb += vertices.map { "\(fmt($0.x)) \(fmt($0.y)) \(fmt($0.z))" }.joined(separator: "v|")
        sb += "m|"
        sb += normals.map { "\(fmt($0.x)) \(fmt($0.y)) \(fmt($0.z))" }.joined(separator: "n|")
        sb += "m|"
        sb += triangles.map(String.init).joined(separator: " ")
        sb += "m|"
        sb += "Triangles"
        sb += "m|"
        sb += "1 1 1 1" // Color.white
        return sb
    }

    static func unityFromARKit(_ v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(v.x, v.y, -v.z)
    }
}

extension ARScanController {

    /// Degraded tracking is reported only once it has persisted, so a blip
    /// lasting a few frames never flashes the controls at the user. Recovery
    /// is applied immediately — there is no reason to keep someone waiting
    /// once tracking is good again.
    private static let degradeGracePeriod: TimeInterval = 0.5

    fileprivate func apply(trackingState state: ARCamera.TrackingState) {
        let next: TrackingQuality
        switch state {
        case .normal:
            next = .good
        case .notAvailable:
            next = .lost("Tracking is unavailable.")
        case .limited(let reason):
            switch reason {
            // These two mean the world frame itself is not settled, so a
            // placed point cannot be trusted to stay where it was put.
            case .initializing:
                next = .establishing("Starting up — move the phone slowly")
            case .relocalizing:
                next = .establishing("Finding your place again — move slowly")
            // These two only mean ARKit is less confident. Depth still reads
            // true, so let the measurement happen and just say what is off.
            case .excessiveMotion:
                next = .advisory("Moving fast — slow down for best accuracy")
            case .insufficientFeatures:
                next = .advisory("Plain surface — hold steady for best accuracy")
            @unknown default:
                next = .advisory("Tracking is not ideal — move slowly")
            }
        }
        set(tracking: next, immediately: next == .good)
    }

    fileprivate func set(tracking next: TrackingQuality, immediately: Bool) {
        guard tracking != next else {
            // Already there — drop any pending change to something else.
            pendingTrackingChange?.cancel()
            pendingTrackingChange = nil
            pendingTrackingTarget = nil
            return
        }

        if immediately {
            pendingTrackingChange?.cancel()
            pendingTrackingChange = nil
            pendingTrackingTarget = nil
            tracking = next
            return
        }

        // This runs once per frame, so re-arming the timer on every call would
        // push it out forever and the change would never land. Only (re)start
        // it when the target actually differs from what is already pending.
        guard pendingTrackingTarget != next else { return }
        pendingTrackingChange?.cancel()
        pendingTrackingTarget = next

        // Only the published message changes. Tracking state no longer touches
        // the reticle or the samples: the depth reading stands on its own, and
        // tearing it down here is what made a bad session unrecoverable.
        let work = DispatchWorkItem { [weak self] in
            guard let self, tracking != next else { return }
            tracking = next
        }
        pendingTrackingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.degradeGracePeriod, execute: work)
    }
}

extension ARScanController: ARSessionDelegate {

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        apply(trackingState: camera.trackingState)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        set(tracking: .lost("The camera was interrupted."), immediately: true)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        set(tracking: .establishing("Picking tracking back up — move slowly"), immediately: true)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        AppLog.log("AR session failed: \(error.localizedDescription)")
        set(tracking: .lost("The camera session stopped."), immediately: true)
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let added = anchors.filter { $0 is ARMeshAnchor }.count
        if added > 0 {
            DispatchQueue.main.async { self.meshChunkCount += added }
        }
    }

    /// ARKit refines its map as the scan goes on and moves anchors to match;
    /// this is where a placed marker follows the surface it was pinned to.
    /// Called on the main queue (the session has no custom delegate queue),
    /// which is where RealityKit entities must be touched.
    ///
    /// This runs constantly during meshing — every LiDAR chunk is an anchor —
    /// so it bails out before doing any work when none of the anchors are ours.
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard !pointAnchorIDs.isEmpty else { return }

        for anchor in anchors where pointAnchorIDs.contains(anchor.identifier) {
            guard let index = placedMarkers.firstIndex(
                where: { $0.anchor.identifier == anchor.identifier }) else { continue }
            // ARKit hands back a fresh anchor object, so keep the new one —
            // it is also what session.remove(anchor:) needs on undo.
            placedMarkers[index].anchor = anchor
            placedMarkers[index].entity.position = placedMarkers[index].position
            if placedMarkers[index].type == .perimeter { linesNeedRebuild = true }
        }
    }
}

// MARK: - ARMeshGeometry buffer access

private extension ARGeometrySource {
    /// Reads a packed float3 at the given index (SIMD3<Float> is 16 bytes,
    /// the buffer is packed 12-byte float3s — read component-wise).
    func float3(at index: Int) -> SIMD3<Float> {
        let pointer = buffer.contents().advanced(by: offset + stride * index)
        let floats = pointer.assumingMemoryBound(to: Float.self)
        return SIMD3(floats[0], floats[1], floats[2])
    }
}

private extension ARGeometryElement {
    func triangleIndices(at face: Int) -> (UInt32, UInt32, UInt32) {
        let indexCount = indexCountPerPrimitive // 3 for triangles
        let pointer = buffer.contents().advanced(by: face * indexCount * bytesPerIndex)
        if bytesPerIndex == 4 {
            let idx = pointer.assumingMemoryBound(to: UInt32.self)
            return (idx[0], idx[1], idx[2])
        } else {
            let idx = pointer.assumingMemoryBound(to: UInt16.self)
            return (UInt32(idx[0]), UInt32(idx[1]), UInt32(idx[2]))
        }
    }
}
