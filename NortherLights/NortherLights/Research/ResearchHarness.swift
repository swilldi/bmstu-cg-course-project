//
//  ResearchHarness.swift
//  NortherLights
//
//  Исследование зависимости времени синтеза кадра от шага интегрирования и от размера
//  расчётной сетки. Фиксированная сцена рендерится вне экрана (SCNRenderer), без
//  синхронизации с частотой дисплея; кадр = синтез сетки + рендер сцены и сияния.
//

import Foundation
import Metal
import QuartzCore
import SceneKit

nonisolated struct ResearchConfiguration: Hashable, Sendable {
    var step: Float
    var grid: GridSize
}

nonisolated struct ResearchMeasurement: Identifiable, Sendable {
    let id = UUID()
    var configuration: ResearchConfiguration
    /// Время кадра от начала синтеза до завершения рендера на GPU, мс.
    var meanMilliseconds: Double
    var minMilliseconds: Double
    var maxMilliseconds: Double
    /// Время выполнения команд кадра на GPU, мс.
    var gpuMilliseconds: Double

    var nodeCount: Int { configuration.grid.nx * configuration.grid.ny * configuration.grid.nz }

    static let csvHeader = "step,nx,ny,nz,nodes,frame_ms_mean,frame_ms_min,frame_ms_max,gpu_ms_mean"

    var csvRow: String {
        let g = configuration.grid
        return [String(configuration.step), String(g.nx), String(g.ny), String(g.nz), String(nodeCount),
                String(format: "%.3f", meanMilliseconds), String(format: "%.3f", minMilliseconds),
                String(format: "%.3f", maxMilliseconds), String(format: "%.3f", gpuMilliseconds)]
            .joined(separator: ",")
    }
}

nonisolated final class ResearchHarness {
    /// Фиксированная сцена: восемь занавесов, параметры по умолчанию, неподвижное время.
    static func fixedSettings(reflectances: [Reflectance]) -> RenderSettings {
        RenderSettings(
            curtains: (0..<AuroraLimits.maxCurtains).map(CurtainParameters.preset(index:)),
            seed: 2026,
            light: LightParameters(),
            medium: MediumParameters(),
            step: 0.4,
            gridSize: .maximum,
            reflectances: reflectances,
            showTerrain: true,
            showObjects: true,
            showLightMarker: true,
            animate: false,
            animationSpeed: 0
        )
    }

    static let fixedObserver = Observer(position: SIMD3(50, 4, 14), azimuth: 90, elevation: 15)
    static let fixedTime: Double = 10
    static let viewport = CGSize(width: 1920, height: 1080)

    private let controller: SceneController
    private let renderer: SCNRenderer
    private let queue: MTLCommandQueue
    private let pass: MTLRenderPassDescriptor
    private let baseSettings: RenderSettings

    enum SetupError: Error, CustomStringConvertible {
        case metal

        var description: String { "Не удалось подготовить вне-экранный рендер Metal" }
    }

    init(description: SceneDescription, heightmap: Heightmap, device: MTLDevice) throws {
        let graph = SceneGraph(description: description, heightmap: heightmap)
        controller = try SceneController(graph: graph, device: device)
        guard let queue = device.makeCommandQueue() else { throw SetupError.metal }
        self.queue = queue

        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: Int(Self.viewport.width), height: Int(Self.viewport.height),
            mipmapped: false)
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .private
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: Int(Self.viewport.width), height: Int(Self.viewport.height),
            mipmapped: false)
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        guard let color = device.makeTexture(descriptor: colorDescriptor),
              let depth = device.makeTexture(descriptor: depthDescriptor) else { throw SetupError.metal }
        pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1

        renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = graph.scene
        renderer.pointOfView = graph.cameraNode
        graph.place(camera: graph.cameraNode, at: Self.fixedObserver)
        graph.lightMarker.follow(graph.cameraNode)

        baseSettings = Self.fixedSettings(reflectances: description.allReflectances)
    }

    /// Прогоняет все конфигурации; на каждую — `warmup` кадров без замера и `frames` с замером.
    func run(_ configurations: [ResearchConfiguration], frames: Int = 30, warmup: Int = 5,
             isCancelled: () -> Bool = { false },
             progress: (ResearchMeasurement) -> Void) {
        controller.setTime(Self.fixedTime)
        for configuration in configurations {
            if isCancelled() { return }
            var settings = baseSettings
            settings.step = configuration.step
            settings.gridSize = configuration.grid.clamped()
            controller.apply(settings)

            var wall: [Double] = []
            var gpu: [Double] = []
            for frame in 0..<(warmup + frames) {
                let (wallTime, gpuTime) = renderFrame()
                if frame >= warmup {
                    wall.append(wallTime)
                    gpu.append(gpuTime)
                }
            }
            progress(ResearchMeasurement(
                configuration: configuration,
                meanMilliseconds: wall.reduce(0, +) / Double(wall.count),
                minMilliseconds: wall.min() ?? 0,
                maxMilliseconds: wall.max() ?? 0,
                gpuMilliseconds: gpu.reduce(0, +) / Double(gpu.count)
            ))
        }
    }

    /// Один кадр: синтез сетки и рендер в одном command buffer, ожидание завершения.
    private func renderFrame() -> (wall: Double, gpu: Double) {
        let start = CACurrentMediaTime()
        guard let commandBuffer = queue.makeCommandBuffer() else { return (0, 0) }
        controller.encodeAurora(into: commandBuffer)
        renderer.render(atTime: Self.fixedTime, viewport: CGRect(origin: .zero, size: Self.viewport),
                        commandBuffer: commandBuffer, passDescriptor: pass)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let wall = (CACurrentMediaTime() - start) * 1000
        let gpu = (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1000
        return (wall, gpu)
    }
}

nonisolated extension SceneDescription {
    /// Коэффициенты отражения в порядке поверхностей ParameterStore: ландшафт, затем объекты.
    var allReflectances: [Reflectance] {
        [terrain.reflectance.clamped()] + objects.map { $0.reflectance.clamped() }
    }
}
