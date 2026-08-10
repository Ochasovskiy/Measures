//
//  UploadContracts.swift
//  MeasureGo
//
//  Portal upload data contracts, ported field-for-field from Unity's
//  ProjectDataSerializer.cs ([DataContract] classes) and RawPointCloudCSV.
//

import Foundation

enum UploadContractTime {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func now() -> String {
        formatter.string(from: Date())
    }
}

struct ResourceContract: Encodable {
    var id: String
    var name: String
    var updateTime: String
    var projectId: String
    var scanId: String? = nil
    var revision: Int = 0
    var type: String
    var captureSource: String = "mobile"
    var mimeType: String
    var status: String = "pending"
    var tags: [String] = []

    // Explicit encode so scanId serializes as null (DataContractJsonSerializer
    // writes "scanId":null; synthesized Codable would omit the key).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(updateTime, forKey: .updateTime)
        try c.encode(projectId, forKey: .projectId)
        try c.encode(scanId, forKey: .scanId)
        try c.encode(revision, forKey: .revision)
        try c.encode(type, forKey: .type)
        try c.encode(captureSource, forKey: .captureSource)
        try c.encode(mimeType, forKey: .mimeType)
        try c.encode(status, forKey: .status)
        try c.encode(tags, forKey: .tags)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, updateTime, projectId, scanId, revision, type, captureSource, mimeType, status, tags
    }
}

struct ScanDataContract: Encodable {
    var id: String
    var projectId: String
    var createdByUserId: String
    var startTime: String
    var endTime: String
    var location: ProjectData.Location
    var resources: [ResourceContract] = []
}

struct FeatureContract: Encodable {
    var id: String
    var type: String       // display text, e.g. "Perimeter"
    var projectId: String
    var updateTime: String
    var name: String       // portal name, e.g. "LM_001_perimeter"
    var notes: String = ""
    var isInsidePool: Bool = false
    var isRemovable: Bool = false
    var stepFastener: String = ""
    var tags: [String] = []
    var scans: [String] = []
    var resources: [ResourceContract] = []

    init(projectId: String, pointType: PointType) {
        self.id = UUID().uuidString
        self.type = pointType.displayName
        self.projectId = projectId
        self.updateTime = UploadContractTime.now()
        self.name = pointType.jsonFeatureName
    }
}

struct ProjectDataContract: Encodable {
    var id: String
    var name: String
    var status: String = "active"
    var customer: ProjectData.Customer
    var address: ProjectData.Address
    var location: ProjectData.Location
    var notes: String
    var primaryImageId: String
    var scans: [ScanDataContract] = []
    var resources: [ResourceContract] = []
    var features: [FeatureContract] = []

    init(project: ProjectData) {
        id = project.id
        name = project.name
        customer = project.customer
        address = project.address
        location = project.location
        notes = project.notes
        primaryImageId = project.primaryImageId
    }
}

/// Unity's RawPointCloudCSV: 2D plan view — column x = Unity x, column
/// y = Unity z, column z is literally "0" (height dropped on purpose).
enum RawPointCloudCSV {
    static func generate(_ points: [ScanData.PointData]) -> String {
        var csv = "last_distance_valid,x,y,z,user_tagged,user_tagged_index,notes,id,arc_start,arc_end,arc_err_type,arc_acceptable,on_deck\n"
        for p in points {
            // Sanitize notes: Unity writes them raw, where a comma corrupts
            // the row — we strip separators instead of copying that bug.
            let notes = p.notes
                .replacingOccurrences(of: ",", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            csv += "True,\(p.position.x),\(p.position.z),0,True,\(p.index),\(notes),\(p.uuid),False,False,no error,False,True\n"
        }
        return csv
    }
}
