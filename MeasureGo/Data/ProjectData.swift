//
//  ProjectData.swift
//  MeasureGo
//
//  Codable port of Unity's ProjectData.cs. The JSON layout must stay
//  byte-compatible with the Unity app's .msr files (JsonUtility output):
//  same field names, all fields present when encoding.
//

import Foundation

struct ProjectData: Codable, Hashable, Identifiable {

    struct Customer: Codable, Hashable {
        var name: String = ""
        var email: String = ""
        var phone: String = ""
    }

    struct Address: Codable, Hashable {
        var address1: String = ""
        var address2: String = ""
        var city: String = ""
        var state: String = ""
        var postalcode: String = ""
        var country: String = ""
    }

    struct Location: Codable, Hashable {
        var latitude: Float = 0
        var longitude: Float = 0
    }

    struct Photo: Codable, Hashable {
        var fileName: String
        var uuid: String
        var updateTime: String
    }

    struct Scan: Codable, Hashable {
        var fileName: String
        var uuid: String
        var timeStamp: Int64
    }

    /// Unity's Vector3 as serialized by JsonUtility: {"x":…,"y":…,"z":…}
    struct Vector3: Codable, Hashable {
        var x: Float = 0
        var y: Float = 0
        var z: Float = 0
    }

    var fileName: String = ""
    var id: String
    var name: String = ""
    /// true once the project has been uploaded to the portal
    var status: Bool = false
    var customer: Customer = Customer()
    var address: Address = Address()
    var location: Location = Location()
    var notes: String = ""
    var primaryImageId: String = ""
    var photos: [Photo] = []
    var totalPhotosAdded: Int = 0
    var photoFileName: String = ""
    var meshString: String = ""
    var points: [Vector3] = []
    var scan: Scan? = nil
    var totalScansAdded: Int = 0

    init(id: String = UUID().uuidString) {
        self.id = id
    }

    // Tolerant decoding: any field missing in an older .msr file falls back
    // to its default instead of failing the whole project.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        status = try c.decodeIfPresent(Bool.self, forKey: .status) ?? false
        customer = try c.decodeIfPresent(Customer.self, forKey: .customer) ?? Customer()
        address = try c.decodeIfPresent(Address.self, forKey: .address) ?? Address()
        location = try c.decodeIfPresent(Location.self, forKey: .location) ?? Location()
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        primaryImageId = try c.decodeIfPresent(String.self, forKey: .primaryImageId) ?? ""
        photos = try c.decodeIfPresent([Photo].self, forKey: .photos) ?? []
        totalPhotosAdded = try c.decodeIfPresent(Int.self, forKey: .totalPhotosAdded) ?? 0
        photoFileName = try c.decodeIfPresent(String.self, forKey: .photoFileName) ?? ""
        meshString = try c.decodeIfPresent(String.self, forKey: .meshString) ?? ""
        points = try c.decodeIfPresent([Vector3].self, forKey: .points) ?? []
        scan = try c.decodeIfPresent(Scan.self, forKey: .scan)
        totalScansAdded = try c.decodeIfPresent(Int.self, forKey: .totalScansAdded) ?? 0
    }

    mutating func setMainPhotoInfo(photoName: String, photoUuid: String) {
        photoFileName = photoName
        primaryImageId = photoUuid
    }

    mutating func addPhoto(fileName: String, uuid: String) {
        let updateTime = ISO8601DateFormatter().string(from: Date())
        photos.append(Photo(fileName: fileName, uuid: uuid, updateTime: updateTime))
        totalPhotosAdded += 1
    }

    mutating func removePhoto(uuid: String) {
        photos.removeAll { $0.uuid == uuid }
    }
}
