//
//  ARScanViewModel.swift
//  MeasureGo
//
//  Scan-flow state machine mirroring Unity's FsmScan -> FsmScanPerimiter ->
//  FsmScanFeature, and the save logic from FsmScanFeature.OnSaveScanBtnClick.
//

import Foundation
import simd
import Combine
import QuartzCore
// For Array.move(fromOffsets:toOffset:), which SwiftUI defines.
import SwiftUI

@MainActor
final class ARScanViewModel: ObservableObject {

    enum Phase {
        case tutorial
        case perimeter
        case features
    }

    struct PlacedPoint: Identifiable {
        let id = UUID()
        let uuid: String
        let type: PointType
        /// ARKit world position (converted to Unity coordinates on save).
        let position: SIMD3<Float>
        /// Per-type 1-based number. Recomputed whenever points are deleted or
        /// reordered, so the list, the AR labels and the saved CSV agree.
        var index: Int
        let notes: String
    }

    @Published var phase: Phase = .tutorial {
        didSet { syncLockedHeight() }
    }
    @Published private(set) var points: [PlacedPoint] = []
    @Published var selectedFeatureType: PointType = .none {
        didSet { syncLockedHeight() }
    }
    @Published var lockHeight = false {
        didSet { syncLockedHeight() }
    }
    @Published var placementFailed = false
    /// Notes attached to feature points placed while set (Unity's
    /// FeatureDetailsPanel notes field).
    @Published var pointNotes = ""

    let controller = ARScanController()
    private let startTime: String

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init() {
        // Unity records StartScanTime when the scan screen activates.
        startTime = Self.isoFormatter.string(from: Date())
    }

    var perimeterPoints: [PlacedPoint] { points.filter { $0.type == .perimeter } }

    private var activePointType: PointType {
        phase == .perimeter ? .perimeter : selectedFeatureType
    }

    /// Keeps the controller's reticle height in sync with the lock state so
    /// the target visibly snaps to the height points will be placed at.
    private func syncLockedHeight() {
        controller.lockedHeight = lockHeight
            ? points.last(where: { $0.type == activePointType })?.position.y
            : nil
    }

    // MARK: - Point placement

    /// Two points from one intent is worse than a missed tap: the duplicate
    /// sits on top of its twin, so it is nearly invisible in the AR view and
    /// only shows up later as a zero-length side in the drawing.
    private static let minimumPlacementInterval: CFTimeInterval = 0.5
    private var lastPlacementTime: CFTimeInterval = 0

    func placePoint() {
        let now = CACurrentMediaTime()
        guard now - lastPlacementTime >= Self.minimumPlacementInterval else { return }

        let type: PointType = phase == .perimeter ? .perimeter : selectedFeatureType
        guard type != .none else { return }

        // The reticle's own position, not a fresh sample — what you see is
        // what gets stored. Nil means no confident surface or poor tracking,
        // in which case the button is already disabled and we simply refuse.
        guard var position = controller.placementPosition else {
            placementFailed = true
            Haptics.warning()
            return
        }

        // Unity's UsePreviousPointHeight: reuse the previous point's height.
        if lockHeight, let previous = points.last(where: { $0.type == type }) {
            position.y = previous.position.y
        }

        let index = points.filter { $0.type == type }.count + 1
        let point = PlacedPoint(
            uuid: UUID().uuidString,
            type: type,
            position: position,
            index: index,
            // Unity: perimeter points get empty notes; feature points get the
            // notes text current at placement time.
            notes: phase == .features ? pointNotes : ""
        )
        points.append(point)
        // Only a placement that actually happened starts the interval — a tap
        // rejected for having no surface must not lock out the next one.
        lastPlacementTime = now

        controller.addMarker(at: position, type: type, index: index)
        if type == .perimeter {
            controller.rebuildLines(closeLoop: false)
        }
        syncLockedHeight()
        // Fired after the position is captured — cannot affect the point.
        Haptics.placement()
    }

    func undoLastPoint() {
        // Undo only removes points placed in the current phase, like Unity's
        // per-state _statePointList.
        let currentTypeFilter: (PlacedPoint) -> Bool = phase == .perimeter
            ? { $0.type == .perimeter }
            : { $0.type != .perimeter }
        guard let last = points.last, currentTypeFilter(last) else { return }

        points.removeLast()
        Haptics.selection()
        controller.removeLastMarker()
        if last.type == .perimeter {
            controller.rebuildLines(closeLoop: false)
        }
        syncLockedHeight()
    }

    var canUndo: Bool {
        guard let last = points.last else { return false }
        return phase == .perimeter ? last.type == .perimeter : last.type != .perimeter
    }

