//
//  ProjectDetailsView.swift
//  MeasureGo
//
//  Native remake of Unity's GuiWindowDetailsView / FsmDetails:
//  Details / Photos / Pool tabs. Field edits save immediately; uploaded
//  projects are read-only.
//

import SwiftUI
import PhotosUI

struct ProjectDetailsView: View {

    private enum Tab: String, CaseIterable {
        case details = "Details"
        case photos = "Photos"
        case pool = "Pool"
    }

    @StateObject private var viewModel: ProjectDetailsViewModel
    @State private var tab: Tab = .details
    @Environment(\.dismiss) private var dismiss

    init(project: ProjectData) {
        _viewModel = StateObject(wrappedValue: ProjectDetailsViewModel(project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 16) {
                Picker("Tab", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 16)

                switch tab {
                case .details:
                    DetailsTabView(viewModel: viewModel)
                case .photos:
                    PhotosTabView(viewModel: viewModel)
                case .pool:
                    PoolTabView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MainView.background)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }

            Text(viewModel.project.name.isEmpty ? "Project" : viewModel.project.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Text(viewModel.isUploaded ? "Uploaded" : "Not uploaded")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(viewModel.isUploaded ? Color.green.opacity(0.85) : MainView.salmon)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background(MainView.navy)
    }
}

// MARK: - Details tab

private struct DetailsTabView: View {

    @ObservedObject var viewModel: ProjectDetailsViewModel
    @FocusState private var emailFocused: Bool

    private var emailInvalid: Bool {
        let email = viewModel.project.customer.email
        return !email.isEmpty && !InputRules.isValidEmail(email)
    }

    var body: some View {
        Form {
            if let photo = viewModel.mainPhoto {
                Section {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Project") {
                field("Project name", "No project name added", \.name)
            }

            Section("Contact") {
                field("Full name", "No name added", \.customer.name)
                VStack(alignment: .leading, spacing: 4) {
                    field("Email", "No email added", \.customer.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($emailFocused)
                    if emailInvalid && !emailFocused {
                        Text("Invalid email address")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                field("Phone", "No phone added", \.customer.phone, filter: InputRules.filterPhone)
                    .keyboardType(.phonePad)
            }

            Section("Address") {
                field("Address 1", "No address line 1 added", \.address.address1)
                field("Address 2", "No address line 2 added", \.address.address2)
                field("City", "No city added", \.address.city)
                field("State", "No state added", \.address.state)
                field("Zip", "No ZIP added", \.address.postalcode, filter: InputRules.filterZip)
                    .keyboardType(.numberPad)
            }

            Section("Notes") {
                TextField("No notes added", text: binding(\.notes), axis: .vertical)
                    .lineLimit(3...6)
                    .disabled(viewModel.isUploaded)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func field(
        _ label: String,
        _ placeholder: String,
        _ keyPath: WritableKeyPath<ProjectData, String>,
        filter: ((String) -> String)? = nil
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            TextField(placeholder, text: binding(keyPath, filter: filter))
                .multilineTextAlignment(.trailing)
                .disabled(viewModel.isUploaded)
        }
    }

    private func binding(
        _ keyPath: WritableKeyPath<ProjectData, String>,
        filter: ((String) -> String)? = nil
    ) -> Binding<String> {
        Binding(
            get: { viewModel.project[keyPath: keyPath] },
            set: { newValue in
                let value = filter?(newValue) ?? newValue
                guard value != viewModel.project[keyPath: keyPath] else { return }
                viewModel.update { $0[keyPath: keyPath] = value }
            }
        )
    }
}

// MARK: - Photos tab

private struct PhotosTabView: View {

    @ObservedObject var viewModel: ProjectDetailsViewModel

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var photoToDelete: ProjectData.Photo?

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(viewModel.project.photos, id: \.uuid) { photo in
                        photoCell(photo)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)

            if !viewModel.isUploaded {
                VStack(spacing: 12) {
                    if cameraAvailable {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MainView.navy)
                    }
                    PhotosPicker(selection: $pickerItems, matching: .images) {
                        Label("Add from library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(MainView.navy)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.addPhoto(image)
                    }
                }
                pickerItems = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                viewModel.addPhoto(image)
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "Do you really want to delete the photo?",
            isPresented: Binding(
                get: { photoToDelete != nil },
                set: { if !$0 { photoToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let photo = photoToDelete {
                    viewModel.deletePhoto(photo)
                }
                photoToDelete = nil
            }
            Button("Cancel", role: .cancel) { photoToDelete = nil }
        }
    }

    @ViewBuilder
    private func photoCell(_ photo: ProjectData.Photo) -> some View {
        if let image = ProjectStore.loadImage(fileName: photo.fileName) {
            Color.clear
                .frame(height: 110)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if !viewModel.isUploaded {
                        Button {
                            photoToDelete = photo
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, MainView.salmon)
                        }
                        .padding(4)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if photo.uuid == viewModel.project.primaryImageId {
                        Text("Main")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MainView.navy)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .padding(4)
                    }
                }
        }
    }
}

// MARK: - Pool tab

private struct PoolTabView: View {

    @ObservedObject var viewModel: ProjectDetailsViewModel
    @State private var showRescanConfirm = false
    @State private var showScanScreen = false
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var sessionExpired = false

    var body: some View {
        VStack(spacing: 16) {
            if let scan = viewModel.project.scan {
                HStack(spacing: 12) {
                    Image(systemName: "cube.transparent")
                        .font(.title2)
                        .foregroundStyle(MainView.navy)
                        .frame(width: 44, height: 44)
                        .background(MainView.background)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pool scan")
                            .font(.headline)
                            .foregroundStyle(MainView.navy)
                        // Unity stores the scan timestamp in unix seconds.
                        Text(Date(timeIntervalSince1970: TimeInterval(scan.timeStamp)),
                             format: .dateTime.day().month().year().hour().minute())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let scanData = ProjectStore.loadScan(fileName: scan.fileName) {
                            Text("\(scanData.pointsData.count) points\(scanData.meshString.isEmpty ? "" : " + mesh")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
            } else {
                Text("No scan yet")
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
            }

            Spacer()

            if !viewModel.isUploaded {
                VStack(spacing: 12) {
                    Button {
                        if viewModel.hasScan {
                            showRescanConfirm = true
                        } else {
                            showScanScreen = true
                        }
                    } label: {
                        Label("Start scan", systemImage: "camera.metering.matrix")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MainView.navy)

                    if viewModel.hasScan {
                        Button {
                            startUpload()
                        } label: {
                            Label("Upload", systemImage: "icloud.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(MainView.navy)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .overlay {
            if isUploading {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text("Please wait\nUploading")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .background(MainView.navy.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
        }
        .confirmationDialog(
            "Are you sure you want to start scanning?\nThe previous scan will be deleted.",
            isPresented: $showRescanConfirm,
            titleVisibility: .visible
        ) {
            Button("Yes") { showScanScreen = true }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showScanScreen) {
            ARScanView(project: viewModel.project) { updated in
                viewModel.project = updated
            }
        }
        .alert(
            "Upload failed",
            isPresented: Binding(
                get: { uploadError != nil },
                set: { if !$0 { uploadError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
        .alert("Your session has expired.", isPresented: $sessionExpired) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please log out and log in again, then retry the upload.")
        }
    }

    private func startUpload() {
        isUploading = true
        Task {
            // Unity checks the token before uploading (FsmDetails.UploadPrj).
            switch await AuthManager.shared.checkToken() {
            case .invalid:
                isUploading = false
                sessionExpired = true
                return
            case .valid, .unreachable:
                break
            }

            do {
                let updated = try await UploadService.upload(project: viewModel.project)
                viewModel.project = updated
            } catch {
                uploadError = error.localizedDescription
            }
            isUploading = false
        }
    }
}
