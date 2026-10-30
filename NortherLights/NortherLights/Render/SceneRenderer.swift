//
//  SceneRenderer.swift
//  NortherLights
//
//  Делегат SCNView: связывает поток рендера SceneKit с ParameterStore.
//  GUI кладёт снимок параметров под замок, рендер забирает его в начале кадра;
//  обратно (положение камеры, время кадра) значения уходят на главный поток.
//

import Foundation
import Metal
import os
import SceneKit

nonisolated final class SceneRenderer: NSObject, SCNSceneRendererDelegate {
    let controller: SceneController
    private let pending: OSAllocatedUnfairLock<RenderSettings?> = .init(initialState: nil)
    /// Вызывается на главном потоке, когда наблюдатель сдвинулся мышью.
    private let onObserverChange: @MainActor @Sendable (Observer) -> Void
    private let onFrameTime: @MainActor @Sendable (Double) -> Void

    private var publishedObserver: Observer?
    private var lastPublish: TimeInterval = 0
    private var lastFrame: TimeInterval?
    private var frameTimes: [Double] = []

    init(controller: SceneController,
         onObserverChange: @escaping @MainActor @Sendable (Observer) -> Void,
         onFrameTime: @escaping @MainActor @Sendable (Double) -> Void) {
        self.controller = controller
        self.onObserverChange = onObserverChange
        self.onFrameTime = onFrameTime
    }

    /// Передаёт рендеру новый снимок параметров (с любого потока).
    func submit(_ settings: RenderSettings) {
        pending.withLock { $0 = settings }
    }

    // MARK: - SCNSceneRendererDelegate (поток рендера)

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if let settings = pending.withLock({ value -> RenderSettings? in
            defer { value = nil }
            return value
        }) {
            controller.apply(settings)
        }
        controller.advance(to: time)
        if let pointOfView = renderer.pointOfView {
            controller.graph.keepAboveTerrain(pointOfView)
        }
    }

    func renderer(_ renderer: any SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        // Свой command buffer в ту же очередь, что и кадр SceneKit: он закоммичен раньше,
        // поэтому сетка заполнена до того, как её прочитает фрагментный шейдер сияния.
        guard let commandBuffer = renderer.commandQueue?.makeCommandBuffer() else { return }
        commandBuffer.label = "Aurora synthesis"
        controller.encodeAurora(into: commandBuffer)
        commandBuffer.commit()
    }

    func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        recordFrame(at: time)
        publishObserver(renderer, at: time)
    }

    private func recordFrame(at time: TimeInterval) {
        defer { lastFrame = time }
        guard let lastFrame else { return }
        frameTimes.append((time - lastFrame) * 1000)
        if frameTimes.count >= 30 {
            let mean = frameTimes.reduce(0, +) / Double(frameTimes.count)
            frameTimes.removeAll(keepingCapacity: true)
            let callback = onFrameTime
            Task { @MainActor in callback(mean) }
        }
    }

    /// Отдаёт положение камеры в GUI не чаще пяти раз в секунду и только при изменении.
    private func publishObserver(_ renderer: any SCNSceneRenderer, at time: TimeInterval) {
        guard time - lastPublish > 0.2, let pointOfView = renderer.pointOfView else { return }
        lastPublish = time
        let observer = controller.graph.observer(of: pointOfView).rounded()
        guard observer != publishedObserver else { return }
        publishedObserver = observer
        let callback = onObserverChange
        Task { @MainActor in callback(observer) }
    }
}

nonisolated extension Observer {
    /// Округление до сотых — для текстовых полей и сравнения без дрожания.
    func rounded() -> Observer {
        func r(_ v: Float) -> Float { (v * 100).rounded() / 100 }
        return Observer(position: SIMD3(r(position.x), r(position.y), r(position.z)),
                        azimuth: r(azimuth), elevation: r(elevation))
    }
}
