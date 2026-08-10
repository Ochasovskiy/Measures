//
//  NewProjectFlowView.swift
//  MeasureGo
//
//  New-project creation flow, mirroring Unity's FsmMain panels:
//  form -> photos -> review -> save.
//

import SwiftUI
import PhotosUI

struct NewProjectFlowView: View {

    @StateObject private var viewModel = NewProjectViewModel()
    @Environment(\.dismiss) private var dismiss

    let onSaved: (ProjectData) -> Void

    var body: some View {
        NavigationStack {
            FormStepView(viewModel: viewModel, onSaved: finish)
        }
        .onAppear {
            // Warm up the GPS fix so it is ready when the project is saved.
            LocationProvider.shared.start()
        }
    }

    private func finish() {
        do {
            let project = try viewModel.save()
            dismiss()
            onSaved(project)
        } catch {
            // Saving to Documents should not fail in practice; surface if it does.
            assertionFailure("Failed to save project: \(error)")
            dismiss()
        }
    }
}

// MARK: - Step 1: form

private struct FormStepView: View {

    @ObservedObject var viewModel: NewProjectViewModel
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void
    @FocusState private var emailFocused: Bool

    private var emailInvalid: Bool {
        !viewModel.email.isEmpty && !InputRules.isValidEmail(viewModel.email)
    }

    var body: some View {
        Form {
            Section("Project") {
                TextField("Project name", text: $viewModel.projectName)
            }
            Section("Contact") {
                TextField("Contact name", text: $viewModel.contactName)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Email", text: $viewModel.email)
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
                TextField("Phone", text: $viewModel.phone)
                    .keyboardType(.phonePad)
                    .onChange(of: viewModel.phone) { _, newValue in
                        viewModel.phone = InputRules.filterPhone(newValue)
                    }
            }
            Section {
                // Inline accessory: an optional helper for this field rather
                // than a step the user must take first.
                HStack(spacing: 8) {
                    TextField("Address 1", text: $viewModel.address1)
                    if viewModel.isLocatingAddress {
                        ProgressView()
                    } else {
                        Button {
                            viewModel.fillAddressFromLocation()
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.subheadline)
                                .foregroundStyle(MainView.navy)
                                .frame(width: 32, height: 32)
                                .background(MainView.background)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Fill address from current location")
                    }
                }
                TextField("Address 2", text: $viewModel.address2)
                TextField("City", text: $viewModel.city)
                TextField("State", text: $viewModel.state)
                TextField("Zip", text: $viewModel.zip)
                    .keyboardType(.numberPad)
                    .onChange(of: viewModel.zip) { _, newValue in
                        viewModel.zip = InputRules.filterZip(newValue)
                    }
            } header: {
                Text("Address")
            } footer: {
                Text("Tap the location icon to fill empty address fields from your current position.")
            }
            Section("Notes") {
                TextField("Additional notes", text: $viewModel.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("New project")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Location unavailable", isPresented: $viewModel.addressLookupFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No GPS fix yet, or location access is off. Check Settings → Privacy → Location Services, then try again.")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                NavigationLink("Next") {
                    PhotoStepView(viewModel: viewModel, onSaved: onSaved)
                }
                .disabled(viewModel.projectName.isEmpty || emailInvalid)
            }
        }
    }
}

// MARK: - Step 2: photos

private struct PhotoStepView: View {

    @ObservedObject var viewModel: NewProjectViewModel
    let onSaved: () -> Void

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(viewModel.currentTip)
                .font(.headline)
                .foregroundStyle(MainView.navy)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("\(viewModel.photos.count) / \(NewProjectViewModel.maxPhotoCount)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            photoGrid

            Spacer()

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

                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: NewProjectViewModel.maxPhotoCount - viewModel.photos.count,
                    matching: .images
                ) {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(MainView.navy)
                .disabled(viewModel.photos.count >= NewProjectViewModel.maxPhotoCount)
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 24)
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                NavigationLink("Next") {
                    ReviewStepView(viewModel: viewModel, onSaved: onSaved)
                }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       viewModel.photos.count < NewProjectViewModel.maxPhotoCount {
                        viewModel.photos.append(image)
                    }
                }
                pickerItems = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                if viewModel.photos.count < NewProjectViewModel.maxPhotoCount {
                    viewModel.photos.append(image)
                }
            }
            .ignoresSafeArea()
        }
    }

    private var photoGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            ForEach(Array(viewModel.photos.enumerated()), id: \.offset) { index, image in
                Color.clear
                    .frame(height: 110)
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            viewModel.photos.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, MainView.salmon)
                        }
                        .padding(6)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if index == 0 {
                            Text("Main")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(MainView.navy)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .padding(6)
                        }
                    }
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Step 3: review

private struct ReviewStepView: View {

    @ObservedObject var viewModel: NewProjectViewModel
    let onSaved: () -> Void

    @State private var showNoPhotoAlert = false

    var body: some View {
        Form {
            if let mainPhoto = viewModel.photos.first {
                Section {
                    Image(uiImage: mainPhoto)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section("Full name") {
                TextField("Full name", text: $viewModel.contactName)
            }
            Section("Additional notes") {
                TextField("Notes", text: $viewModel.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    // Unity: Done without a photo shows the info panel first.
                    if viewModel.photos.isEmpty {
                        showNoPhotoAlert = true
                    } else {
                        onSaved()
                    }
                }
            }
        }
        .alert("No photo added", isPresented: $showNoPhotoAlert) {
            Button("Continue anyway") { onSaved() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can go back to add photos of the pool, or continue without one.")
        }
    }
}

