//
//  ProjectDetailsViewModel.swift
//  MeasureGo
//
//  Details-screen logic from Unity's FsmDetails: every field edit and photo
//  change immediately persists the .msr file.
//

import UIKit
import Combine

@MainActor
final class ProjectDetailsViewModel: ObservableObject {

    @Published var project: ProjectData

    init(project: ProjectData) {
        self.project = project
    }

    /// Uploaded projects are read-only (Unity's SetLoaded).
    var isUploaded: Bool { project.status }
    var hasScan: Bool { project.scan != nil }

    var mainPhoto: UIImage? {
        ProjectStore.loadImage(fileName: project.photoFileName)
    }

    func update(_ mutate: (inout ProjectData) -> Void) {
        mutate(&project)
        save()
    }

    func addPhoto(_ image: UIImage) {
        let uuid = UUID().uuidString
        let fileName = ProjectStore.photoFileName(uuid: uuid, counter: project.totalPhotosAdded)
        guard let savedName = try? ProjectStore.savePNG(image, fileName: fileName) else { return }
        project.addPhoto(fileName: savedName, uuid: uuid)
        // First photo also becomes the project's main photo.
        if project.photoFileName.isEmpty {
            project.setMainPhotoInfo(photoName: savedName, photoUuid: uuid)
        }
        save()
    }

    func deletePhoto(_ photo: ProjectData.Photo) {
        project.removePhoto(uuid: photo.uuid)
        try? FileManager.default.removeItem(at: ProjectStore.imageURL(fileName: photo.fileName))
        if project.primaryImageId == photo.uuid {
            project.photoFileName = project.photos.first?.fileName ?? ""
            project.primaryImageId = project.photos.first?.uuid ?? ""
        }
        save()
    }

    private func save() {
        try? ProjectStore.save(project)
    }
}
