//
//  ScanData.swift
//  MeasureGo
//
//  Codable port of Unity's ScanData.cs and PointTypeEnum.cs. The JSON must
//  stay compatible with the Unity app's scan files
//  (Documents/Project/Scans/<n>-<uuid>.json, written by JsonUtility).
//

import UIKit

enum PointType: Int, Codable, CaseIterable {
    case none = -1
    case perimeter = 0
    case anchor = 1
    case autocover = 2
    case deck = 3
    case divingBoard = 4
    case handrail = 5
    case informational = 6 // Calibration
    case paingerPot = 7    // Planter (Unity's original spelling)
    case slide = 8
    case spa = 9
    case step = 10
    case wall = 11
    case infoRef = 12      // Other
    case divingObject = 13

    var displayName: String {
        switch self {
        case .none: return "None"
        case .perimeter: return "Perimeter"
        case .anchor: return "Anchor"
        case .autocover: return "AutoCover"
        case .deck: return "Decking"
        case .divingBoard: return "Diving Board"
        case .handrail: return "Handrail"
        case .informational: return "Calibration"
        case .paingerPot: return "Planter"
        case .slide: return "Slide"
        case .spa: return "Spa"
        case .step: return "Steps"
        case .wall: return "Wall"
        case .infoRef: return "Other"
        case .divingObject: return "Diving object"
        }
    }

    /// Feature name used in the upload contracts (PointTypeEnum.GetJsonPointTypeName).
    var jsonFeatureName: String {
        switch self {
        case .none: return "None"
        case .perimeter: return "LM_001_perimeter"
        case .anchor: return "LM_000_anchor"
        case .autocover: return "LM_000_autocover"
        case .deck: return "LM_000_decking"
        case .divingBoard: return "LM_000_divingboard"
        case .handrail: return "LM_000_handrail"
        case .informational: return "LM_000_calibration"
        case .paingerPot: return "LM_000_planterpot"
        case .slide: return "LM_000_slide"
        case .spa: return "LM_000_spa"
        case .step: return "LM_000_steps"
        case .wall: return "LM_000_wall"
        case .infoRef: return "LM_000_other"
        case .divingObject: return "LM_000_divingobject"
        }
    }

    /// Marker colors from Unity's PointTypeEnum.PointTypeColors.
    var uiColor: UIColor {
        switch self {
        case .none, .perimeter: return .black
        case .anchor: return .red
        case .autocover: return UIColor(red: 0, green: 1, blue: 0, alpha: 1)
        case .deck: return UIColor(red: 0, green: 1, blue: 0.1, alpha: 1)
        case .divingBoard: return UIColor(red: 0, green: 1, blue: 0.2, alpha: 1)
        case .handrail: return UIColor(red: 0, green: 1, blue: 0.3, alpha: 1)
        case .informational: return UIColor(red: 0, green: 1, blue: 0.4, alpha: 1)
        case .paingerPot: return UIColor(red: 0, green: 1, blue: 0.5, alpha: 1)
        case .slide: return UIColor(red: 0, green: 1, blue: 0.6, alpha: 1)
        case .spa: return UIColor(red: 0, green: 1, blue: 0.7, alpha: 1)
        case .step: return UIColor(red: 0, green: 1, blue: 0.8, alpha: 1)
        case .wall: return UIColor(red: 0, green: 1, blue: 0.9, alpha: 1)
        case .infoRef, .divingObject: return UIColor(red: 0, green: 1, blue: 1, alpha: 1)
        }
    }

    /// Types offered in the feature-point selector (Unity's panel: everything
    /// real except the perimeter, which has its own phase).
    static var featureTypes: [PointType] {
        allCases.filter { $0 != .none && $0 != .perimeter }
    }
}

struct ScanData: Codable {

    struct PointData: Codable {
        var uuid: String
        var pointType: PointType
        var position: ProjectData.Vector3
        var notes: String = ""
        var index: Int = 0
        var photoUuid: String = ""

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            uuid = try c.decodeIfPresent(String.self, forKey: .uuid) ?? UUID().uuidString
            pointType = try c.decodeIfPresent(PointType.self, forKey: .pointType) ?? .none
            position = try c.decodeIfPresent(ProjectData.Vector3.self, forKey: .position) ?? .init()
            notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
            index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
            photoUuid = try c.decodeIfPresent(String.self, forKey: .photoUuid) ?? ""
        }

        init(uuid: String, pointType: PointType, position: ProjectData.Vector3, notes: String = "", index: Int = 0) {
            self.uuid = uuid
            self.pointType = pointType
            self.position = position
            self.notes = notes
            self.index = index
        }
    }

    var name: String = ""
    var uuid: String
    var timeStamp: Int64 // unix seconds, like Unity's ToUnixTimeSeconds
    /// File name of the mesh .dat in Documents/Meshes (not the mesh itself).
    var meshString: String = ""
    var points: [ProjectData.Vector3] = [] // legacy field, kept for compatibility
    var pointsData: [PointData] = []
    var startTime: String = ""
    var endTime: String = ""
    var totalPointsAdded: Int = 0

    init(uuid: String, timeStamp: Int64, meshString: String,
         pointsData: [PointData], startTime: String, endTime: String) {
        self.uuid = uuid
        self.timeStamp = timeStamp
        self.meshString = meshString
        self.pointsData = pointsData
        self.startTime = startTime
        self.endTime = endTime
        self.totalPointsAdded = pointsData.count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        uuid = try c.decodeIfPresent(String.self, forKey: .uuid) ?? UUID().uuidString
        timeStamp = try c.decodeIfPresent(Int64.self, forKey: .timeStamp) ?? 0
        meshString = try c.decodeIfPresent(String.self, forKey: .meshString) ?? ""
        points = try c.decodeIfPresent([ProjectData.Vector3].self, forKey: .points) ?? []
        pointsData = try c.decodeIfPresent([PointData].self, forKey: .pointsData) ?? []
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime) ?? ""
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime) ?? ""
        totalPointsAdded = try c.decodeIfPresent(Int.self, forKey: .totalPointsAdded) ?? 0
    }
}