    func finishPerimeter() {
        controller.rebuildLines(closeLoop: true)
        phase = .features
    }

    // MARK: - Editing placed points (Unity's PointEditPanel)

    /// Deletes one point. Undo only reaches the most recent point, so without
    /// this a single bad point early in a long perimeter meant rescanning.
    /// Matched by uuid: the review list shows saved-shape points, not the
    /// in-memory ones, and the uuid is what survives that conversion.
    func deletePoint(matching pointData: ScanData.PointData) {
        guard let index = points.firstIndex(where: { $0.uuid == pointData.uuid }) else { return }
        points.remove(at: index)
        controller.removeMarker(at: index)
        renumberAndRedraw()
        Haptics.selection()
    }

    /// Reorders points. The perimeter is a polygon, so the order of its points
    /// *is* its shape — this is how a rep fixes a side that zig-zags because
    /// one point was tagged out of sequence.
    func movePoints(fromOffsets source: IndexSet, toOffset destination: Int) {
        points.move(fromOffsets: source, toOffset: destination)
        controller.moveMarkers(fromOffsets: source, toOffset: destination)
        renumberAndRedraw()
    }

    /// Renumbers per type exactly as placement does, then pushes the result to
    /// the AR labels and the perimeter line.
    private func renumberAndRedraw() {
        var counters: [PointType: Int] = [:]
        var numbers: [Int] = []
        numbers.reserveCapacity(points.count)

        for i in points.indices {
            let next = (counters[points[i].type] ?? 0) + 1
            counters[points[i].type] = next
            points[i].index = next
            numbers.append(next)
        }

        controller.setMarkerNumbers(numbers)
        controller.rebuildLines()
        syncLockedHeight()
    }

    /// The points as they would be saved, in Unity coordinates.
    private var pointsDataForSave: [ScanData.PointData] {
        points.map { point in
            let unity = ARScanController.unityFromARKit(point.position)
            return ScanData.PointData(
                uuid: point.uuid,
                pointType: point.type,
                position: .init(x: unity.x, y: unity.y, z: unity.z),
                notes: point.notes,
                index: point.index
            )
        }
    }

    /// An unsaved scan for the review screens to render. There is no mesh
    /// filename because the mesh is not exported until save — and the shape
    /// of the perimeter is what a rep is checking at this point anyway.
    var previewScanData: ScanData {
        ScanData(
            uuid: "",
            timeStamp: Int64(Date().timeIntervalSince1970),
            meshString: "",
            pointsData: pointsDataForSave,
            startTime: startTime,
            endTime: ""
        )
    }

    // MARK: - Save (Unity FsmScanFeature.OnSaveScanBtnClick)

    /// Saves mesh + scan + project and returns the updated project.
    func saveScan(into project: ProjectData) -> ProjectData {
        let endTime = Self.isoFormatter.string(from: Date())
        let scanUuid = UUID().uuidString
        let timeStamp = Int64(Date().timeIntervalSince1970)

        // 1. Combined mesh -> Documents/Meshes/<guid>.dat (Unity text format).
        var meshFileName = ""
        if let meshString = controller.exportUnityMeshString() {
            meshFileName = (try? ProjectStore.saveMesh(meshString)) ?? ""
        }

        // 2. ScanData JSON -> Documents/Project/Scans/0-<uuid>.json.
        let pointsData = pointsDataForSave

        let scanData = ScanData(
            uuid: scanUuid,
            timeStamp: timeStamp,
            meshString: meshFileName,
            pointsData: pointsData,
            startTime: startTime,
            endTime: endTime
        )

        var updated = project

        // Re-scanning replaces the previous scan (and our port also removes
        // the old mesh, which Unity leaks).
        if let oldScan = updated.scan {
            if let oldScanData = ProjectStore.loadScan(fileName: oldScan.fileName),
               !oldScanData.meshString.isEmpty {
                try? FileManager.default.removeItem(
                    at: ProjectStore.meshesFolder.appendingPathComponent(oldScanData.meshString))
            }
            ProjectStore.deleteScanFile(fileName: oldScan.fileName)
        }

        let scanFileName = "\(updated.totalScansAdded)-\(scanUuid)"
        guard let savedName = try? ProjectStore.saveScan(scanData, fileName: scanFileName) else {
            return project
        }

        // 3. Update the project (.msr).
        updated.scan = .init(fileName: savedName, uuid: scanUuid, timeStamp: timeStamp)
        _ = try? ProjectStore.save(&updated)

        AppLog.log("Scan saved: \(pointsData.count) points, mesh: \(meshFileName.isEmpty ? "none" : meshFileName)")
        Haptics.success()
        controller.pauseSession()
        return updated
    }
}
