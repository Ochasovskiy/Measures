//
//  ProjectStore.swift
//  MeasureGo
//
//  Port of Unity's FileManager.cs. Projects live as .msr JSON files in
//  Documents/Project, photos as PNGs in Documents/Project/Images, scans in
//  Documents/Project/Scans — same layout as the Unity app's persistentDataPath.
//

import Foundation
import UIKit

struct ProjectFile {
    let url: URL
    let creationDate: Date
    let data: ProjectData
}

enum ProjectStore {

    static let msrExtension = "msr"

    static var projectFolder: URL {
        documentsFolder.appendingPathComponent("Project", isDirectory: true)
    }

    static var imagesFolder: URL {
        projectFolder.appendingPathComponent("Images", isDirectory: true)
    }

    static var scansFolder: URL {
        projectFolder.appendingPathComponent("Scans", isDirectory: true)
    }

    /// Documents/Meshes — scanned pool meshes in Unity's .dat text format.
    static var meshesFolder: URL {
        documentsFolder.appendingPathComponent("Meshes", isDirectory: true)
    }

    private static var documentsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Projects

    static func loadAllProjects() -> [ProjectFile] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: projectFolder,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return urls
            .filter { $0.pathExtension == msrExtension }
            .compactMap { url in
                guard let jsonData = try? Data(contentsOf: url),
                      let data = try? JSONDecoder().decode(ProjectData.self, from: jsonData)
                else { return nil }
                let creation = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return ProjectFile(url: url, creationDate: creation, data: data)
            }
    }

    /// Reloads a single project from disk by its file name.
    static func loadProject(fileName: String) -> ProjectData? {
        guard !fileName.isEmpty else { return nil }
        let url = projectFolder.appendingPathComponent(fileName).appendingPathExtension(msrExtension)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProjectData.self, from: data)
    }

    @discardableResult
    static func save(_ project: ProjectData) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: projectFolder, withIntermediateDirectories: true)

        let fileName = project.fileName.isEmpty ? randomFileName() : project.fileName
        var toSave = project
        toSave.fileName = fileName

        let encoder = JSONEncoder()
        let data = try encoder.encode(toSave)
        let url = projectFolder.appendingPathComponent(fileName).appendingPathExtension(msrExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func delete(_ project: ProjectData) {
        let fm = FileManager.default
        let url = projectFolder.appendingPathComponent(project.fileName).appendingPathExtension(msrExtension)
        try? fm.removeItem(at: url)

        // Remove the project's photos like Unity's FileManager.DeleteProjectFile.
        for photo in project.photos {
            try? fm.removeItem(at: imageURL(fileName: photo.fileName))
        }
        if !project.photoFileName.isEmpty {
            try? fm.removeItem(at: imageURL(fileName: project.photoFileName))
        }

        // Remove the scan, its point photos, and its mesh (Unity leaks the
        // mesh .dat — we clean it up deliberately).
        if let scan = project.scan {
            if let scanData = loadScan(fileName: scan.fileName) {
                for point in scanData.pointsData where !point.photoUuid.isEmpty {
                    try? fm.removeItem(at: imageURL(fileName: point.photoUuid))
                }
                if !scanData.meshString.isEmpty {
                    try? fm.removeItem(at: meshesFolder.appendingPathComponent(scanData.meshString))
                }
            }
            deleteScanFile(fileName: scan.fileName)
        }
    }

    // MARK: - Scans

    static func loadScan(fileName: String) -> ScanData? {
        guard !fileName.isEmpty,
              let data = try? Data(contentsOf: scansFolder.appendingPathComponent(fileName))
        else { return nil }
        return try? JSONDecoder().decode(ScanData.self, from: data)
    }

    /// Saves ScanData as Project/Scans/<fileName>.json and returns the full
    /// file name (Unity's FileManager.SaveScanFile).
    @discardableResult
    static func saveScan(_ scan: ScanData, fileName: String) throws -> String {
        try FileManager.default.createDirectory(at: scansFolder, withIntermediateDirectories: true)
        let name = fileName.hasSuffix(".json") ? fileName : fileName + ".json"
        let data = try JSONEncoder().encode(scan)
        try data.write(to: scansFolder.appendingPathComponent(name), options: .atomic)
        return name
    }

    static func deleteScanFile(fileName: String) {
        guard !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: scansFolder.appendingPathComponent(fileName))
    }

    // MARK: - Meshes

    /// Saves a mesh string as Documents/Meshes/<uuid>.dat and returns the file
    /// name (Unity's FileManager.SaveMeshToFile).
    static func saveMesh(_ meshString: String) throws -> String {
        try FileManager.default.createDirectory(at: meshesFolder, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".dat"
        try meshString.write(to: meshesFolder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        return name
    }

    static func loadMeshString(fileName: String) -> String? {
        guard !fileName.isEmpty else { return nil }
        return try? String(contentsOf: meshesFolder.appendingPathComponent(fileName), encoding: .utf8)
    }

    // MARK: - Images

    static func imageURL(fileName: String) -> URL {
        let name = fileName.hasSuffix(".png") ? fileName : fileName + ".png"
        return imagesFolder.appendingPathComponent(name)
    }

    @discardableResult
    static func savePNG(_ image: UIImage, fileName: String) throws -> String {
        try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        guard let data = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        let name = fileName.hasSuffix(".png") ? fileName : fileName + ".png"
        try data.write(to: imagesFolder.appendingPathComponent(name), options: .atomic)
        return name
    }

    static func loadImage(fileName: String) -> UIImage? {
        guard !fileName.isEmpty,
              let data = try? Data(contentsOf: imageURL(fileName: fileName))
        else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Naming (mirrors Unity's FileManager)

    static func randomFileName() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func photoFileName(uuid: String, counter: Int) -> String {
        "image-\(counter)-\(uuid)"
    }
}
