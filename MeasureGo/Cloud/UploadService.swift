//
//  UploadService.swift
//  MeasureGo
//
//  Orchestrates the portal upload — port of Unity's
//  ProjectDataSerializer.SaveProjectDataAsync + ProjectCloud/ResourceCloud
//  sequencing, with the archive race fixed by uploading strictly in order:
//  project JSON first, then photos, CSVs, and finally the tar.gz archive.
//

import Foundation

enum UploadService {

    struct UploadItem {
        let fileURL: URL
        let resourceId: String
        let revision: Int
    }

    /// A project staged on disk in the folder layout the portal expects, plus
    /// the tar.gz of that layout. Either upload it, or share the archive
    /// straight off the device — both start from the same staged tree, so the
    /// file a field rep shares is byte-identical to what the portal receives.
    struct PreparedProject {
        let stagingDir: URL
        let archiveURL: URL
        let projectId: String
        let projectJSON: Data
        let uploadItems: [UploadItem]

        /// The staged tree is only needed while its individual files are being
        /// uploaded — the archive already holds a copy of all of it.
        func removeStagingDirectory() {
            try? FileManager.default.removeItem(at: stagingDir)
        }

        func removeArchive() {
            try? FileManager.default.removeItem(at: archiveURL)
        }
    }

    /// Stages the project and writes the archive, without touching the network.
    ///
    /// - Parameter archiveDestination: where to write the tar.gz. Defaults to
    ///   Unity's `Documents/Archives/{guid}.tar.gz`, which is the name the
    ///   portal expects; the share path passes a readable name in tmp instead.
    static func prepare(
        project: ProjectData,
        archiveDestination: URL? = nil
    ) async throws -> PreparedProject {
        let fm = FileManager.default
        var contract = ProjectDataContract(project: project)
        var uploadItems: [UploadItem] = []

        // Temp working dir (Unity: tmp/Project-{name}-{id}).
        let safeName = project.name.replacingOccurrences(of: "/", with: "%")
        let tempDir = fm.temporaryDirectory.appendingPathComponent("Project-\(safeName)-\(project.id)")
        if fm.fileExists(atPath: tempDir.path) {
            try fm.removeItem(at: tempDir)
        }
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let archivesDir = ProjectStore.projectFolder.deletingLastPathComponent()
            .appendingPathComponent("Archives", isDirectory: true)
        var archiveURL: URL?

        do {
            let resourcesDir = tempDir.appendingPathComponent("resources", isDirectory: true)
            let imagesDir = resourcesDir.appendingPathComponent("images", isDirectory: true)
            let featuresDir = tempDir.appendingPathComponent("features", isDirectory: true)
            let scansDir = tempDir.appendingPathComponent("scans", isDirectory: true)
            try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: featuresDir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()

            // --- Photos -> resources/images/{i}-{uuid}.{jpg|png} + descriptor ---
            for (i, photo) in project.photos.enumerated() {
                let source = ProjectStore.imageURL(fileName: photo.fileName)
                guard fm.fileExists(atPath: source.path) else { continue }

                // Follow the file that is actually on disk: projects created
                // before photos moved to JPEG still hold .png.
                let storedExtension = (photo.fileName as NSString).pathExtension.lowercased()
                let ext = storedExtension.isEmpty ? ProjectStore.photoFileExtension : storedExtension
                let photoName = "\(i)-\(photo.uuid).\(ext)"
                let dest = imagesDir.appendingPathComponent(photoName)
                try fm.copyItem(at: source, to: dest)

                let resource = ResourceContract(
                    id: photo.uuid,
                    name: photoName,
                    updateTime: photo.updateTime.isEmpty ? UploadContractTime.now() : photo.updateTime,
                    projectId: project.id,
                    type: "user image",
                    mimeType: ext == "png" ? "image/png" : "image/jpeg"
                )
                contract.resources.append(resource)
                try encoder.encode(resource)
                    .write(to: imagesDir.appendingPathComponent("Resource-\(i)-\(photo.uuid).json"))
                uploadItems.append(UploadItem(fileURL: dest, resourceId: resource.id, revision: 0))
            }

            // --- Archive resource descriptor (file added to the queue last) ---
            let archiveGuid = UUID().uuidString
            let archiveResource = ResourceContract(
                id: archiveGuid,
                name: archiveGuid,
                updateTime: UploadContractTime.now(),
                projectId: project.id,
                type: "archive",
                mimeType: "application/gzip"
            )

            // --- Scan + features ---
            if let scanRef = project.scan,
               let scanData = ProjectStore.loadScan(fileName: scanRef.fileName) {

                var scanContract = ScanDataContract(
                    id: scanData.uuid,
                    projectId: project.id,
                    createdByUserId: AuthManager.shared.userId ?? "",
                    startTime: scanData.startTime,
                    endTime: scanData.endTime,
                    location: project.location
                )

                let scanResourceGuid = UUID().uuidString
                let scanCSVResource = ResourceContract(
                    id: scanResourceGuid,
                    name: scanResourceGuid,
                    updateTime: UploadContractTime.now(),
                    projectId: project.id,
                    type: "raw point cloud",
                    mimeType: "text/plain"
                )
                scanContract.resources.append(scanCSVResource)

                let scanDirIndex = scansDir.appendingPathComponent("0", isDirectory: true)
                let scanResourcesDir = scanDirIndex.appendingPathComponent("resources", isDirectory: true)
                try fm.createDirectory(at: scanResourcesDir, withIntermediateDirectories: true)

                try encoder.encode(scanContract)
                    .write(to: scanDirIndex.appendingPathComponent("Scan-\(scanContract.id).json"))
                try encoder.encode(scanCSVResource)
                    .write(to: scanResourcesDir.appendingPathComponent("Resource-raw_point_cloud-\(scanResourceGuid).json"))

                let scanCSVURL = scanResourcesDir.appendingPathComponent("raw_point_cloud.csv")
                try RawPointCloudCSV.generate(scanData.pointsData)
                    .write(to: scanCSVURL, atomically: true, encoding: .utf8)
                uploadItems.append(UploadItem(fileURL: scanCSVURL, resourceId: scanCSVResource.id, revision: 0))

                contract.scans.append(scanContract)

                // One feature per point type present (Unity iterates the enum
                // in numeric order; featureIndex starts at 1).
                var featureIndex = 1
                for pointType in PointType.allCases where pointType != .none {
                    let pointsOfType = scanData.pointsData.filter { $0.pointType == pointType }
                    guard !pointsOfType.isEmpty else { continue }

                    var feature = FeatureContract(projectId: project.id, pointType: pointType)

                    let resourceGuid = UUID().uuidString
                    let csvResource = ResourceContract(
                        id: resourceGuid,
                        name: resourceGuid,
                        updateTime: UploadContractTime.now(),
                        projectId: project.id,
                        type: "raw point cloud",
                        mimeType: "text/plain"
                    )
                    feature.resources.append(csvResource)
                    contract.features.append(feature)

                    let featureDir = featuresDir.appendingPathComponent("\(featureIndex)", isDirectory: true)
                    let featureResourcesDir = featureDir.appendingPathComponent("resources", isDirectory: true)
                    try fm.createDirectory(at: featureResourcesDir, withIntermediateDirectories: true)

                    try encoder.encode(feature)
                        .write(to: featureDir.appendingPathComponent("Feature-\(feature.name)-\(feature.id).json"))
                    try encoder.encode(csvResource)
                        .write(to: featureResourcesDir.appendingPathComponent("Resource-raw_point_cloud-\(resourceGuid).json"))

                    let csvURL = featureResourcesDir.appendingPathComponent("raw_point_cloud.csv")
                    try RawPointCloudCSV.generate(pointsOfType)
                        .write(to: csvURL, atomically: true, encoding: .utf8)
                    uploadItems.append(UploadItem(fileURL: csvURL, resourceId: csvResource.id, revision: 0))

                    featureIndex += 1
                }
            }

            // --- Project JSON (includes the archive's own descriptor) ---
            contract.resources.append(archiveResource)
            let projectJSON = try encoder.encode(contract)
            try projectJSON.write(
                to: tempDir.appendingPathComponent("Project-\(safeName)-\(project.id).json"))

            // --- Archive: tar the staged tree, then gzip it ---
            let archive = archiveDestination
                ?? archivesDir.appendingPathComponent("\(archiveGuid).tar.gz")
            try TarGzWriter.createArchive(of: tempDir, to: archive)
            archiveURL = archive
            uploadItems.append(UploadItem(fileURL: archive, resourceId: archiveGuid, revision: 0))

            return PreparedProject(
                stagingDir: tempDir,
                archiveURL: archive,
                projectId: contract.id,
                projectJSON: projectJSON,
                uploadItems: uploadItems
            )
        } catch {
            // Never leave a half-written staging tree or archive behind.
            try? fm.removeItem(at: tempDir)
            if let archiveURL {
                try? fm.removeItem(at: archiveURL)
            }
            throw error
        }
    }

