//
//  PerlinCurtainSynthesizer.swift
//  NortherLights
//
//  Выбранный в аналитическом разделе метод: шум Перлина (раздел «Синтез формы занавеса»),
//  $w(u, t) = A \cdot \mathrm{noise}(u / \lambda,\ t / \tau)$.
//

import Foundation

nonisolated struct PerlinCurtainSynthesizer: AuroraCurtainSynthesizing {
    /// Постоянный масштаб времени $\tau$ для формы, с.
    var shapeTimeScale: Double = 7
    /// Масштаб времени для яркости — яркость меняется быстрее формы, с.
    var brightnessTimeScale: Double = 2.5
    /// Отношение длины «луча» яркости к длине складки.
    var brightnessDetail: Float = 0.35

    func base(of curtain: CurtainParameters, seed: UInt32, time: Double, sampleCount: Int) -> CurtainBase {
        let noise = PerlinNoise(seed: seed)
        let tShape = time / shapeTimeScale
        let tBright = time / brightnessTimeScale
        // Общая пульсация яркости всего занавеса.
        let pulse = 0.8 + 0.2 * noise.value(13.7, time / 4)

        var deviation = [Float](repeating: 0, count: sampleCount)
        var brightness = [Float](repeating: 0, count: sampleCount)
        let du = Double(curtain.length) / Double(sampleCount - 1)
        let lambda = Double(curtain.foldLength)
        for i in 0..<sampleCount {
            let u = Double(i) * du
            let w = noise.value(u / lambda, tShape).clamped(to: -1...1)
            deviation[i] = curtain.amplitude * Float(w)
            let b = 0.55 + 0.6 * noise.value(u / (lambda * Double(brightnessDetail)) + 37.1, tBright + 11.3)
            brightness[i] = Float((b * pulse).clamped(to: 0.05...1))
        }
        return CurtainBase(deviation: deviation, brightness: brightness)
    }
}

/// Двумерный градиентный шум Перлина [Hill 2002] с перестановкой, порождённой
/// генератором псевдослучайных чисел по начальному значению.
nonisolated struct PerlinNoise {
    private var permutation = [Int](repeating: 0, count: 512)

    init(seed: UInt32) {
        var generator = SplitMix64(seed: UInt64(seed))
        var p = Array(0..<256)
        for i in stride(from: 255, to: 0, by: -1) {
            p.swapAt(i, Int(generator.next() % UInt64(i + 1)))
        }
        for i in 0..<512 { permutation[i] = p[i & 255] }
    }

    /// Значение шума в точке $(x, y)$, примерно в $[-1; 1]$.
    func value(_ x: Double, _ y: Double) -> Double {
        let fx = floor(x), fy = floor(y)
        let xi = Int(fx) & 255, yi = Int(fy) & 255
        let xf = x - fx, yf = y - fy
        let u = Self.fade(xf), v = Self.fade(yf)
        let p = permutation
        let aa = p[p[xi] + yi], ab = p[p[xi] + yi + 1]
        let ba = p[p[xi + 1] + yi], bb = p[p[xi + 1] + yi + 1]
        let x1 = Self.lerp(Self.grad(aa, xf, yf), Self.grad(ba, xf - 1, yf), u)
        let x2 = Self.lerp(Self.grad(ab, xf, yf - 1), Self.grad(bb, xf - 1, yf - 1), u)
        return Self.lerp(x1, x2, v)
    }

    private static func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    private static func grad(_ hash: Int, _ x: Double, _ y: Double) -> Double {
        switch hash & 7 {
        case 0: x + y
        case 1: -x + y
        case 2: x - y
        case 3: -x - y
        case 4: x
        case 5: -x
        case 6: y
        default: -y
        }
    }
}

/// Генератор псевдослучайных чисел SplitMix64: детерминирован по начальному значению.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextFloat(in range: ClosedRange<Float>) -> Float {
        Float.random(in: range, using: &self)
    }
}
