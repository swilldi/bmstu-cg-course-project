//
//  SceneViewContainer.swift
//  NortherLights
//
//  SCNView в SwiftUI. Камера — узел камеры + встроенный контроллер SceneKit
//  (орбита мышью, зум колесом); положение из текстовых полей пишется в тот же узел.
//

import Observation
import SceneKit
import SwiftUI

struct SceneViewContainer: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> SCNView {
        let graph = model.renderer.controller.graph
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredDevice.rawValue: model.device])
        view.scene = graph.scene
        view.pointOfView = graph.cameraNode
        view.delegate = model.renderer
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 120
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {}

    @MainActor
    final class Coordinator {
        private let model: AppModel
        private weak var view: SCNView?
        private var appliedCameraRequest = -1

        init(model: AppModel) {
            self.model = model
        }

        func attach(_ view: SCNView) {
            self.view = view
            observeSettings()
            observeCameraRequests()
        }

        /// Каждое изменение параметров уходит в рендер снимком. Подписка одноразовая и
        /// возобновляется после каждого срабатывания; координатор держится слабо.
        private func observeSettings() {
            let coordinator = WeakReference(self)
            let settings = withObservationTracking {
                model.store.renderSettings
            } onChange: {
                Task { @MainActor in coordinator.value?.observeSettings() }
            }
            model.renderer.submit(settings)
        }

        private func observeCameraRequests() {
            let coordinator = WeakReference(self)
            let request = withObservationTracking {
                model.store.cameraRequest
            } onChange: {
                Task { @MainActor in coordinator.value?.observeCameraRequests() }
            }
            guard request.id != appliedCameraRequest, let view, let pointOfView = view.pointOfView else { return }
            appliedCameraRequest = request.id
            let graph = model.renderer.controller.graph
            graph.place(camera: pointOfView, at: request.observer)
            // Орбита мышью — вокруг точки, на которую смотрит наблюдатель.
            let eye = pointOfView.simdWorldPosition
            let forward = pointOfView.simdWorldOrientation.act(SIMD3(0, 0, -1))
            view.defaultCameraController.target = SCNVector3(eye + forward * 30)
        }
    }
}

/// Слабая ссылка, которую можно захватить в `@Sendable`-замыкании.
@MainActor
private final class WeakReference<Object: AnyObject> {
    weak var value: Object?

    init(_ value: Object) {
        self.value = value
    }
}
