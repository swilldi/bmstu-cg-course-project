//
//  SceneController.swift
//  NortherLights
//
//  Покадровая работа на потоке рендера: применение параметров к сцене, синтез сияния
//  (заполнение сетки) и обновление источников подсветки. Используется и интерактивным
//  окном (SceneRenderer), и режимом исследования (ResearchHarness).
//

import Metal
import SceneKit

nonisolated final class SceneController {
    let graph: SceneGraph
    let device: MTLDevice
    private let synthesizer: AuroraSynthesizer
    private let lightTable: AuroraLightTable
    private var grid: AuroraGrid?
    private var applied: RenderSettings?

    /// Время анимации сияния, с.
    private(set) var time: Double = 0
    private var lastSystemTime: TimeInterval?

    enum SetupError: Error, CustomStringConvertible {
        case metal(String)

        var description: String {
            switch self {
            case .metal(let what): "Metal: не удалось создать \(what)"
            }
        }
    }

    init(graph: SceneGraph, device: MTLDevice) throws {
        guard let synthesizer = AuroraSynthesizer(device: device) else { throw SetupError.metal("синтезатор сияния") }
        guard let lightTable = AuroraLightTable(device: device) else { throw SetupError.metal("таблицу источников") }
        self.graph = graph
        self.device = device
        self.synthesizer = synthesizer
        self.lightTable = lightTable
    }

    /// Переносит изменившиеся параметры в узлы и материалы сцены.
    func apply(_ settings: RenderSettings) {
        let previous = applied
        guard previous != settings else { return }
        applied = settings
        if previous?.light != settings.light {
            graph.apply(light: settings.light)
        }
        if previous?.reflectances != settings.reflectances {
            graph.apply(reflectances: settings.reflectances)
        }
        graph.terrainNode.isHidden = !settings.showTerrain
        graph.objectsNode.isHidden = !settings.showObjects
    }

    /// Продвигает время анимации по системному времени кадра.
    func advance(to systemTime: TimeInterval) {
        defer { lastSystemTime = systemTime }
        guard let settings = applied, settings.animate, let last = lastSystemTime else { return }
        // Ограничение шага — чтобы после паузы окна сияние не «прыгало».
        time += min(systemTime - last, 0.1) * Double(settings.animationSpeed)
    }

    /// Устанавливает время анимации явно (режим исследования — фиксированная сцена).
    func setTime(_ time: Double) {
        self.time = time
    }

    /// Кодирует синтез сияния в `commandBuffer` и обновляет подсветку сцены.
    func encodeAurora(into commandBuffer: MTLCommandBuffer) {
        guard let settings = applied else { return }
        if grid?.size != settings.gridSize {
            grid = AuroraGrid(device: device, size: settings.gridSize)
        }
        guard let grid else { return }
        let lights = synthesizer.synthesize(curtains: settings.curtains, seed: settings.seed, time: time,
                                            into: grid, commandBuffer: commandBuffer)
        graph.auroraVolume.update(grid: grid, medium: settings.medium, step: settings.step)
        graph.apply(lights: lightTable.upload(lights), count: lights.count, emission: settings.medium.emission)
    }
}
