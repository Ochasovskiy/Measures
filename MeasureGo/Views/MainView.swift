//
//  MainView.swift
//  MeasureGo
//
//  Native remake of Unity's GuiWindowMainView / FsmMain: project list with
//  Active/Uploaded tabs, sort toggle, delete with confirmation, New project.
//

import SwiftUI

struct MainView: View {

    private enum Tab: String, CaseIterable {
        case active = "Active"
        case uploaded = "Uploaded"
    }

    @StateObject private var viewModel = ProjectListViewModel()
    @State private var tab: Tab = .active
    @State private var projectToDelete: ProjectData?
    @State private var selectedProject: ProjectData?
    @State private var showNewProjectFlow = false

    static let navy = Color(red: 0.043, green: 0.145, blue: 0.29)
    static let salmon = Color(red: 0.976, green: 0.435, blue: 0.38)
    static let background = Color(red: 0.882, green: 0.898, blue: 0.925)
    /// Secondary text on white/light cards — slate blue in the navy palette,
    /// with much better contrast than the system .secondary gray.
    static let textSecondary = Color(red: 0.28, green: 0.36, blue: 0.47)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                VStack(spacing: 16) {
                    Picker("Tab", selection: $tab) {
                        Text("Active (\(viewModel.activeProjects.count))").tag(Tab.active)
                        Text("Uploaded (\(viewModel.uploadedProjects.count))").tag(Tab.uploaded)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text(tab == .active ? "Active Projects" : "Uploaded Projects")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Self.navy)
                        Spacer()
                        Button {
                            viewModel.toggleSortOrder()
                        } label: {
                            Text("Sort")
                                .font(.headline)
                                .foregroundStyle(Self.salmon)
                        }
                    }

                    projectList
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .background(Self.background)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationDestination(item: $selectedProject) { project in
                ProjectDetailsView(project: project)
            }
            .fullScreenCover(isPresented: $showNewProjectFlow) {
                NewProjectFlowView { project in
                    viewModel.reload()
                    // Unity moves straight to the details screen after saving.
                    selectedProject = project
                }
            }
        }
        .onAppear { viewModel.reload() }
        .onChange(of: selectedProject) { _, newValue in
            // Returning from the details screen: the project may have been
            // edited or uploaded there — refresh so it lands in the right tab.
            if newValue == nil {
                viewModel.reload()
            }
        }
        .confirmationDialog(
            "Do you really want to delete the project \(projectToDelete?.name ?? "")?",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    viewModel.delete(project)
                }
                projectToDelete = nil
            }
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Projects")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                showNewProjectFlow = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("New project")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(Self.navy)
    }

    @ViewBuilder
    private var projectList: some View {
        let items = tab == .active ? viewModel.activeProjects : viewModel.uploadedProjects
        if items.isEmpty {
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(items, id: \.data.id) { file in
                        ProjectCardView(
                            project: file.data,
                            creationDate: file.creationDate,
                            onTap: { selectedProject = file.data },
                            onDelete: { projectToDelete = file.data }
                        )
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
    }
}

#Preview {
    MainView()
}
