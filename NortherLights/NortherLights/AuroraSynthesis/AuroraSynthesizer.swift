//
//  AuroraSynthesizer.swift
//  NortherLights
//
//  Внешний интерфейс модуля синтеза: по параметрам занавесов заполняет расчётную
//  сетку `AuroraGrid` (compute-шейдер Metal) и строит точечные источники подсветки.
//  Метод синтеза основания — подставляемая стратегия `AuroraCurtainSynthesizing`.
//

import Metal
import simd

/// Расчётная сетка — 3D-текстура RGBA16F над областью
/// $[0;100]\times[0;100]\times[10;60]$ у.е. (координаты РПЗ).
/// В узле хранится $(\sum_k \rho_k C_k,\ \sum_k \rho_k)$: при перекрытии занавесов
/// излучение и поглощение складываются, а цвет у каждого занавеса свой.
/// Это единственный интерфейс между синтезом и объёмным рендером.
nonisolated final class AuroraGrid {
    static let domainMin = SIMD3<Float>(0, 0, 10)
    static let domainMax = SIMD3<Float>(100, 100, 60)

    let size: GridSize
    let texture: MTLTexture

    init?(device: MTLDevice, size: GridSize) {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = size.nx
        descriptor.height = size.ny
        descriptor.depth = size.nz
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "AuroraGrid \(size)"
        self.size = size
        self.texture = texture
    }

    /// Расстояние между соседними узлами по каждой оси, у.е.
    var spacing: SIMD3<Float> {
        (Self.domainMax - Self.domainMin) / SIMD3(Float(size.nx - 1), Float(size.ny - 1), Float(size.nz - 1))
    }
}

/// Точечный источник, заменяющий свечение участка занавеса: $I_j$ без множителя
/// $\varepsilon$ (он применяется в шейдере освещения), центр яркости $y_j$ и средний цвет $C_j$.
nonisolated struct AuroraLightSource: Sendable {
    /// Центр яркости участка, координаты РПЗ.
    var position: SIMD3<Float>
    /// $\int_{V_j} \rho\, dV$.
    var intensity: Float
    var color: SIMD3<Float>
}

