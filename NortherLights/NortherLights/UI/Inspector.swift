//
//  Inspector.swift
//  NortherLights
//
//  Инспектор параметров справа от сцены: вкладки по группам параметров ТЗ.
//  Читает и пишет ParameterStore напрямую.
//

import SwiftUI

struct Inspector: View {
    @Bindable var store: ParameterStore
    @State private var tab = Tab.aurora

    enum Tab: String, CaseIterable, Identifiable {
        case aurora, medium, light, scene, observer

        var id: Self { self }

        var title: String {
            switch self {
            case .aurora: "Сияние"
            case .medium: "Среда"
            case .light: "Свет"
            case .scene: "Сцена"
            case .observer: "Наблюдатель"
            }
        }

        var symbol: String {
            switch self {
            case .aurora: "sparkles"
            case .medium: "cloud.fog"
            case .light: "sun.max"
            case .scene: "mountain.2"
            case .observer: "camera"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Раздел", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Image(systemName: tab.symbol)
                        .help(tab.title)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Text(tab.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)

            Form {
                switch tab {
                case .aurora: AuroraTab(store: store)
                case .medium: MediumTab(store: store)
                case .light: LightTab(store: store)
                case .scene: SceneTab(store: store)
                case .observer: ObserverTab(store: store)
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Сияние

private struct AuroraTab: View {
    @Bindable var store: ParameterStore
    @State private var selected = 0

    var body: some View {
        Section {
            IntegerField("Число занавесов K", value: $store.curtainCount,
                         range: Int64(Ranges.curtainCount.lowerBound)...Int64(Ranges.curtainCount.upperBound),
                         stepper: true)
            IntegerField("Начальное значение r₀", value: $store.seed, range: Ranges.seed)
        } footer: {
            Text("Положение и направление занавесов порождаются генератором по r₀.")
        }

        Section {
            Picker("Занавес", selection: $selected) {
                ForEach(0..<store.curtainCount, id: \.self) { k in
                    Text("\(k + 1)").tag(k)
                }
            }
            .pickerStyle(.segmented)

            let curtain = curtainBinding
            NumberField("Нижняя граница h_min", value: curtain.hMin,
                        range: Ranges.glowHeight.lowerBound...(curtain.wrappedValue.hMax - 1), unit: "у.е.", digits: 1)
            NumberField("Верхняя граница h_max", value: curtain.hMax,
                        range: (curtain.wrappedValue.hMin + 1)...Ranges.glowHeight.upperBound, unit: "у.е.", digits: 1)
            NumberField("Протяжённость ℓ", value: curtain.length, range: Ranges.length, unit: "у.е.", digits: 1)
            NumberField("Амплитуда складок A", value: curtain.amplitude, range: Ranges.amplitude, unit: "у.е.", digits: 1)
            NumberField("Длина складки λ", value: curtain.foldLength, range: 1...curtain.wrappedValue.length,
                        unit: "у.е.", digits: 1)
        } header: {
            Text("Занавес")
        }

        Section {
            let curtain = curtainBinding
            HeightGradient(curtain: curtain.wrappedValue)
            ColorField("Низ", color: curtain.colorLow)
            ColorField("Середина", color: curtain.colorMid)
            ColorField("Верх", color: curtain.colorHigh)
        } header: {
            Text("Цвет по высоте")
        } footer: {
            Text("Трети высоты свечения; RGB в [0; 1].")
        }

        Section("Анимация") {
            Toggle("Форма и яркость меняются", isOn: $store.animate)
            NumberField("Скорость", value: $store.animationSpeed, range: 0...10, unit: "×", digits: 1)
                .disabled(!store.animate)
        }
        .onChange(of: store.curtainCount) { _, count in
            selected = min(selected, count - 1)
        }
    }

    /// Привязка к выбранному занавесу; при уменьшении ℓ длина складки не превышает ℓ.
    private var curtainBinding: Binding<CurtainParameters> {
        let index = min(selected, store.curtains.count - 1)
        return Binding(
            get: { store.curtains[index] },
            set: { newValue in
                var curtain = newValue
                curtain.foldLength = min(curtain.foldLength, curtain.length)
                store.curtains[index] = curtain
            }
        )
    }
}

/// Предпросмотр цвета занавеса по высоте: слева направо низ → середина → верх.
private struct HeightGradient: View {
    let curtain: CurtainParameters

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: curtain.colorLow.swiftUIColor, location: 0.15),
                .init(color: curtain.colorMid.swiftUIColor, location: 0.5),
                .init(color: curtain.colorHigh.swiftUIColor, location: 0.85),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 14)
        .clipShape(.capsule)
        .overlay(Capsule().strokeBorder(.separator))
        .accessibilityHidden(true)
    }
}

// MARK: - Среда и расчёт

private struct MediumTab: View {
    @Bindable var store: ParameterStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section {
            NumberField("Излучение ε", value: $store.medium.emission, range: Ranges.emission)
            NumberField("Поглощение κ", value: $store.medium.absorption, range: Ranges.absorption,
                        unit: "у.е.⁻¹", digits: 3)
        } header: {
            Text("Светящаяся среда")
        }

        Section {
            NumberField("Шаг интегрирования Δs", value: $store.step, range: Ranges.step, unit: "у.е.",
                        logarithmic: true)
            LabeledContent("Сетка") {
                HStack(spacing: 4) {
                    gridField(\.nx, range: Ranges.gridXY)
                    Text("×").foregroundStyle(.secondary)
                    gridField(\.ny, range: Ranges.gridXY)
                    Text("×").foregroundStyle(.secondary)
                    gridField(\.nz, range: Ranges.gridZ)
                }
            }
        } header: {
            Text("Расчёт")
        } footer: {
            Text("Сетка не больше \(GridSize.maximum.description) узлов.")
        }

        Section {
            Button {
                openWindow(id: ResearchView.windowID)
            } label: {
                Label("Исследование времени кадра…", systemImage: "chart.xyaxis.line")
            }
        }
    }

    private func gridField(_ keyPath: WritableKeyPath<GridSize, Int>, range: ClosedRange<Int>) -> some View {
        TextField("", value: Binding(get: { store.gridSize[keyPath: keyPath] },
                                     set: { store.gridSize[keyPath: keyPath] = $0.clamped(to: range) }),
                  format: .number.grouping(.never))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 44)
            .help("\(range.lowerBound) … \(range.upperBound)")
    }
}

// MARK: - Источник света

private struct LightTab: View {
    @Bindable var store: ParameterStore

