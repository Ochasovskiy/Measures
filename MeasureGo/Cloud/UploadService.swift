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

    /// Builds the temp directory + archive and uploads everything.
    /// Returns the project with status = true on full success.
    static func upload(project: ProjectData) async throws -> ProjectData {
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

        defer {
            try? fm.removeItem(at: tempDir)
            if let archiveURL {
                try? fm.removeItem(at: archiveURL) // Unity's _deleteArchive = true
            }
        }

        do {
            let resourcesDir = tempDir.appendingPathComponent("resources", isDirectory: true)
            let imagesDir = resourcesDir.appendingPathComponent("images", isDirectory: true)
            let featuresDir = tempDir.appendingPathComponent("features", isDirectory: true)
            let scansDir = tempDir.appendingPathComponent("scans", isDirectory: true)
            try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: featuresDir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()

            // --- Photos -> resources/images/{i}-{uuid}.png + descriptor ---
            for (i, photo) in project.photos.enumerated() {
                let source = ProjectStore.imageURL(fileName: photo.fileName)
                guard fm.fileExists(atPath: source.path) else { continue }

                let photoName = "\(i)-\(photo.uuid).png"
                let dest = imagesDir.appendingPathComponent(photoName)
                try fm.copyItem(at: source, to: dest)

                let resource = ResourceContract(
                    id: photo.uuid,
                    name: photoName,
                    updateTime: photo.updateTime.isEmpty ? UploadContractTime.now() : photo.updateTime,
                    projectId: project.id,
                    type: "user image",
                    mimeType: "image/png"
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

            // --- Archive: Documents/Archives/{guid}.tar.gz ---
            let archive = archivesDir.appendingPathComponent("\(archiveGuid).tar.gz")
            try TarGzWriter.createArchive(of: tempDir, to: archive)
            archiveURL = archive
            uploadItems.append(UploadItem(fileURL: archive, resourceId: archiveGuid, revision: 0))

            // --- Upload: project first, then every resource sequentially ---
            try await CloudAPI.putProject(id: contract.id, jsonData: projectJSON)
            for item in uploadItems {
                try await CloudAPI.putResourceFile(
                    resourceId: item.resourceId,
                    revision: item.revision,
                    fileURL: item.fileURL
                )
            }
        }

        // Success: mark uploaded and persist, like Unity's OnUploaded.
        var updated = project
        updated.status = true
        try ProjectStore.save(&updated)
        return updated
    }
}
