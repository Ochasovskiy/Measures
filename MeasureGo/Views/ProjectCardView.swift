//
//  ProjectCardView.swift
//  MeasureGo
//
//  One row of the project list — Unity's ProjectItemView: photo thumbnail
//  (or placeholder), name, creation date, delete button.
//

import SwiftUI

struct ProjectCardView: View {

    let project: ProjectData
    let creationDate: Date
    let onTap: () -> Void
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MM yyyy" // same format as the Unity app
        return f
    }()

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                thumbnail

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name.isEmpty ? "Untitled" : project.name)
                        .font(.headline)
                        .foregroundStyle(MainView.navy)
                        .lineLimit(1)
                    Text(Self.dateFormatter.string(from: creationDate))
                        .font(.subheadline)
                        .foregroundStyle(MainView.textSecondary)
                }

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(MainView.salmon)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = ProjectStore.loadImage(fileName: project.photoFileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(MainView.background)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(MainView.textSecondary)
                }
        }
    }
}
