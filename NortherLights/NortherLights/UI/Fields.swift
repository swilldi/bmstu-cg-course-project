//
//  Fields.swift
//  NortherLights
//
//  Элементы ввода инспектора. Каждое значение задаётся текстовым полем (требование ТЗ),
//  у непрерывных величин рядом слайдер. Значение вне допустимого диапазона приводится
//  к ближайшей границе.
//

import SwiftUI

/// Числовой параметр: подпись, текстовое поле с единицами и слайдер под ними.
struct NumberField: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var unit: String?
    var digits = 2
    var slider = true
    /// Логарифмическая шкала слайдера — для величин, меняющихся на порядки (шаг Δs).
    var logarithmic = false

    init(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, unit: String? = nil,
         digits: Int = 2, slider: Bool = true, logarithmic: Bool = false) {
        self.title = title
        _value = value
        self.range = range
        self.unit = unit
        self.digits = digits
        self.slider = slider
        self.logarithmic = logarithmic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 4) {
                    TextField(title, value: clampedValue, format: .number.precision(.fractionLength(0...digits)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 64)
                    if let unit {
                        Text(unit)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 22, alignment: .leading)
                    }
                }
            }
            if slider, range.upperBound > range.lowerBound {
                Slider(value: sliderValue, in: sliderRange)
                    .controlSize(.small)
            }
        }
        .help("Допустимо: \(range.lowerBound.formatted()) … \(range.upperBound.formatted())")
    }

    private var clampedValue: Binding<Float> {
        Binding(get: { value }, set: { value = $0.clamped(to: range) })
    }

    private var sliderRange: ClosedRange<Double> {
        logarithmic ? log(Double(range.lowerBound))...log(Double(range.upperBound))
                    : Double(range.lowerBound)...Double(range.upperBound)
    }

    /// Слайдер округляет до той же точности, что и поле, чтобы не плодить «0,30000001».
    private var sliderValue: Binding<Double> {
        Binding(
            get: { logarithmic ? log(Double(value)) : Double(value) },
            set: { raw in
                let linear = logarithmic ? exp(raw) : raw
                let scale = pow(10, Double(digits))
                value = Float((linear * scale).rounded() / scale).clamped(to: range)
            }
        )
    }
}

/// Целочисленный параметр: текстовое поле и, при небольшом диапазоне, степпер.
struct IntegerField<Value: BinaryInteger>: View {
    let title: String
    @Binding var value: Value
    let range: ClosedRange<Int64>
    var stepper = false

    init(_ title: String, value: Binding<Value>, range: ClosedRange<Int64>, stepper: Bool = false) {
        self.title = title
        _value = value
        self.range = range
        self.stepper = stepper
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: wide, format: .number.grouping(.never))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: stepper ? 44 : 100)
                if stepper {
                    Stepper(title, value: wide, in: range)
                        .labelsHidden()
                }
            }
        }
        .help("Допустимо: \(range.lowerBound) … \(range.upperBound)")
    }

    private var wide: Binding<Int64> {
        Binding(get: { Int64(value) }, set: { value = Value($0.clamped(to: range)) })
    }
}

/// Цвет: палитра и три текстовых поля R, G, B в $[0;1]$.
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
                component(\.x, "R")
                component(\.y, "G")
                component(\.z, "B")
                ColorPicker(title, selection: pickerBinding, supportsOpacity: false)
                    .labelsHidden()
                    .padding(.leading, 2)
            }
        }
    }

    private func component(_ keyPath: WritableKeyPath<SIMD3<Float>, Float>, _ name: String) -> some View {
        TextField(name, value: Binding(get: { color[keyPath: keyPath] },
                                       set: { color[keyPath: keyPath] = $0.clamped(to: Ranges.unit) }),
                  format: .number.precision(.fractionLength(0...2)))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 40)
            .help("\(name), 0 … 1")
    }

    private var pickerBinding: Binding<Color> {
        Binding(
            get: { color.swiftUIColor },
            set: { newValue in
                guard let srgb = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                func r(_ v: CGFloat) -> Float { (Float(v) * 100).rounded() / 100 }
                color = SIMD3(r(srgb.redComponent), r(srgb.greenComponent), r(srgb.blueComponent))
                    .clamped(lowerBound: .zero, upperBound: .one)
            }
        )
    }
}

extension SIMD3<Float> {
    var swiftUIColor: Color {
        Color(.sRGB, red: Double(x), green: Double(y), blue: Double(z))
    }
}
