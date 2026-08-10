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
        let index: Int
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

    func placePoint() {
        let type: PointType = phase == .perimeter ? .perimeter : selectedFeatureType
        guard type != .none else { return }

        guard var position = controller.raycastFromCenter() else {
            placementFailed = true
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

        controller.addMarker(at: position, type: type)
        if type == .perimeter {
            controller.rebuildLines(through: perimeterPoints.map(\.position), closeLoop: false)
        }
        syncLockedHeight()
    }

    func undoLastPoint() {
        // Undo only removes points placed in the current phase, like Unity's
        // per-state _statePointList.
        let currentTypeFilter: (PlacedPoint) -> Bool = phase == .perimeter
            ? { $0.type == .perimeter }
            : { $0.type != .perimeter }
        guard let last = points.last, currentTypeFilter(last) else { return }

        points.removeLast()
        controller.removeLastMarker()
        if last.type == .perimeter {
            controller.rebuildLines(through: perimeterPoints.map(\.position), closeLoop: false)
        }
        syncLockedHeight()
    }

    var canUndo: Bool {
        guard let last = points.last else { return false }
        return phase == .perimeter ? last.type == .perimeter : last.type != .perimeter
    }

    func finishPerimeter() {
        controller.rebuildLines(through: perimeterPoints.map(\.position), closeLoop: true)
        phase = .features
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
        let pointsData = points.map { point -> ScanData.PointData in
            let unity = ARScanController.unityFromARKit(point.position)
            return ScanData.PointData(
                uuid: point.uuid,
                pointType: point.type,
                position: .init(x: unity.x, y: unity.y, z: unity.z),
                notes: point.notes,
                index: point.index
            )
        }

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
        try? ProjectStore.save(updated)

        controller.pauseSession()
        return updated
    }
}
