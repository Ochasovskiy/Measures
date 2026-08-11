//
//  MeshDecimator.swift
//  MeasureGo
//
//  Reduces the LiDAR mesh before it is written to disk — the Swift stand-in
//  for Unity's UnityMeshSimplifier pass (quality 0.5).
//
//  Method: vertex clustering. Vertices are snapped to a uniform grid, all
//  vertices in a cell collapse into their average, and triangles that end up
//  with repeated corners are dropped. This suits ARKit meshes (already blocky
//  and noisy) and is fast and predictable on hundreds of thousands of
//  triangles, unlike an edge-collapse simplifier.
//
//  Accuracy note: this only affects the stored/previewed mesh. Measured point
//  positions come from ARKit raycasts at placement time and are stored
//  separately, so decimation cannot change any measurement.
//

import simd

enum MeshDecimator {

    struct Mesh {
        var vertices: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        var triangles: [UInt32]
    }

    /// Triangles we are happy to keep before coarsening kicks in. Pools vary
    /// enormously in size (a plunge pool to a large commercial pool), so this
    /// is a soft cap, not a hard one.
    ///
    /// Raised from 40k once the duplicate index list was dropped from the .dat
    /// format: that freed ~30% of every file, and the budget spends it on
    /// resolution instead, so files stay about the same size but keep more
    /// geometry.
    static let defaultTriangleBudget = 60_000

    /// Starting grid size. ARKit's scene mesh is ~4–5 cm dense, so 3 cm keeps
    /// essentially all detail; the search only coarsens when it must.
    static let minimumCellSize: Float = 0.03

    /// Quality floor. A large pool is allowed to exceed the triangle budget
    /// rather than be reduced past this resolution — detail per metre stays
    /// consistent whatever the pool's size, and only the file grows.
    static let maximumCellSize: Float = 0.08

    /// Decimates only as much as necessary: a small scan keeps full detail,
    /// a large one is reduced until it fits the triangle budget. Each pass is
    /// a couple of milliseconds, so the search is cheap.
    static func decimateToBudget(
        _ mesh: Mesh,
        triangleBudget: Int = defaultTriangleBudget
    ) -> Mesh {
        guard mesh.triangles.count / 3 > triangleBudget else { return mesh }

        // Finest allowed grid: if that already fits, keep every triangle it has.
        let finest = decimate(mesh, cellSize: minimumCellSize)
        if finest.triangles.count / 3 <= triangleBudget { return finest }

        // Otherwise binary-search for the *finest* cell size that fits the
        // budget. Growing the cell in fixed steps used to overshoot badly —
        // one step could halve the triangle count, throwing away detail that
        // would have fitted comfortably.
        var tooFine = minimumCellSize        // known to exceed the budget
        var fitting = maximumCellSize        // coarsest we will ever allow
        var best: Mesh?

        for _ in 0..<6 {
            let mid = (tooFine + fitting) / 2
            let candidate = decimate(mesh, cellSize: mid)
            if candidate.triangles.count / 3 <= triangleBudget {
                best = candidate
                fitting = mid
            } else {
                tooFine = mid
            }
        }

        // If nothing fits even at the quality floor, take the floor: a big pool
        // gets a bigger file rather than an unusable mesh.
        return best ?? decimate(mesh, cellSize: maximumCellSize)
    }

    static func decimate(_ mesh: Mesh, cellSize: Float) -> Mesh {
        guard cellSize > 0, !mesh.vertices.isEmpty, mesh.triangles.count >= 3 else { return mesh }

        let hasNormals = mesh.normals.count == mesh.vertices.count

        // Cell key -> index of the merged vertex.
        var cellToNewIndex: [SIMD3<Int32>: UInt32] = [:]
        cellToNewIndex.reserveCapacity(mesh.vertices.count / 2)

        var remap = [UInt32](repeating: 0, count: mesh.vertices.count)
        var positionSums: [SIMD3<Float>] = []
        var normalSums: [SIMD3<Float>] = []
        var counts: [Float] = []

        for (index, vertex) in mesh.vertices.enumerated() {
            let cell = SIMD3<Int32>(
                Int32(floor(vertex.x / cellSize)),
                Int32(floor(vertex.y / cellSize)),
                Int32(floor(vertex.z / cellSize))
            )
            if let existing = cellToNewIndex[cell] {
                remap[index] = existing
                positionSums[Int(existing)] += vertex
                if hasNormals { normalSums[Int(existing)] += mesh.normals[index] }
                counts[Int(existing)] += 1
            } else {
                let newIndex = UInt32(positionSums.count)
                cellToNewIndex[cell] = newIndex
                remap[index] = newIndex
                positionSums.append(vertex)
                normalSums.append(hasNormals ? mesh.normals[index] : SIMD3<Float>(0, 1, 0))
                counts.append(1)
            }
        }

        // Average each cluster.
        var newVertices = [SIMD3<Float>]()
        var newNormals = [SIMD3<Float>]()
        newVertices.reserveCapacity(positionSums.count)
        newNormals.reserveCapacity(positionSums.count)
        for i in 0..<positionSums.count {
            newVertices.append(positionSums[i] / counts[i])
            let n = normalSums[i] / counts[i]
            let length = simd_length(n)
            newNormals.append(length > 1e-6 ? n / length : SIMD3<Float>(0, 1, 0))
        }

        // Remap triangles, dropping ones that collapsed to a line or point.
        var newTriangles = [UInt32]()
        newTriangles.reserveCapacity(mesh.triangles.count)
        for t in stride(from: 0, to: mesh.triangles.count - 2, by: 3) {
            let a = remap[Int(mesh.triangles[t])]
            let b = remap[Int(mesh.triangles[t + 1])]
            let c = remap[Int(mesh.triangles[t + 2])]
            if a == b || b == c || a == c { continue }
            newTriangles.append(a)
            newTriangles.append(b)
            newTriangles.append(c)
        }

        guard !newTriangles.isEmpty else { return mesh } // never return an empty mesh
        return Mesh(vertices: newVertices, normals: newNormals, triangles: newTriangles)
    }
}
