//
//  ProjectListViewModel.swift
//  MeasureGo
//
//  List/sort/delete logic from Unity's FsmMain.
//

import Foundation
import Combine

@MainActor
final class ProjectListViewModel: ObservableObject {

    enum OrderBy: Int {
        case descending = 0
        case ascending = 1
    }

    @Published private(set) var projects: [ProjectFile] = []
    @Published private(set) var orderBy: OrderBy

    // Same preference key as Unity's PlayerPrefs.GetInt("OrderBy").
    private static let orderByKey = "OrderBy"

    init() {
        orderBy = OrderBy(rawValue: UserDefaults.standard.integer(forKey: Self.orderByKey)) ?? .descending
        // One-time cleanup of duplicate .msr files written by earlier builds.
        ProjectStore.removeDuplicateProjectFiles()
        reload()
    }

    var activeProjects: [ProjectFile] { projects.filter { !$0.data.status } }
    var uploadedProjects: [ProjectFile] { projects.filter { $0.data.status } }

    func reload() {
        let sorted = ProjectStore.loadAllProjects().sorted {
            orderBy == .descending
                ? $0.creationDate > $1.creationDate
                : $0.creationDate < $1.creationDate
        }
        projects = sorted
    }

    func toggleSortOrder() {
        orderBy = orderBy == .descending ? .ascending : .descending
        UserDefaults.standard.set(orderBy.rawValue, forKey: Self.orderByKey)
        reload()
    }

    func delete(_ project: ProjectData) {
        ProjectStore.delete(project)
        reload()
    }
}