    var body: some View {
        Section {
            SkyDial(azimuth: $store.light.azimuth, elevation: $store.light.elevation, color: store.light.color)
            NumberField("Азимут φ_L", value: $store.light.azimuth, range: Ranges.lightAzimuth, unit: "°", digits: 0)
            NumberField("Высота θ_L", value: $store.light.elevation, range: Ranges.lightElevation, unit: "°", digits: 0)
        } header: {
            Text("Направление")
        } footer: {
            Text("Источник на схеме неба можно перетаскивать мышью: край — горизонт, центр — зенит.")
        }

        Section {
            NumberField("Интенсивность I_L", value: $store.light.intensity, range: Ranges.unit)
            ColorField("Цвет C_L", color: $store.light.color)
            Toggle("Показывать на небе", isOn: $store.showLightMarker)
        } header: {
            Text("Излучение")
        } footer: {
            Text("Единственный источник на бесконечности; от него строятся тени.")
        }
    }
}

/// Схема неба в полярных координатах: азимут — угол (север сверху, восток справа,
/// $\varphi$ отсчитывается от востока против часовой стрелки), высота — расстояние
/// от края (горизонт, $\theta = 0^\circ$) к центру (зенит, $\theta = 90^\circ$).
private struct SkyDial: View {
    @Binding var azimuth: Float
    @Binding var elevation: Float
    let color: SIMD3<Float>

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = size / 2 - 14
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                Canvas { context, _ in
                    // Горизонт и круги высоты 30° и 60°.
                    for fraction in [1.0, 2.0 / 3, 1.0 / 3] {
                        let r = radius * fraction
                        let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                        context.stroke(circle, with: .style(.separator), lineWidth: fraction == 1 ? 1.5 : 0.75)
                    }
                    var cross = Path()
                    cross.move(to: CGPoint(x: center.x - radius, y: center.y))
                    cross.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                    cross.move(to: CGPoint(x: center.x, y: center.y - radius))
                    cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                    context.stroke(cross, with: .style(.separator), lineWidth: 0.5)
                    // Луч от наблюдателя к источнику.
                    var ray = Path()
                    ray.move(to: center)
                    ray.addLine(to: point(center: center, radius: radius))
                    context.stroke(ray, with: .color(color.swiftUIColor.opacity(0.8)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                ForEach(Self.compass, id: \.label) { mark in
                    Text(mark.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .position(x: center.x + (radius + 9) * mark.dx, y: center.y - (radius + 9) * mark.dy)
                }
                Circle()
                    .fill(color.swiftUIColor.gradient)
                    .frame(width: 18, height: 18)
                    .shadow(color: color.swiftUIColor.opacity(0.9), radius: 8)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                    .position(point(center: center, radius: radius))
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                update(from: drag.location, center: center, radius: radius)
            })
        }
        .frame(height: 190)
        .accessibilityElement()
        .accessibilityLabel("Направление на источник")
        .accessibilityValue("азимут \(Int(azimuth))°, высота \(Int(elevation))°")
    }

