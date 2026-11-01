//
//  ParameterStore.swift
//  NortherLights
//
//  Единственный источник правды по всем пользовательским значениям.
//  GUI читает и пишет его напрямую; рендер получает неизменяемый снимок `RenderSettings`.
//

import Foundation
import Observation

/// Поверхность, коэффициенты отражения которой пользователь может менять.
nonisolated struct SurfaceSettings: Hashable, Sendable, Identifiable {
    var id: Int
    var name: String
    var reflectance: Reflectance
}

/// Снимок параметров для рендера: значение, а не ссылка, — его безопасно передавать
/// в поток рендера SceneKit.
nonisolated struct RenderSettings: Equatable, Sendable {
    var curtains: [CurtainParameters]
    var seed: UInt32
    var light: LightParameters
    var medium: MediumParameters
    var step: Float
    var gridSize: GridSize
    /// Индекс 0 — ландшафт, далее объекты в порядке файла описания сцены.
    var reflectances: [Reflectance]
    var showTerrain: Bool
    var showObjects: Bool
    var showLightMarker: Bool
    var animate: Bool
    var animationSpeed: Float
}

/// Запрос на перенос камеры из текстовых полей; `id` растёт при каждом вводе.
nonisolated struct CameraRequest: Equatable, Sendable {
    var id: Int
    var observer: Observer
}

@Observable
final class ParameterStore {
    /// Параметры всех восьми возможных занавесов; активны первые `curtainCount`.
    var curtains: [CurtainParameters] = (0..<AuroraLimits.maxCurtains).map(CurtainParameters.preset(index:))
    var curtainCount = 3
    /// Начальное значение генератора псевдослучайных чисел $r_0$.
    var seed: UInt32 = 2026

    var light = LightParameters()
    var medium = MediumParameters()
    /// Шаг интегрирования вдоль луча $\Delta s$, у.е.
    var step: Float = 0.4
    var gridSize = GridSize.maximum

    var surfaces: [SurfaceSettings]
    var showTerrain = true
    var showObjects = true
    /// Показывать источник на бесконечности диском на небе.
    var showLightMarker = true
    var animate = true
    var animationSpeed: Float = 1

    /// Текущее положение наблюдателя: обновляется рендером при управлении мышью
    /// и пользователем через текстовые поля.
    var observer = Observer.initial
    private(set) var cameraRequest = CameraRequest(id: 0, observer: .initial)

    /// Средняя длительность кадра по последним кадрам, мс (для строки состояния).
    var frameTime: Double = 0

    init(scene: SceneDescription) {
        var surfaces = [SurfaceSettings(id: 0, name: "Ландшафт", reflectance: scene.terrain.reflectance.clamped())]
        for (k, object) in scene.objects.enumerated() {
            surfaces.append(SurfaceSettings(id: k + 1, name: object.name, reflectance: object.reflectance.clamped()))
        }
        self.surfaces = surfaces
    }

    /// Переносит камеру в положение из текстовых полей.
    func applyObserver(_ observer: Observer) {
        self.observer = observer
        cameraRequest = CameraRequest(id: cameraRequest.id + 1, observer: observer)
    }

    var renderSettings: RenderSettings {
        RenderSettings(
            curtains: Array(curtains.prefix(curtainCount)),
            seed: seed,
            light: light,
            medium: medium,
            step: step,
            gridSize: gridSize,
            reflectances: surfaces.map(\.reflectance),
            showTerrain: showTerrain,
            showObjects: showObjects,
            showLightMarker: showLightMarker,
            animate: animate,
            animationSpeed: animationSpeed
        )
    }
}
