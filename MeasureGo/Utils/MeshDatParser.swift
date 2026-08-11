//
//  MeshDatParser.swift
//  MeasureGo
//
//  Parses the SaveMesh .dat text format.
//
//  Unity wrote:  vertices 'm|' normals 'm|' triangles 'm|' indices 'm|' topology 'm|' color
//  We now write: vertices 'm|' normals 'm|' triangles 'm|' topology 'm|' color
//  (the index list duplicated the triangle list; see ARScanController).
//  Only the first three sections are read, so both layouts load — scans made
//  by the Unity app or by earlier builds still open.
//

import Foundation
import simd

struct ParsedMesh {
    var vertices: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var triangles: [Int32] = []
}

enum MeshDatParser {

    static func parse(_ text: String) -> ParsedMesh? {
        // Multi-mesh models are joined with "mo|"; scan meshes have one.
        let firstModel = text.components(separatedBy: "mo|").first ?? text
        let sections = firstModel.components(separatedBy: "m|")
        guard sections.count >= 3 else { return nil }

        var mesh = ParsedMesh()
        mesh.vertices = parseVectors(sections[0], separator: "v|")
        mesh.normals = parseVectors(sections[1], separator: "n|")
        mesh.triangles = sections[2].split(separator: " ").compactMap { Int32($0) }

        guard !mesh.vertices.isEmpty, mesh.triangles.count >= 3 else { return nil }
        // Drop any triangle index that is out of range (defensive against
        // truncated files).
        let count = Int32(mesh.vertices.count)
        guard mesh.triangles.allSatisfy({ $0 >= 0 && $0 < count }) else { return nil }
        return mesh
    }

    private static func parseVectors(_ section: String, separator: String) -> [SIMD3<Float>] {
        section.components(separatedBy: separator).compactMap { triple in
            let parts = triple.split(separator: " ").compactMap { Float($0) }
            guard parts.count >= 3 else { return nil }
            return SIMD3(parts[0], parts[1], parts[2])
        }
    }
}
