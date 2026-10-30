//
//  NortherLightsApp.swift
//  NortherLights
//
//  Created by Dmitriy Dudyrev on 17.10.2026.
//

import SwiftUI

@main
struct NortherLightsApp: App {
    @State private var model = AppModel.load()

    var body: some Scene {
        WindowGroup("Северное сияние") {
            switch model {
            case .success(let model): ContentView(model: model)
            case .failure(let error): LoadErrorView(error: error)
            }
        }
        .defaultSize(width: 1400, height: 860)

        Window("Исследование времени синтеза кадра", id: ResearchView.windowID) {
            switch model {
            case .success(let model): ResearchView(model: model)
            case .failure(let error): LoadErrorView(error: error)
            }
        }
    }
}
