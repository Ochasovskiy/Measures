//
//  NewProjectViewModel.swift
//  MeasureGo
//
//  State + save logic for the new-project flow (Unity FsmMain.SaveProject).
//

import UIKit
import Combine

@MainActor
final class NewProjectViewModel: ObservableObject {

    // Form fields (Unity's new-project panel inputs)
    @Published var projectName = ""
    @Published var contactName = ""
    @Published var email = ""
    @Published var phone = ""
    @Published var address1 = ""
    @Published var address2 = ""
    @Published var city = ""
    @Published var state = ""
    @Published var zip = ""
    @Published var notes = ""

    // Photos: first one becomes the project's main photo
    @Published var photos: [UIImage] = []

    static let maxPhotoCount = 4

    // Unity's per-photo capture tips
    static let tips = [
        "Take a minimum of four pictures to best display the pool project",
        "Take a picture of Side B of the pool",
        "Take a picture of Side C of the pool",
        "Take a picture of Side D of the pool",
    ]

    var currentTip: String {
        Self.tips[min(photos.count, Self.tips.count - 1)]
    }

    /// Mirrors FsmMain.SaveProject: builds ProjectData, stores the photos as
    /// image-<n>-<uuid>.png, saves the .msr file.
    func save() throws -> ProjectData {
        var project = ProjectData()
        project.name = projectName
        project.customer = .init(name: contactName, email: email, phone: phone)
        project.address = .init(address1: address1, address2: address2, city: city,
                                state: state, postalcode: zip, country: "")
        // TODO: GPS coordinates (Unity reads them from GpsLocation here) —
        // location plumbing arrives with the AR step.
        project.notes = notes

        for (index, image) in photos.enumerated() {
            let uuid = UUID().uuidString
            let fileName = ProjectStore.photoFileName(uuid: uuid, counter: project.totalPhotosAdded)
            let savedName = try ProjectStore.savePNG(image, fileName: fileName)
            if index == 0 {
                project.setMainPhotoInfo(photoName: savedName, photoUuid: uuid)
            }
            project.addPhoto(fileName: savedName, uuid: uuid)
        }

        try ProjectStore.save(project)
        return project
    }
}
