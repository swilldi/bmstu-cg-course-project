//
//  ParameretStoreView.swift
//  NortherLights
//
//  Created by Dmitriy on 20.09.2026.
//

import SwiftUI

struct ParameretStoreView: View {
    enum SeedValue {
        case a
        case custom(Int)
    }
    
    @Bindable var store: ParameretStore
    var body: some View {
        Text("Высоты границ").font(.title)
        Spinbox<Int>(value: $store.topHeight, title: "Верхняя")
        Spinbox<Int>(value: $store.bottomHeight, title: "Нижняя")
        
        Text("Протяженность").font(.title)
        Spinbox<Int>(value: $store.length)
        
        Text("Складчатость").font(.title)
        Spinbox<Int>(value: $store.inventory)
        
        Text("Seed").font(.title)
        
    }
}

struct Spinbox<V: Numeric>: View {
    @Binding var value: Int
    var title: String? = nil
    var range: ClosedRange<Int> = 0...100
    var step: Int = 10
    
    var body: some View {
        HStack {
            if let title = title {
                Text(title)
            }
            TextField("", value: $value, format: .number)
                .onChange(of: value) { _, newValue in
                    if newValue > range.upperBound { value = range.upperBound }
                    if newValue < range.lowerBound { value = range.lowerBound }
                }
            Button("", systemImage: "plus") {
                value += step
                if value > range.upperBound {
                    value = range.upperBound
                }
            }
            .disabled(value >= range.upperBound)
            
            Button("", systemImage: "minus") {
                value -= step
                if value < range.lowerBound {
                    value = range.lowerBound
                }
            }
            .disabled(value <= range.lowerBound)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .fixedSize(horizontal: true, vertical: true)
    }
}

#Preview {
    @Previewable @State var store = ParameretStore()
    ParameretStoreView(store: store)
//    Spinbox<Int>(value: $store.bottomHeight)
}
