//
//  ScanPreviewView.swift
//  MeasureGo
//
//  3D preview of a saved scan — native counterpart of Unity's Preview.cs:
//  the saved mesh, colored points, the closed perimeter loop, and an
//  orbitable camera starting above the scene center.
//

import SwiftUI
import SceneKit

struct ScanPreviewView: View {

    let scanData: ScanData
    @Environment(\.dismiss) private var dismiss
    @State private var showPointList = false

    var body: some View {
        ZStack {
            ScenePreviewContainer(scanData: scanData)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(MainView.navy.opacity(0.85))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text("Pool scan")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(MainView.navy.opacity(0.85))
                        .clipShape(Capsule())
                    Spacer()
                    Button {
                        showPointList = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(MainView.navy.opacity(0.85))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                Text("Drag to orbit • Pinch to zoom • Two fingers to pan")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(MainView.navy.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 24)
            }
        }
        .statusBarHidden()
        .sheet(isPresented: $showPointList) {
            pointListSheet
        }
    }

    private var pointListSheet: some View {
        NavigationStack {
            List(scanData.pointsData, id: \.uuid) { point in
                HStack {
                    Circle()
                        .fill(Color(point.pointType.uiColor))
                        .frame(width: 14, height: 14)
                    Text("\(point.pointType.displayName) \(point.index)")
                        .foregroundStyle(.primary)
                    Spacer()
                    if !point.notes.isEmpty {
                        Text(point.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .navigationTitle("Points (\(scanData.pointsData.count))")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - SceneKit container

private struct ScenePreviewContainer: UIViewRepresentable {

    let scanData: ScanData

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = Self.buildScene(from: scanData)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = UIColor(red: 0.04, green: 0.1, blue: 0.2, alpha: 1)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    /// Unity coordinates (left-handed) -> SceneKit (right-handed): negate z.
    private static func scnVector(_ v: ProjectData.Vector3) -> SCNVector3 {
        SCNVector3(v.x, v.y, -v.z)
    }

    private static func buildScene(from scanData: ScanData) -> SCNScene {
        let scene = SCNScene()
        var boundsPoints: [SIMD3<Float>] = []

        // --- Mesh from the .dat file ---
        if let meshString = ProjectStore.loadMeshString(fileName: scanData.meshString),
           let parsed = MeshDatParser.parse(meshString) {

            let vertices = parsed.vertices.map { SIMD3($0.x, $0.y, -$0.z) }
            boundsPoints.append(contentsOf: vertices)

            let vertexSource = SCNGeometrySource(
                vertices: vertices.map { SCNVector3($0.x, $0.y, $0.z) })
            var sources = [vertexSource]
            if parsed.normals.count == parsed.vertices.count {
                sources.append(SCNGeometrySource(
                    normals: parsed.normals.map { SCNVector3($0.x, $0.y, -$0.z) }))
            }

            // Winding flips with the z mirror: swap each triangle's 2nd/3rd.
            var indices: [Int32] = []
            indices.reserveCapacity(parsed.triangles.count)
            for t in stride(from: 0, to: parsed.triangles.count - 2, by: 3) {
                indices.append(parsed.triangles[t])
                indices.append(parsed.triangles[t + 2])
                indices.append(parsed.triangles[t + 1])
            }
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

            let geometry = SCNGeometry(sources: sources, elements: [element])
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(white: 0.75, alpha: 1)
            material.isDoubleSided = true
            geometry.materials = [material]
            scene.rootNode.addChildNode(SCNNode(geometry: geometry))
        }

        // --- Points ---
        for point in scanData.pointsData {
            let sphere = SCNSphere(radius: 0.04)
            sphere.firstMaterial?.diffuse.contents = point.pointType.uiColor
            let node = SCNNode(geometry: sphere)
            node.position = scnVector(point.position)
            scene.rootNode.addChildNode(node)
            boundsPoints.append(SIMD3(point.position.x, point.position.y, -point.position.z))
        }

        // --- Perimeter loop ---
        let perimeter = scanData.pointsData
            .filter { $0.pointType == .perimeter }
            .sorted { $0.index < $1.index }
        if perimeter.count >= 2 {
            for i in 0..<perimeter.count {
                let a = scnVector(perimeter[i].position)
                let b = scnVector(perimeter[(i + 1) % perimeter.count].position)
                if let line = lineNode(from: a, to: b) {
                    scene.rootNode.addChildNode(line)
                }
            }
        }

        // --- Camera above the scene center (Unity's GetCameraPosition) ---
        let center: SIMD3<Float>
        let radius: Float
        if boundsPoints.isEmpty {
            center = .zero
            radius = 5
        } else {
            let minP = boundsPoints.reduce(boundsPoints[0], simd_min)
            let maxP = boundsPoints.reduce(boundsPoints[0], simd_max)
            center = (minP + maxP) / 2
            radius = max(simd_distance(minP, maxP) / 2, 1)
        }

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 200
        let distance = max(radius * 2.2, 3)
        cameraNode.position = SCNVector3(center.x, center.y + distance, center.z + distance * 0.35)
        cameraNode.look(
            at: SCNVector3(center.x, center.y, center.z),
            up: SCNVector3(0, 1, 0),
            localFront: SCNVector3(0, 0, -1)
        )
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    private static func lineNode(from a: SCNVector3, to b: SCNVector3) -> SCNNode? {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let length = sqrtf(dx * dx + dy * dy + dz * dz)
        guard length > 0.001 else { return nil }

        let cylinder = SCNCylinder(radius: 0.012, height: CGFloat(length))
        cylinder.firstMaterial?.diffuse.contents = UIColor.black
        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        node.look(at: b, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        return node
    }
}
