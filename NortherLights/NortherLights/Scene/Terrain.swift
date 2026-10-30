//
//  Terrain.swift
//  NortherLights
//
//  Ландшафт: карта высот -> SCNGeometry. Декорация, геометрию строит SceneKit;
//  шейдинг — общая модель освещения SurfaceShading.
//

import SceneKit

nonisolated enum Terrain {
    static func makeNode(heightmap: Heightmap, description: SceneDescription.Terrain) -> (SCNNode, SCNMaterial) {
        let w = heightmap.width, h = heightmap.height
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        positions.reserveCapacity(w * h)
        normals.reserveCapacity(w * h)
        let cell = Heightmap.extent / Float(w - 1)
        for j in 0..<h {
            for i in 0..<w {
                positions.append(Axes.scene(heightmap.position(i, j)))
                // Нормаль по центральным разностям: (-dH/dx, -dH/dy, 1) в РПЗ.
                // Строка j растёт к югу, поэтому dH/dy берётся с обратным знаком.
                let dx = (heightmap.value(i + 1, j) - heightmap.value(i - 1, j)) / (2 * cell)
                let dy = (heightmap.value(i, j - 1) - heightmap.value(i, j + 1)) / (2 * cell)
                normals.append(Axes.scene(simd_normalize(SIMD3(-dx, -dy, 1))))
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity((w - 1) * (h - 1) * 6)
        for j in 0..<(h - 1) {
            for i in 0..<(w - 1) {
                let a = UInt32(j * w + i), b = a + 1, c = a + UInt32(w), d = c + 1
                // Обход против часовой стрелки при взгляде сверху.
                indices += [a, c, b, b, c, d]
            }
        }
        let geometry = SCNGeometry(
            sources: [vectorSource(positions, semantic: .vertex), vectorSource(normals, semantic: .normal)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let material = SCNMaterial()
        SurfaceShading.configure(material, color: description.color, reflectance: description.reflectance.clamped())
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = "terrain"
        return (node, material)
    }

    private static func vectorSource(_ vectors: [SIMD3<Float>], semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
        // SIMD3<Float> занимает 16 байт, в буфер вершин пишутся только три компоненты.
        let packed = vectors.flatMap { [$0.x, $0.y, $0.z] }
        let data = packed.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: semantic, vectorCount: vectors.count,
                                 usesFloatComponents: true, componentsPerVector: 3,
                                 bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                 dataStride: 3 * MemoryLayout<Float>.size)
    }
}
