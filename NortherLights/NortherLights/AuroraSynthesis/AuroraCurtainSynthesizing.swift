//
//  AuroraCurtainSynthesizing.swift
//  NortherLights
//
//  Точка замены метода синтеза формы занавеса (паттерн Strategy).
//  Снаружи модуля `AuroraSynthesis` никто не знает, какая реализация активна:
//  рендер и GUI работают только с `AuroraSynthesizer` и `AuroraGrid`.
//

import Foundation

/// Основание занавеса в момент $t$, заданное в `sampleCount` равноотстоящих точках
/// $u_i = i\,\ell / (\text{sampleCount} - 1)$ вдоль основного направления.
nonisolated struct CurtainBase: Sendable {
    /// Отклонение основания $w(u_i, t)$, $|w| \le A$, у.е.
    var deviation: [Float]
    /// Множитель яркости вдоль занавеса $b(u_i, t) \in [0; 1]$.
    var brightness: [Float]
}

/// Метод процедурного синтеза формы и яркости основания занавеса.
/// Реализация должна быть детерминированной по `seed` и непрерывной по `time`.
nonisolated protocol AuroraCurtainSynthesizing: Sendable {
    func base(of curtain: CurtainParameters, seed: UInt32, time: Double, sampleCount: Int) -> CurtainBase
}
