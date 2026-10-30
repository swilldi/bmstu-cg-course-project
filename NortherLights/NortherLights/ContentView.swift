//
//  ContentView.swift
//  NortherLights
//
//  Created by Dmitriy Dudyrev on 17.10.2026.
//

import SwiftUI

struct ContentView: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SceneViewContainer(model: model)
                .overlay(alignment: .topLeading) { StatusBadge(store: model.store) }
            Divider()
            ControlPanel(store: model.store)
                .frame(width: 390)
        }
    }
}

private struct StatusBadge: View {
    let store: ParameterStore

    var body: some View {
        let fps = store.frameTime > 0 ? 1000 / store.frameTime : 0
        Text("Кадр \(store.frameTime.formatted(.number.precision(.fractionLength(1)))) мс · \(Int(fps.rounded())) к/с · сетка \(store.gridSize.description) · Δs \(store.step.formatted())")
            .font(.caption.monospacedDigit())
            .padding(6)
            .background(.black.opacity(0.5), in: .rect(cornerRadius: 6))
            .foregroundStyle(.white)
            .padding(8)
    }
}

/// Сообщение, если сцену не удалось загрузить.
struct LoadErrorView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView("Сцена не загружена", systemImage: "exclamationmark.triangle",
                               description: Text(String(describing: error)))
    }
}