nonisolated final class AuroraSynthesizer {
    /// Точек основания на занавес (не больше 256 по аналитическому разделу).
    static let sampleCount = 256
    /// Сколько кадров могут одновременно читать буферы на GPU.
    private static let framesInFlight = 3

    private let method: any AuroraCurtainSynthesizing
    private let pipeline: MTLComputePipelineState
    private let curtainBuffers: [MTLBuffer]
    private let sampleBuffers: [MTLBuffer]
    private var frameIndex = 0

    init?(device: MTLDevice, method: any AuroraCurtainSynthesizing = PerlinCurtainSynthesizer()) {
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "fillAuroraGrid"),
              let pipeline = try? device.makeComputePipelineState(function: function) else { return nil }
        let curtainLength = MemoryLayout<CurtainGPU>.stride * AuroraLimits.maxCurtains
        let sampleLength = MemoryLayout<SIMD4<Float>>.stride * AuroraLimits.maxCurtains * Self.sampleCount
        var curtainBuffers: [MTLBuffer] = []
        var sampleBuffers: [MTLBuffer] = []
        for _ in 0..<Self.framesInFlight {
            guard let curtains = device.makeBuffer(length: curtainLength, options: .storageModeShared),
                  let samples = device.makeBuffer(length: sampleLength, options: .storageModeShared) else { return nil }
            curtainBuffers.append(curtains)
            sampleBuffers.append(samples)
        }
        self.method = method
        self.pipeline = pipeline
        self.curtainBuffers = curtainBuffers
        self.sampleBuffers = sampleBuffers
    }

    /// Синтезирует сияние в момент `time`: кодирует заполнение сетки в `commandBuffer`
    /// и возвращает точечные источники подсветки (по четыре на занавес).
    func synthesize(curtains: [CurtainParameters], seed: UInt32, time: Double,
                    into grid: AuroraGrid, commandBuffer: MTLCommandBuffer) -> [AuroraLightSource] {
        frameIndex = (frameIndex + 1) % Self.framesInFlight
        let curtainBuffer = curtainBuffers[frameIndex]
        let sampleBuffer = sampleBuffers[frameIndex]
        let gpuCurtains = curtainBuffer.contents().bindMemory(to: CurtainGPU.self, capacity: AuroraLimits.maxCurtains)
        let gpuSamples = sampleBuffer.contents().bindMemory(to: SIMD4<Float>.self,
                                                            capacity: AuroraLimits.maxCurtains * Self.sampleCount)
        // Толщина слоя не меньше шага сетки, иначе занавес «проваливается» между узлами.
        let thickness = max(0.7, max(grid.spacing.x, grid.spacing.y))

        var lights: [AuroraLightSource] = []
        lights.reserveCapacity(AuroraLimits.maxLights)
        let active = curtains.prefix(AuroraLimits.maxCurtains)
        for (k, curtain) in active.enumerated() {
            let curtainSeed = Self.curtainSeed(seed, k)
            let placement = Self.placement(of: curtain, seed: curtainSeed)
            let base = method.base(of: curtain, seed: curtainSeed, time: time, sampleCount: Self.sampleCount)
            let slope = Self.derivative(base.deviation, step: curtain.length / Float(Self.sampleCount - 1))
            let offset = k * Self.sampleCount
            for i in 0..<Self.sampleCount {
                gpuSamples[offset + i] = SIMD4(base.deviation[i], slope[i], base.brightness[i], 0)
            }
            gpuCurtains[k] = CurtainGPU(
                placement: SIMD4(placement.origin, placement.direction),
                shape: SIMD4(curtain.length, curtain.hMin, curtain.hMax, thickness),
                colorLow: SIMD4(curtain.colorLow, 0),
                colorMid: SIMD4(curtain.colorMid, 0),
                colorHigh: SIMD4(curtain.colorHigh, 0),
                sampling: SIMD4(UInt32(Self.sampleCount), UInt32(offset), 0, 0)
            )
            lights += Self.lightSources(curtain: curtain, placement: placement, base: base, slope: slope,
                                        thickness: thickness)
        }

        var uniforms = GridUniforms(
            domainMin: SIMD4(AuroraGrid.domainMin, 0),
            domainMax: SIMD4(AuroraGrid.domainMax, 0),
            size: SIMD4(UInt32(grid.size.nx), UInt32(grid.size.ny), UInt32(grid.size.nz), UInt32(active.count))
        )
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.label = "Aurora grid synthesis"
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(grid.texture, index: 0)
            encoder.setBytes(&uniforms, length: MemoryLayout<GridUniforms>.stride, index: 0)
            encoder.setBuffer(curtainBuffer, offset: 0, index: 1)
            encoder.setBuffer(sampleBuffer, offset: 0, index: 2)
            let threadgroup = MTLSize(width: 8, height: 8, depth: 4)
            encoder.dispatchThreads(MTLSize(width: grid.size.nx, height: grid.size.ny, depth: grid.size.nz),
                                    threadsPerThreadgroup: threadgroup)
            encoder.endEncoding()
        }
        return lights
    }

    // MARK: - Расстановка занавесов

    struct Placement {
        /// Начало основания $(x, y)$, РПЗ.
        var origin: SIMD2<Float>
        /// Единичный вектор основного направления.
        var direction: SIMD2<Float>

        func point(u: Float, w: Float) -> SIMD2<Float> {
            origin + u * direction + w * SIMD2(-direction.y, direction.x)
        }
    }

    private static func curtainSeed(_ seed: UInt32, _ k: Int) -> UInt32 {
        var generator = SplitMix64(seed: UInt64(seed) &* 0x1_0000_0001 &+ UInt64(k))
        return UInt32(truncatingIfNeeded: generator.next())
    }

    /// Положение и направление занавеса порождаются генератором по начальному значению:
    /// центр — в северной половине сцены, направление — близкое к «восток — запад».
    static func placement(of curtain: CurtainParameters, seed: UInt32) -> Placement {
        var generator = SplitMix64(seed: UInt64(seed) ^ 0xA5A5_5A5A)
        let center = SIMD2(generator.nextFloat(in: 30...70), generator.nextFloat(in: 45...90))
        let angle = generator.nextFloat(in: -35...35).radians
        let direction = SIMD2(cos(angle), sin(angle))
        return Placement(origin: center - direction * curtain.length / 2, direction: direction)
    }

    private static func derivative(_ values: [Float], step: Float) -> [Float] {
        let n = values.count
        return (0..<n).map { i in
            let a = values[max(i - 1, 0)], b = values[min(i + 1, n - 1)]
            return (b - a) / (Float(min(i + 1, n - 1) - max(i - 1, 0)) * step)
        }
    }

    // MARK: - Точечные источники подсветки

    /// Делит основание на `lightsPerCurtain` участков и для каждого считает
    /// $I_j = \int_{V_j} \rho\, dV$ и центр яркости $y_j$ (формула точечного источника РПЗ).
    /// Плотность раскладывается в произведение множителей вдоль основания, поперёк слоя
    /// и по высоте, поэтому объёмный интеграл сводится к произведению одномерных.
    private static func lightSources(curtain: CurtainParameters, placement: Placement, base: CurtainBase,
                                     slope: [Float], thickness: Float) -> [AuroraLightSource] {
        let vertical = VerticalProfile(curtain: curtain)
        // $\int e^{-(d/\sigma)^2} dd = \sigma\sqrt{\pi}$.
        let across = thickness * Float.pi.squareRoot()
        let du = curtain.length / Float(sampleCount - 1)
        let perSegment = sampleCount / AuroraLimits.lightsPerCurtain
        var lights: [AuroraLightSource] = []
        for segment in 0..<AuroraLimits.lightsPerCurtain {
            var weight: Float = 0
            var center = SIMD2<Float>.zero
            for i in (segment * perSegment)..<((segment + 1) * perSegment) {
                let u = Float(i) * du
                // Длина дуги основания: $ds = \sqrt{1 + w'^2}\, du$.
                let w = base.brightness[i] * endFade(u / curtain.length) * (1 + slope[i] * slope[i]).squareRoot() * du
                weight += w
                center += w * placement.point(u: u, w: base.deviation[i])
            }
            guard weight > 0 else { continue }
            lights.append(AuroraLightSource(
                position: SIMD3(center / weight, vertical.centroid),
                intensity: weight * across * vertical.integral,
                color: vertical.meanColor
            ))
        }
        return lights
    }

    /// Затухание у концов занавеса; та же формула в `AuroraGridFill.metal`.
    private static func endFade(_ s: Float) -> Float {
        smoothstep(0, 0.08, s) * smoothstep(0, 0.08, 1 - s)
    }

    /// Профиль плотности по высоте $f(s)$, $s = (z - h_{\min}) / (h_{\max} - h_{\min})$:
    /// резкая нижняя граница и плавное затухание вверх. Те же формулы — в `AuroraGridFill.metal`.
    struct VerticalProfile {
        /// $\int f\, dz$, у.е.
        var integral: Float = 0
        /// Высота центра яркости, у.е.
        var centroid: Float = 0
        /// Средний по профилю цвет $C_j$.
        var meanColor = SIMD3<Float>.zero

        init(curtain: CurtainParameters) {
            let n = 64
            let height = curtain.hMax - curtain.hMin
            var sum: Float = 0, moment: Float = 0
            var color = SIMD3<Float>.zero
            for i in 0..<n {
                let s = (Float(i) + 0.5) / Float(n)
                let f = Self.density(s)
                sum += f
                moment += s * f
                color += f * Self.color(s, curtain)
            }
            guard sum > 0 else { return }
            integral = sum / Float(n) * height
            centroid = curtain.hMin + moment / sum * height
            meanColor = color / sum
        }

        static func density(_ s: Float) -> Float {
            smoothstep(0, 0.06, s) * pow(1 - s, 1.5)
        }

        /// Цвет нижней, средней и верхней третей с плавными переходами.
        static func color(_ s: Float, _ c: CurtainParameters) -> SIMD3<Float> {
            let mid = simd_mix(c.colorLow, c.colorMid, SIMD3(repeating: smoothstep(1.0 / 3 - 0.06, 1.0 / 3 + 0.06, s)))
            return simd_mix(mid, c.colorHigh, SIMD3(repeating: smoothstep(2.0 / 3 - 0.06, 2.0 / 3 + 0.06, s)))
        }
    }
}

nonisolated private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = ((x - edge0) / (edge1 - edge0)).clamped(to: 0...1)
    return t * t * (3 - 2 * t)
}

// MARK: - Структуры, разделяемые с AuroraGridFill.metal (раскладка должна совпадать)

nonisolated struct CurtainGPU {
    /// origin.xy, direction.xy
    var placement: SIMD4<Float>
    /// length, hMin, hMax, thickness
    var shape: SIMD4<Float>
    var colorLow: SIMD4<Float>
    var colorMid: SIMD4<Float>
    var colorHigh: SIMD4<Float>
    /// sampleCount, sampleOffset
    var sampling: SIMD4<UInt32>
}

nonisolated struct GridUniforms {
    var domainMin: SIMD4<Float>
    var domainMax: SIMD4<Float>
    /// nx, ny, nz, curtainCount
    var size: SIMD4<UInt32>
}
