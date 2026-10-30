//
//  SceneObjects.swift
//  NortherLights
//
//  Объекты сцены из стандартных тел SceneKit с полигональной аппроксимацией
//  (число сегментов — параметр тесселяции примитива). Состав и расстановка —
//  данные из файла описания сцены, здесь только «чертежи» типов объектов.
//

import SceneKit

nonisolated enum SceneObjects {
    static let defaultSegments = 16

    /// Узел объекта и материалы всех его тел (у объекта одни коэффициенты отражения).
    static func makeNode(_ object: SceneDescription.Object, heightmap: Heightmap) -> (SCNNode, [SCNMaterial]) {
        let segments = max(object.segments ?? defaultSegments, 3)
        let primary = object.colors.first ?? SIMD3(0.6, 0.6, 0.6)
        let secondary = object.colors.dropFirst().first ?? primary
        let reflectance = object.reflectance.clamped()
        var materials: [SCNMaterial] = []

        func part(_ geometry: SCNGeometry, color: SIMD3<Float>, at position: SIMD3<Float>,
                  euler: SIMD3<Float> = .zero) -> SCNNode {
            let material = SCNMaterial()
            SurfaceShading.configure(material, color: color, reflectance: reflectance)
            geometry.materials = [material]
            materials.append(material)
            let node = SCNNode(geometry: geometry)
            node.simdPosition = position
            node.simdEulerAngles = euler
            return node
        }

        let root = SCNNode()
        root.name = object.name
        switch object.kind {
        case .house:
            // Стены — параллелепипед, крыша — четырёхугольная пирамида.
            root.addChildNode(part(SCNBox(width: 4, height: 2.6, length: 3, chamferRadius: 0),
                                   color: primary, at: SIMD3(0, 1.3, 0)))
            root.addChildNode(part(SCNPyramid(width: 4.6, height: 1.8, length: 3.6),
                                   color: secondary, at: SIMD3(0, 2.6, 0)))
        case .tree:
            // Ствол — цилиндр, крона — два конуса.
            let trunk = SCNCylinder(radius: 0.25, height: 1.2)
            trunk.radialSegmentCount = segments
            root.addChildNode(part(trunk, color: primary, at: SIMD3(0, 0.6, 0)))
            let lower = SCNCone(topRadius: 0, bottomRadius: 1.6, height: 2.6)
            lower.radialSegmentCount = segments
            root.addChildNode(part(lower, color: secondary, at: SIMD3(0, 2.3, 0)))
            let upper = SCNCone(topRadius: 0, bottomRadius: 1.1, height: 2.0)
            upper.radialSegmentCount = segments
            root.addChildNode(part(upper, color: secondary, at: SIMD3(0, 3.6, 0)))
        case .car:
            // Кузов и кабина — параллелепипеды, колёса — цилиндры.
            root.addChildNode(part(SCNBox(width: 3.6, height: 0.8, length: 1.6, chamferRadius: 0),
                                   color: primary, at: SIMD3(0, 0.75, 0)))
            root.addChildNode(part(SCNBox(width: 2.0, height: 0.7, length: 1.4, chamferRadius: 0),
                                   color: primary, at: SIMD3(-0.3, 1.5, 0)))
            for (x, z) in [(-1.2, -0.85), (-1.2, 0.85), (1.2, -0.85), (1.2, 0.85)] as [(Float, Float)] {
                let wheel = SCNCylinder(radius: 0.38, height: 0.3)
                wheel.radialSegmentCount = segments
                root.addChildNode(part(wheel, color: secondary, at: SIMD3(x, 0.38, z),
                                       euler: SIMD3(.pi / 2, 0, 0)))
            }
        }

        // Основание — на минимальной высоте рельефа под объектом, чтобы не висело в воздухе.
        let footprint: Float = 2 * object.scale
        let corners: [SIMD2<Float>] = [SIMD2(-1, -1), SIMD2(-1, 1), SIMD2(1, -1), SIMD2(1, 1), .zero]
        let ground = corners.map { corner -> Float in
            let p = SIMD2(object.x, object.y) + corner * footprint
            return heightmap.height(x: p.x, y: p.y)
        }.min() ?? 0
        root.simdPosition = Axes.scene(SIMD3(object.x, object.y, ground))
        root.simdEulerAngles = SIMD3(0, object.rotation.radians, 0)
        root.simdScale = SIMD3(repeating: object.scale)
        return (root, materials)
    }
}
