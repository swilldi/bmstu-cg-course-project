//
//  AuroraVolume.swift
//  NortherLights
//
//  Аврора-нода: ограничивающий параллелепипед области сетки с материалом,
//  которому назначен SCNProgram (AuroraVolume.metal). SceneKit не считает здесь
//  освещение — только передаёт матрицы камеры и выполняет draw call.
//

import Metal
import SceneKit

nonisolated final class AuroraVolume {
    let node: SCNNode
    private let material: SCNMaterial
    /// Читается в обработчике привязки буфера на потоке рендера; там же и пишется.
    private var uniforms = AuroraVolumeUniforms()
    private weak var boundGrid: AuroraGrid?

    init() {
        let lo = Axes.scene(AuroraGrid.domainMin), hi = Axes.scene(AuroraGrid.domainMax)
        let extent = simd_abs(hi - lo)
        let box = SCNBox(width: CGFloat(extent.x), height: CGFloat(extent.y), length: CGFloat(extent.z), chamferRadius: 0)

        let program = SCNProgram()
        program.vertexFunctionName = "auroraVolumeVertex"
        program.fragmentFunctionName = "auroraVolumeFragment"
        program.isOpaque = false

        let material = SCNMaterial()
        material.program = program
        // Рисуются задние грани: так луч строится и когда наблюдатель внутри области сетки.
        material.cullMode = .front
        material.blendMode = .alpha
        // Тест глубины обрывает луч на непрозрачной поверхности; занавесы ниже 10 у.е.
        // не опускаются, поэтому задняя грань, закрытая рельефом, — луч, упёршийся в рельеф.
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = false
        box.materials = [material]

        let node = SCNNode(geometry: box)
        node.name = "aurora"
        node.simdPosition = (lo + hi) / 2
        node.castsShadow = false
        // После непрозрачной геометрии, чтобы буфер глубины был заполнен.
        node.renderingOrder = 100

        self.node = node
        self.material = material

        program.handleBinding(ofBufferNamed: "aurora", frequency: .perFrame) { [weak self] stream, _, _, _ in
            guard var uniforms = self?.uniforms else { return }
            stream.writeBytes(&uniforms, count: MemoryLayout<AuroraVolumeUniforms>.stride)
        }
    }

    func update(grid: AuroraGrid, medium: MediumParameters, step: Float) {
        if boundGrid !== grid {
            material.setValue(SCNMaterialProperty(contents: grid.texture), forKey: "grid")
            boundGrid = grid
        }
        uniforms = AuroraVolumeUniforms(
            domainMin: SIMD4(AuroraGrid.domainMin, 0),
            domainMax: SIMD4(AuroraGrid.domainMax, 0),
            gridSize: SIMD4(Float(grid.size.nx), Float(grid.size.ny), Float(grid.size.nz), 0),
            emission: medium.emission,
            absorption: medium.absorption,
            step: step,
            padding: 0
        )
    }
}

/// Раскладка совпадает с AuroraVolumeUniforms в AuroraVolume.metal.
nonisolated struct AuroraVolumeUniforms {
    var domainMin = SIMD4<Float>.zero
    var domainMax = SIMD4<Float>.zero
    var gridSize = SIMD4<Float>.zero
    var emission: Float = 0
    var absorption: Float = 0
    var step: Float = 1
    var padding: Float = 0
}
