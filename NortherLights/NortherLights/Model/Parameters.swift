//
//  Parameters.swift
//  NortherLights
//
//  Значения пользовательских параметров и их допустимые диапазоны
//  (таблица «Допустимые диапазоны входных параметров» РПЗ).
//

import Foundation
import simd

/// Диапазоны из таблицы входных параметров РПЗ — единственное место, где они записаны.
nonisolated enum Ranges {
    static let lightAzimuth: ClosedRange<Float> = 0...359.99
    static let lightElevation: ClosedRange<Float> = 0...90
    static let unit: ClosedRange<Float> = 0...1
    static let curtainCount: ClosedRange<Int> = 1...AuroraLimits.maxCurtains
    static let glowHeight: ClosedRange<Float> = 10...60
    static let length: ClosedRange<Float> = 5...100
    static let amplitude: ClosedRange<Float> = 0...20
    static let shininess: ClosedRange<Float> = 1...256
    static let emission: ClosedRange<Float> = 0...10
    static let absorption: ClosedRange<Float> = 0...1
    static let seed: ClosedRange<Int64> = 0...Int64(UInt32.max)
    static let viewAzimuth: ClosedRange<Float> = 0...359.99
    static let viewElevation: ClosedRange<Float> = -90...90
    static let gridXY: ClosedRange<Int> = 16...AuroraLimits.maxGrid.x
    static let gridZ: ClosedRange<Int> = 8...AuroraLimits.maxGrid.z
    static let step: ClosedRange<Float> = 0.05...5
}

/// Жёсткие ограничения ТЗ на сияние.
nonisolated enum AuroraLimits {
    static let maxCurtains = 8
    static let maxGrid = (x: 256, y: 256, z: 128)
    /// Точечных источников подсветки на один занавес (раздел «Освещение сцены свечением сияния»).
    static let lightsPerCurtain = 4
    static let maxLights = maxCurtains * lightsPerCurtain
}

/// Коэффициенты отражения поверхности для модели Блинна — Фонга.
nonisolated struct Reflectance: Codable, Hashable, Sendable {
    var kd: Float
    var ks: Float
    var n: Float

    /// Приводит к ограничениям $k_d, k_s \in [0;1]$, $k_d + k_s \le 1$, $n \in [1;256]$.
    func clamped() -> Reflectance {
        let kd = kd.clamped(to: Ranges.unit)
        let ks = ks.clamped(to: 0...(1 - kd))
        return Reflectance(kd: kd, ks: ks, n: n.clamped(to: Ranges.shininess))
    }
}

/// Параметры одного занавеса (раздел «Формализация объектов сцены»).
nonisolated struct CurtainParameters: Hashable, Sendable {
    /// Границы свечения $h_{\min}$, $h_{\max}$, у.е.
    var hMin: Float
    var hMax: Float
    /// Протяжённость $\ell$, у.е.
    var length: Float
    /// Амплитуда складок $A$, у.е.
    var amplitude: Float
    /// Характерная длина складки $\lambda$, у.е.
    var foldLength: Float
    /// Цвета нижней, средней и верхней третей высоты свечения.
    var colorLow: SIMD3<Float>
    var colorMid: SIMD3<Float>
    var colorHigh: SIMD3<Float>

    static func preset(index k: Int) -> CurtainParameters {
        let f = Float(k)
        return CurtainParameters(
            hMin: 12 + 1.5 * Float(k % 3),
            hMax: 38 + 3 * Float(k % 4),
            length: 55 + 6 * Float(k % 4),
            amplitude: 5 + Float(k % 3) * 1.5,
            foldLength: 10 + 2 * Float(k % 3),
            colorLow: SIMD3(0.95, 0.30, 0.55),
            colorMid: SIMD3(0.20, 1.00, 0.45 + 0.05 * f.truncatingRemainder(dividingBy: 2)),
            colorHigh: SIMD3(0.55, 0.20, 0.85)
        )
    }
}

nonisolated struct LightParameters: Hashable, Sendable {
    /// Азимут $\varphi_L$ и высота над горизонтом $\theta_L$, градусы.
    // Луна над сценой слева от сияния — видна с начального положения наблюдателя.
    var azimuth: Float = 125
    var elevation: Float = 22
    var intensity: Float = 0.35
    var color = SIMD3<Float>(0.70, 0.78, 1.00)

    /// Единичный вектор на источник в координатах РПЗ, формула (1.1).
    var direction: SIMD3<Float> {
        let phi = azimuth.radians, theta = elevation.radians
        return SIMD3(cos(theta) * cos(phi), cos(theta) * sin(phi), sin(theta))
    }
}

/// Коэффициенты излучения $\varepsilon$ и поглощения $\kappa$ светящейся среды.
nonisolated struct MediumParameters: Hashable, Sendable {
    var emission: Float = 0.6
    var absorption: Float = 0.08
}

nonisolated struct GridSize: Hashable, Sendable, CustomStringConvertible {
    var nx: Int
    var ny: Int
    var nz: Int

    static let maximum = GridSize(nx: AuroraLimits.maxGrid.x, ny: AuroraLimits.maxGrid.y, nz: AuroraLimits.maxGrid.z)

    func clamped() -> GridSize {
        GridSize(nx: nx.clamped(to: Ranges.gridXY), ny: ny.clamped(to: Ranges.gridXY), nz: nz.clamped(to: Ranges.gridZ))
    }

    var description: String { "\(nx)×\(ny)×\(nz)" }
}

/// Положение наблюдателя $P_V$ (координаты РПЗ) и направление взгляда $\varphi_V$, $\theta_V$ (градусы).
nonisolated struct Observer: Hashable, Sendable {
    var position: SIMD3<Float>
    var azimuth: Float
    var elevation: Float

    var direction: SIMD3<Float> {
        let phi = azimuth.radians, theta = elevation.radians
        return SIMD3(cos(theta) * cos(phi), cos(theta) * sin(phi), sin(theta))
    }

    static let initial = Observer(position: SIMD3(50, 4, 14), azimuth: 90, elevation: 12)
}

nonisolated extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

nonisolated extension Float {
    var radians: Float { self * .pi / 180 }
    var degrees: Float { self * 180 / .pi }
}