    /// Builds the archive for sharing off the device with the system share
    /// sheet. The staged tree is cleaned up before returning; the caller owns
    /// the returned file.
    ///
    /// Written to tmp rather than Documents/Archives so the system reclaims it
    /// if a share is abandoned — nothing here deletes it on dismissal, because
    /// AirDrop can still be reading the file after the sheet closes.
    static func prepareArchiveForSharing(project: ProjectData) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(shareFileName(for: project))
        try? FileManager.default.removeItem(at: destination)

        let prepared = try await prepare(project: project, archiveDestination: destination)
        prepared.removeStagingDirectory()
        AppLog.log("Archive ready to share: \(destination.lastPathComponent)")
        return prepared.archiveURL
    }

    /// Readable name for a shared archive — a GUID tells the recipient nothing.
    private static func shareFileName(for project: ProjectData) -> String {
        let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let safe = (trimmed.isEmpty ? "Project" : trimmed)
            .components(separatedBy: illegal)
            .joined(separator: "-")
        return "\(safe)-\(project.id).tar.gz"
    }

    /// Builds the archive and uploads everything.
    /// Returns the project with status = true on full success.
    static func upload(project: ProjectData) async throws -> ProjectData {
        let prepared = try await prepare(project: project)
        defer {
            prepared.removeStagingDirectory()
            prepared.removeArchive() // Unity's _deleteArchive = true
        }

        // --- Upload: project first, then every resource sequentially ---
        try await CloudAPI.putProject(id: prepared.projectId, jsonData: prepared.projectJSON)
        for item in prepared.uploadItems {
            try await CloudAPI.putResourceFile(
                resourceId: item.resourceId,
                revision: item.revision,
                fileURL: item.fileURL
            )
        }

        // Success: mark uploaded and persist, like Unity's OnUploaded.
        var updated = project
        updated.status = true
        try ProjectStore.save(&updated)
        return updated
    }
}
