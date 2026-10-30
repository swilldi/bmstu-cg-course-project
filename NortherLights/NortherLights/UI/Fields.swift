//
//  Fields.swift
//  NortherLights
//
//  Текстовые поля ввода с ограничением диапазона: значение вне допустимого
//  диапазона приводится к ближайшей границе при подтверждении ввода.
//

import SwiftUI

struct NumberField: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var digits = 2

    init(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, digits: Int = 2) {
        self.title = title
        _value = value
        self.range = range
        self.digits = digits
    }

    var body: some View {
        LabeledContent(title) {
            TextField(title, value: Binding(get: { value }, set: { value = $0.clamped(to: range) }),
                      format: .number.precision(.fractionLength(0...digits)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
        .help("Диапазон: \(range.lowerBound.formatted()) … \(range.upperBound.formatted())")
    }
}

struct IntegerField<Value: BinaryInteger>: View {
    let title: String
    @Binding var value: Value
    let range: ClosedRange<Int64>

    init(_ title: String, value: Binding<Value>, range: ClosedRange<Int64>) {
        self.title = title
        _value = value
        self.range = range
    }

    var body: some View {
        LabeledContent(title) {
            TextField(title, value: Binding(get: { Int64(value) }, set: { value = Value($0.clamped(to: range)) }),
                      format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
        .help("Диапазон: \(range.lowerBound) … \(range.upperBound)")
    }
}

/// Цвет — три текстовых поля R, G, B в $[0;1]$ и палитра.
struct ColorField: View {
    let title: String
    @Binding var color: SIMD3<Float>

    init(_ title: String, color: Binding<SIMD3<Float>>) {
        self.title = title
        _color = color
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                component(\.x)
                component(\.y)
                component(\.z)
                ColorPicker(title, selection: pickerBinding, supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    private func component(_ keyPath: WritableKeyPath<SIMD3<Float>, Float>) -> some View {
        TextField(title, value: Binding(get: { color[keyPath: keyPath] },
                                        set: { color[keyPath: keyPath] = $0.clamped(to: Ranges.unit) }),
                  format: .number.precision(.fractionLength(0...2)))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
    }

    private var pickerBinding: Binding<Color> {
        Binding(
            get: { Color(.sRGB, red: Double(color.x), green: Double(color.y), blue: Double(color.z)) },
            set: { newValue in
                guard let srgb = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                func r(_ v: CGFloat) -> Float { (Float(v) * 100).rounded() / 100 }
                color = SIMD3(r(srgb.redComponent), r(srgb.greenComponent), r(srgb.blueComponent))
                    .clamped(lowerBound: .zero, upperBound: .one)
            }
        )
    }
}
