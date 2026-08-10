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

    private(set) weak var arView: ARView?
    private var worldAnchor: AnchorEntity?
    private var pointMarkers: [ModelEntity] = []
    private var lineEntities: [ModelEntity] = []
    private var reticleEntity: Entity?
    private var reticleVisible = false
    /// When set, the reticle (and placed points) snap to this height —
    /// Unity's UsePreviousPointHeight made visible.
    var lockedHeight: Float?

    static var isARSupported: Bool { ARWorldTrackingConfiguration.isSupported }
    static var isMeshingSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    // MARK: - Session

    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self

        let anchor = AnchorEntity(world: matrix_identity_float4x4)
        arView.scene.addAnchor(anchor)
        worldAnchor = anchor

        let reticle = Self.makeReticle()
        reticle.isEnabled = false
        anchor.addChild(reticle)
        reticleEntity = reticle

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        if Self.isMeshingSupported {
            config.sceneReconstruction = .mesh
            arView.debugOptions.insert(.showSceneUnderstanding)
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
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
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

    /// Called every frame: keeps the reticle glued to the surface under the
    /// screen center.
    fileprivate func updateReticle() {
        guard reticleVisible, let reticleEntity else { return }
        guard let arView else {
            reticleEntity.isEnabled = false
            return
        }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let hit = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first
        else {
            reticleEntity.isEnabled = false
            return
        }
        let t = hit.worldTransform
        var position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        if let lockedHeight {
            // Show the point exactly where it would be placed.
            position.y = lockedHeight
            reticleEntity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        } else {
            reticleEntity.orientation = simd_quatf(t)
        }
        reticleEntity.position = position
        reticleEntity.isEnabled = true
    }

    // MARK: - Raycast + markers

    /// Raycasts from the screen center (the reticle) onto the scanned
    /// surfaces; returns the hit position in ARKit world space.
    func raycastFromCenter() -> SIMD3<Float>? {
        guard let arView else { return nil }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let hit = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first
        else { return nil }
        let t = hit.worldTransform.columns.3
        return SIMD3<Float>(t.x, t.y, t.z)
    }

    func addMarker(at position: SIMD3<Float>, type: PointType) {
        guard let worldAnchor else { return }
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.025),
            materials: [UnlitMaterial(color: type.uiColor)]
        )
        sphere.position = position
        worldAnchor.addChild(sphere)
        pointMarkers.append(sphere)
    }

    func removeLastMarker() {
        pointMarkers.popLast()?.removeFromParent()
    }

    func clearMarkersAndLines() {
        pointMarkers.forEach { $0.removeFromParent() }
        pointMarkers.removeAll()
        rebuildLines(through: [], closeLoop: false)
    }

    /// Rebuilds the polyline connecting the given points (Unity's
    /// LinesController.SetupLine).
    func rebuildLines(through points: [SIMD3<Float>], closeLoop: Bool) {
        lineEntities.forEach { $0.removeFromParent() }
        lineEntities.removeAll()
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
    /// coordinates) and serializes it exactly like Unity's SaveMesh:
    /// vertices 'm|' normals 'm|' triangles 'm|' indices 'm|' topology 'm|' color
    /// with vertices/normals joined by 'v|'/'n|' as "x y z".
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

        func fmt(_ v: Float) -> String {
            String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), v)
        }

        var sb = ""
        sb.reserveCapacity(vertices.count * 24 + triangles.count * 8)
        sb += vertices.map { "\(fmt($0.x)) \(fmt($0.y)) \(fmt($0.z))" }.joined(separator: "v|")
        sb += "m|"
        sb += normals.map { "\(fmt($0.x)) \(fmt($0.y)) \(fmt($0.z))" }.joined(separator: "n|")
        sb += "m|"
        let triangleStr = triangles.map(String.init).joined(separator: " ")
        sb += triangleStr
        sb += "m|"
        sb += triangleStr // Unity writes GetIndices(0), identical to triangles here
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

extension ARScanController: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let added = anchors.filter { $0 is ARMeshAnchor }.count
        if added > 0 {
            DispatchQueue.main.async { self.meshChunkCount += added }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updateReticle()
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
