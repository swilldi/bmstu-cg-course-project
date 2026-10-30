//
//  SceneGraph.swift
//  NortherLights
//
//  Сборка сцены SceneKit: ландшафт, объекты, источник на бесконечности, камера и
//  аврора-нода. Здесь же — применение пользовательских параметров к узлам.
//

import SceneKit

nonisolated final class SceneGraph {
    /// Центр сцены, координаты РПЗ.
    static let center = SIMD3<Float>(50, 50, 5)

    let scene = SCNScene()
    let heightmap: Heightmap
    let cameraNode: SCNNode
    let sunNode: SCNNode
    let terrainNode: SCNNode
    let objectsNode = SCNNode()
    let auroraVolume = AuroraVolume()
    /// Материалы каждой поверхности: [0] — ландшафт, далее объекты в порядке файла описания.
    let surfaceMaterials: [[SCNMaterial]]

    init(description: SceneDescription, heightmap: Heightmap) {
        self.heightmap = heightmap
        scene.background.contents = NSColor(srgbRed: 0.01, green: 0.015, blue: 0.04, alpha: 1)

        let (terrain, terrainMaterial) = Terrain.makeNode(heightmap: heightmap, description: description.terrain)
        terrainNode = terrain
        scene.rootNode.addChildNode(terrain)

        var surfaceMaterials = [[terrainMaterial]]
        for object in description.objects {
            let (node, materials) = SceneObjects.makeNode(object, heightmap: heightmap)
            objectsNode.addChildNode(node)
            surfaceMaterials.append(materials)
        }
        self.surfaceMaterials = surfaceMaterials
        scene.rootNode.addChildNode(objectsNode)

        sunNode = Self.makeSunLight()
        scene.rootNode.addChildNode(sunNode)

        let camera = SCNCamera()
        camera.fieldOfView = 60  // постоянный угол обзора по вертикали
        camera.projectionDirection = .vertical
        camera.zNear = 0.1
        camera.zFar = 600
        cameraNode = SCNNode()
        cameraNode.name = "observer"
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        scene.rootNode.addChildNode(auroraVolume.node)
    }

    /// Единственный источник на бесконечности. Карту теней строит SceneKit,
    /// а применяет тень собственная модель освещения (SurfaceShading.lightingModifier).
    private static func makeSunLight() -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.castsShadow = true
        // Явно: только при прямом режиме тень попадает в `_light.intensity` до вызова
        // модификатора lightingModel; при `.deferred` она накладывается после него.
        light.shadowMode = .forward
        light.shadowMapSize = CGSize(width: 4096, height: 4096)
        light.shadowSampleCount = 8
        light.shadowRadius = 1.5
        light.shadowBias = 2
        light.shadowColor = NSColor.black
        light.orthographicScale = 75
        light.zNear = 1
        light.zFar = 400
        let node = SCNNode()
        node.name = "sun"
        node.light = light
        return node
    }

    // MARK: - Применение параметров

    func apply(light parameters: LightParameters) {
        guard let light = sunNode.light else { return }
        let toLight = Axes.scene(parameters.direction)
        // Направленный источник светит вдоль своей оси −Z.
        sunNode.simdOrientation = simd_quatf(from: SIMD3(0, 0, -1), to: -toLight)
        sunNode.simdPosition = Axes.scene(Self.center) + toLight * 150
        light.color = NSColor(srgbRed: CGFloat(parameters.color.x), green: CGFloat(parameters.color.y),
                              blue: CGFloat(parameters.color.z), alpha: 1)
        // 1000 лм в SceneKit соответствует множителю 1 в `_light.intensity`.
        light.intensity = CGFloat(parameters.intensity * 1000)
    }

    func apply(reflectances: [Reflectance]) {
        for (materials, reflectance) in zip(surfaceMaterials, reflectances) {
            for material in materials {
                SurfaceShading.apply(reflectance, to: material)
            }
        }
    }

    func apply(lights: SCNMaterialProperty, count: Int, emission: Float) {
        for materials in surfaceMaterials {
            for material in materials {
                SurfaceShading.apply(lights: lights, count: count, emission: emission, to: material)
            }
        }
    }

    // MARK: - Наблюдатель

    /// Ставит камеру в положение наблюдателя (координаты РПЗ, углы в градусах).
    func place(camera node: SCNNode, at observer: Observer) {
        var position = observer.position
        position.z = max(position.z, heightmap.height(x: position.x, y: position.y) + Self.minimumEyeHeight)
        node.simdPosition = Axes.scene(position)
        // Камера смотрит вдоль −Z (север РПЗ, φ = 90°): сначала угол места, затем азимут.
        let yaw = simd_quatf(angle: (observer.azimuth - 90).radians, axis: Axes.up)
        let pitch = simd_quatf(angle: observer.elevation.radians, axis: SIMD3(1, 0, 0))
        node.simdOrientation = yaw * pitch
    }

    func observer(of node: SCNNode) -> Observer {
        let position = Axes.rpz(node.simdWorldPosition)
        let direction = Axes.rpz(node.simdWorldOrientation.act(SIMD3(0, 0, -1)))
        var azimuth = atan2(direction.y, direction.x).degrees
        if azimuth < 0 { azimuth += 360 }
        let elevation = asin(direction.z.clamped(to: -1...1)).degrees
        return Observer(position: position, azimuth: azimuth, elevation: elevation)
    }

    /// Наблюдатель не опускается ниже поверхности: $z_V > H(x_V, y_V)$.
    static let minimumEyeHeight: Float = 0.5

    func keepAboveTerrain(_ node: SCNNode) {
        let position = Axes.rpz(node.simdWorldPosition)
        let floor = heightmap.height(x: position.x, y: position.y) + Self.minimumEyeHeight
        if position.z < floor {
            node.simdWorldPosition = Axes.scene(SIMD3(position.x, position.y, floor))
        }
    }
}
