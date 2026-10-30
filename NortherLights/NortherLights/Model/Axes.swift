//
//  Axes.swift
//  NortherLights
//
//  Единственное место, где задано соответствие осей РПЗ и SceneKit.
//

import simd

/// В РПЗ ось $z$ направлена вверх, сцена по горизонтали — квадрат $[0;100]\times[0;100]$.
/// В SceneKit вверх направлена ось Y. Отображение $(x, y, z) \mapsto (x, z, -y)$ — поворот
/// на $-90^\circ$ вокруг оси $x$, правая тройка сохраняется. Те же формулы повторены в
/// `AuroraVolume.metal` (переход из мировых координат SceneKit в координаты сетки).
nonisolated enum Axes {
    static func scene(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(p.x, p.z, -p.y) }
    static func rpz(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(p.x, -p.z, p.y) }

    /// Вертикальная ось SceneKit.
    static let up = SIMD3<Float>(0, 1, 0)
}