    private static let compass: [(label: String, dx: CGFloat, dy: CGFloat)] = [
        ("С", 0, 1), ("В", 1, 0), ("Ю", 0, -1), ("З", -1, 0),
    ]

    private func point(center: CGPoint, radius: CGFloat) -> CGPoint {
        let r = radius * CGFloat(1 - elevation / 90)
        let phi = CGFloat(azimuth.radians)
        return CGPoint(x: center.x + r * cos(phi), y: center.y - r * sin(phi))
    }

    private func update(from location: CGPoint, center: CGPoint, radius: CGFloat) {
        let dx = location.x - center.x, dy = center.y - location.y
        var phi = Float(atan2(dy, dx)).degrees
        if phi < 0 { phi += 360 }
        let r = min(hypot(dx, dy) / radius, 1)
        azimuth = phi.rounded().clamped(to: Ranges.lightAzimuth)
        elevation = (90 * (1 - Float(r))).rounded().clamped(to: Ranges.lightElevation)
    }
}

// MARK: - Сцена

private struct SceneTab: View {
    @Bindable var store: ParameterStore
    @State private var selected = 0

    var body: some View {
        Section {
            Picker("Поверхность", selection: $selected) {
                ForEach(store.surfaces) { surface in
                    Text(surface.name).tag(surface.id)
                }
            }
            let reflectance = $store.surfaces[selected].reflectance
            NumberField("Диффузное k_d", value: reflectance.kd, range: 0...(1 - reflectance.wrappedValue.ks))
            NumberField("Зеркальное k_s", value: reflectance.ks, range: 0...(1 - reflectance.wrappedValue.kd))
            NumberField("Блеск n", value: reflectance.n, range: Ranges.shininess, digits: 0, logarithmic: true)
        } header: {
            Text("Отражающие свойства")
        } footer: {
            Text("k_d + k_s ≤ 1. Начальные значения — из файла описания сцены.")
        }

        Section("Отображение") {
            Toggle("Ландшафт", isOn: $store.showTerrain)
            Toggle("Объекты", isOn: $store.showObjects)
        }
    }
}

// MARK: - Наблюдатель

/// Поля показывают текущую камеру (в том числе после управления мышью);
/// ввод значения и Enter переносят камеру.
private struct ObserverTab: View {
    let store: ParameterStore
    @State private var draft = Observer.initial

    var body: some View {
        Group {
            observerFields
            applySection
        }
        .onAppear { draft = store.observer }
        .onChange(of: store.observer) { _, observer in draft = observer }
        .onSubmit { store.applyObserver(draft) }
    }

    private var observerFields: some View {
        Section {
            LabeledContent("Положение P_V") {
                HStack(spacing: 4) {
                    coordinate(\.x, "x", range: 0...Heightmap.extent)
                    coordinate(\.y, "y", range: 0...Heightmap.extent)
                    coordinate(\.z, "z", range: 0...200)
                }
            }
            NumberField("Азимут взгляда φ_V", value: $draft.azimuth, range: Ranges.viewAzimuth, unit: "°",
                        digits: 1, slider: false)
            NumberField("Угол места θ_V", value: $draft.elevation, range: Ranges.viewElevation, unit: "°",
                        digits: 1, slider: false)
        } header: {
            Text("Положение и взгляд")
        } footer: {
            Text("Координаты в у.е.; z_V не опускается ниже рельефа.")
        }
    }

    private var applySection: some View {
        Section {
            Button("Перенести наблюдателя") { store.applyObserver(draft) }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Label("Перетаскивание — осмотр сцены", systemImage: "hand.draw")
                Label("Колесо или щипок — приближение", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            }
        }
    }

    private func coordinate(_ keyPath: WritableKeyPath<SIMD3<Float>, Float>, _ name: String,
                            range: ClosedRange<Float>) -> some View {
        TextField(name, value: Binding(get: { draft.position[keyPath: keyPath] },
                                       set: { draft.position[keyPath: keyPath] = $0.clamped(to: range) }),
                  format: .number.precision(.fractionLength(0...1)))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 52)
            .help("\(name)_V")
    }
}
