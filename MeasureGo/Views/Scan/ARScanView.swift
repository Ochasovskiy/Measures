//
//  ARScanView.swift
//  MeasureGo
//
//  The AR scan screen: tutorial overlay -> perimeter points -> feature
//  points -> save. Native counterpart of Unity's GuiWindowScanView /
//  GuiWindowScanPerimiterView / GuiWindowScanFeatureView.
//

import ARKit
import SwiftUI
import RealityKit

struct ARScanView: View {

    @StateObject private var viewModel = ARScanViewModel()
    @Environment(\.dismiss) private var dismiss

    let project: ProjectData
    let onScanSaved: (ProjectData) -> Void

    @State private var showTypeSelector = false
    @State private var showCompleteConfirm = false
    @State private var showCongratulations = false

    var body: some View {
        ZStack {
            if ARScanController.isARSupported {
                ARViewContainer(controller: viewModel.controller)
                    .ignoresSafeArea()
            } else {
                unsupportedView
            }

            if ARScanController.isARSupported {
                overlay
            }
        }
        .statusBarHidden()
        .sheet(isPresented: $showTypeSelector) {
            typeSelectorSheet
        }
        .alert("Complete the scan?", isPresented: $showCompleteConfirm) {
            Button("Save scan") { saveScan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The mesh and all placed points will be saved to the project.")
        }
        .alert("Congratulations!", isPresented: $showCongratulations) {
            Button("OK") { dismiss() }
        } message: {
            Text("You've completed the measurement.")
        }
        .alert("No surface found", isPresented: $viewModel.placementFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Point the camera at the ground and move the phone slowly, then try again.")
        }
    }

    // MARK: - Phase overlays

    @ViewBuilder
    private var overlay: some View {
        switch viewModel.phase {
        case .tutorial:
            tutorialOverlay
        case .perimeter:
            placementOverlay(
                title: "Mark the pool perimeter",
                subtitle: "Aim the center reticle at the pool edge and place points around the perimeter.",
                nextTitle: "Continue",
                nextEnabled: viewModel.perimeterPoints.count >= 3,
                nextAction: { viewModel.finishPerimeter() }
            )
        case .features:
            placementOverlay(
                title: viewModel.selectedFeatureType == .none
                    ? "Select a point type"
                    : "Place: \(viewModel.selectedFeatureType.displayName)",
                subtitle: "Mark anchors and other features of the pool. Change the type any time.",
                nextTitle: "Complete",
                nextEnabled: true,
                nextAction: { showCompleteConfirm = true }
            )
        }
    }

    private var tutorialOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Text("Scan the pool area")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MainView.navy)
                Text("Slowly walk around the pool while pointing the camera at the ground and walls. The detected surface appears as a mesh. When the whole pool is covered, tap Start to place points.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if ARScanController.isMeshingSupported {
                    Text("Scanned surfaces: \(viewModel.controller.meshChunkCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("This device has no LiDAR — points can still be placed on detected planes, but no mesh will be saved.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                Button {
                    viewModel.phase = .perimeter
                } label: {
                    Text("Start")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(MainView.navy)

                Button("Back to project") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(16)
        }
    }

    private func placementOverlay(
        title: String,
        subtitle: String,
        nextTitle: String,
        nextEnabled: Bool,
        nextAction: @escaping () -> Void
    ) -> some View {
        VStack {
            // Top bar
            HStack {
                Button {
                    if viewModel.phase == .features {
                        viewModel.phase = .perimeter
                        viewModel.controller.rebuildLines(
                            through: viewModel.perimeterPoints.map(\.position), closeLoop: false)
                    } else {
                        viewModel.phase = .tutorial
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Points: \(viewModel.phase == .perimeter ? viewModel.perimeterPoints.count : viewModel.points.count - viewModel.perimeterPoints.count)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.4))
                .clipShape(Capsule())
                Spacer()
                Toggle(isOn: $viewModel.lockHeight) {
                    Image(systemName: viewModel.lockHeight ? "lock.fill" : "lock.open")
                }
                .toggleStyle(.button)
                .tint(.white)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.4))
                .clipShape(Circle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 4)
                .shadow(radius: 2)

            Spacer()

            // Center reticle
            reticle

            Spacer()

            // Bottom controls
            VStack(spacing: 12) {
                if viewModel.phase == .features {
                    Button {
                        showTypeSelector = true
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(viewModel.selectedFeatureType.uiColor))
                                .frame(width: 14, height: 14)
                            Text(viewModel.selectedFeatureType == .none
                                 ? "Select point type"
                                 : viewModel.selectedFeatureType.displayName)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                    }
                }

                HStack(spacing: 16) {
                    Button {
                        viewModel.undoLastPoint()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .disabled(!viewModel.canUndo)
                    .opacity(viewModel.canUndo ? 1 : 0.4)

                    Button {
                        viewModel.placePoint()
                    } label: {
                        Text("Place point")
                            .font(.headline)
                            .foregroundStyle(MainView.navy)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(viewModel.phase == .features && viewModel.selectedFeatureType == .none)
                    .opacity(viewModel.phase == .features && viewModel.selectedFeatureType == .none ? 0.5 : 1)

                    Button {
                        nextAction()
                    } label: {
                        Text(nextTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 90, height: 54)
                            .background(nextEnabled ? MainView.salmon : Color.gray.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    .disabled(!nextEnabled)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var reticle: some View {
        ZStack {
            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: 44, height: 44)
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
            Rectangle().fill(.white).frame(width: 16, height: 1)
                .offset(x: -28)
            Rectangle().fill(.white).frame(width: 16, height: 1)
                .offset(x: 28)
            Rectangle().fill(.white).frame(width: 1, height: 16)
                .offset(y: -28)
            Rectangle().fill(.white).frame(width: 1, height: 16)
                .offset(y: 28)
        }
        .shadow(radius: 2)
        .allowsHitTesting(false)
    }

    private var typeSelectorSheet: some View {
        NavigationStack {
            List(PointType.featureTypes, id: \.self) { type in
                Button {
                    viewModel.selectedFeatureType = type
                    showTypeSelector = false
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(type.uiColor))
                            .frame(width: 16, height: 16)
                        Text(type.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if viewModel.selectedFeatureType == type {
                            Image(systemName: "checkmark")
                                .foregroundStyle(MainView.navy)
                        }
                    }
                }
            }
            .navigationTitle("Point type")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var unsupportedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arkit")
                .font(.system(size: 48))
                .foregroundStyle(MainView.navy)
            Text("AR is not available on this device")
                .font(.headline)
                .foregroundStyle(MainView.navy)
            Text("Pool scanning requires an iPhone or iPad with ARKit support (the simulator can't run AR).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Back to project") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(MainView.navy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MainView.background)
    }

    private func saveScan() {
        let updated = viewModel.saveScan(into: project)
        onScanSaved(updated)
        showCongratulations = true
    }
}

// MARK: - ARView wrapper

private struct ARViewContainer: UIViewRepresentable {

    let controller: ARScanController

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        controller.attach(to: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: ()) {
        uiView.session.pause()
    }
}
