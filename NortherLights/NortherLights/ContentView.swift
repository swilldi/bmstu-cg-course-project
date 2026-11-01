//
//  ContentView.swift
//  NortherLights
//
//  Created by Dmitriy Dudyrev on 17.10.2026.
//

import SwiftUI

struct ContentView: View {
    let model: AppModel
    @State private var showInspector = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var store = model.store
        SceneViewContainer(model: model)
            .ignoresSafeArea()
            .overlay(alignment: .bottomLeading) { StatusBadge(store: store) }
            .inspector(isPresented: $showInspector) {
                Inspector(store: store)
                    .inspectorColumnWidth(min: 320, ideal: 360, max: 440)
            }
            .navigationTitle("Северное сияние")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        store.animate.toggle()
                    } label: {
                        Label(store.animate ? "Пауза" : "Продолжить",
                              systemImage: store.animate ? "pause.fill" : "play.fill")
                    }
                    .help(store.animate ? "Остановить анимацию сияния" : "Запустить анимацию сияния")
                }
                ToolbarItem {
                    Button {
                        openWindow(id: ResearchView.windowID)
                    } label: {
                        Label("Исследование", systemImage: "chart.xyaxis.line")
                    }
                    .help("Исследование времени синтеза кадра")
                }
                ToolbarItem {
                    Button {
                        showInspector.toggle()
                    } label: {
                        Label("Параметры", systemImage: "sidebar.trailing")
                    }
                    .help(showInspector ? "Скрыть параметры" : "Показать параметры")
                }
            }
    }

    private var subtitle: String {
        let store = model.store
        let curtains = store.curtainCount
        let noun = switch curtains {
        case 1: "занавес"
        case 2...4: "занавеса"
        default: "занавесов"
        }
        return "\(curtains) \(noun) · сетка \(store.gridSize.description) · Δs \(store.step.formatted())"
    }
}

/// Время кадра поверх сцены.
private struct StatusBadge: View {
    let store: ParameterStore

    var body: some View {
        let fps = store.frameTime > 0 ? 1000 / store.frameTime : 0
        HStack(spacing: 6) {
            Image(systemName: "speedometer")
            Text("\(store.frameTime.formatted(.number.precision(.fractionLength(1)))) мс")
            Text("·").foregroundStyle(.secondary)
            Text("\(Int(fps.rounded())) к/с")
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .padding(14)
        .help("Среднее время кадра за последние 30 кадров")
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
