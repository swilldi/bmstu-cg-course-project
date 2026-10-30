//
//  ControlPanel.swift
//  NortherLights
//
//  Панель пользовательских параметров: читает и пишет ParameterStore напрямую.
//

import SwiftUI

struct ControlPanel: View {
    @Bindable var store: ParameterStore
    @State private var selectedCurtain = 0
    @State private var selectedSurface = 0
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            auroraSection
            curtainSection
            mediumSection
            lightSection
            surfaceSection
            ObserverSection(store: store)
            viewSection
        }
        .formStyle(.grouped)
        .onChange(of: store.curtainCount) { _, count in
            selectedCurtain = min(selectedCurtain, count - 1)
        }
    }

    // MARK: - Сияние

    private var auroraSection: some View {
        Section("Сияние") {
            IntegerField("Число занавесов K", value: $store.curtainCount,
                         range: Int64(Ranges.curtainCount.lowerBound)...Int64(Ranges.curtainCount.upperBound))
            IntegerField("Начальное значение ГПСЧ r₀", value: $store.seed, range: Ranges.seed)
        }
    }

    private var curtainSection: some View {
        Section {
            Picker("Занавес", selection: $selectedCurtain) {
                ForEach(0..<store.curtainCount, id: \.self) { k in
                    Text("№ \(k + 1)").tag(k)
                }
            }
            let curtain = curtainBinding
            NumberField("Нижняя граница hₘᵢₙ", value: curtain.hMin,
                        range: Ranges.glowHeight.lowerBound...(curtain.wrappedValue.hMax - 1))
            NumberField("Верхняя граница hₘₐₓ", value: curtain.hMax,
                        range: (curtain.wrappedValue.hMin + 1)...Ranges.glowHeight.upperBound)
            NumberField("Протяжённость ℓ", value: curtain.length, range: Ranges.length)
            NumberField("Амплитуда складок A", value: curtain.amplitude, range: Ranges.amplitude)
            NumberField("Длина складки λ", value: curtain.foldLength, range: 1...curtain.wrappedValue.length)
            ColorField("Цвет нижней части", color: curtain.colorLow)
            ColorField("Цвет средней части", color: curtain.colorMid)
            ColorField("Цвет верхней части", color: curtain.colorHigh)
        } header: {
            Text("Занавес")
        } footer: {
            Text("Высоты и длины — в у.е.; цвета — RGB в [0; 1].")
        }
    }

    /// Привязка к выбранному занавесу; при уменьшении ℓ длина складки не превышает ℓ.
    private var curtainBinding: Binding<CurtainParameters> {
        let index = min(selectedCurtain, store.curtains.count - 1)
        return Binding(
            get: { store.curtains[index] },
            set: { newValue in
                var curtain = newValue
                curtain.foldLength = min(curtain.foldLength, curtain.length)
                store.curtains[index] = curtain
            }
        )
    }

    // MARK: - Среда и расчёт

    private var mediumSection: some View {
        Section {
            NumberField("Излучение ε", value: $store.medium.emission, range: Ranges.emission)
            NumberField("Поглощение κ, у.е.⁻¹", value: $store.medium.absorption, range: Ranges.absorption, digits: 3)
            NumberField("Шаг интегрирования Δs", value: $store.step, range: Ranges.step)
            LabeledContent("Сетка Nx × Ny × Nz") {
                HStack(spacing: 4) {
                    gridField(\.nx, range: Ranges.gridXY)
                    gridField(\.ny, range: Ranges.gridXY)
                    gridField(\.nz, range: Ranges.gridZ)
                }
            }
            Button("Исследование времени синтеза кадра…") {
                openWindow(id: ResearchView.windowID)
            }
        } header: {
            Text("Светящаяся среда и расчёт")
        }
    }

    private func gridField(_ keyPath: WritableKeyPath<GridSize, Int>, range: ClosedRange<Int>) -> some View {
        TextField("", value: Binding(get: { store.gridSize[keyPath: keyPath] },
                                     set: { store.gridSize[keyPath: keyPath] = $0.clamped(to: range) }),
                  format: .number.grouping(.never))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 48)
    }

    // MARK: - Источник света

    private var lightSection: some View {
        Section("Источник на бесконечности") {
            NumberField("Азимут φ_L, °", value: $store.light.azimuth, range: Ranges.lightAzimuth)
            NumberField("Высота θ_L, °", value: $store.light.elevation, range: Ranges.lightElevation)
            NumberField("Интенсивность I_L", value: $store.light.intensity, range: Ranges.unit)
            ColorField("Цвет C_L", color: $store.light.color)
        }
    }

    // MARK: - Поверхности

    private var surfaceSection: some View {
        Section {
            Picker("Поверхность", selection: $selectedSurface) {
                ForEach(store.surfaces) { surface in
                    Text(surface.name).tag(surface.id)
                }
            }
            let reflectance = $store.surfaces[selectedSurface].reflectance
            NumberField("Диффузное k_d", value: reflectance.kd, range: 0...(1 - reflectance.wrappedValue.ks))
            NumberField("Зеркальное k_s", value: reflectance.ks, range: 0...(1 - reflectance.wrappedValue.kd))
            NumberField("Блеск n", value: reflectance.n, range: Ranges.shininess, digits: 0)
        } header: {
            Text("Отражающие свойства")
        } footer: {
            Text("k_d + k_s ≤ 1. Начальные значения — из файла описания сцены.")
        }
    }

    // MARK: - Вид

    private var viewSection: some View {
        Section("Вид") {
            Toggle("Ландшафт", isOn: $store.showTerrain)
            Toggle("Объекты", isOn: $store.showObjects)
            Toggle("Анимация сияния", isOn: $store.animate)
            NumberField("Скорость анимации", value: $store.animationSpeed, range: 0...10)
        }
    }
}

/// Положение наблюдателя: поля показывают текущую камеру (в том числе после
/// управления мышью); ввод значения и Enter переносят камеру.
private struct ObserverSection: View {
    let store: ParameterStore
    @State private var draft = Observer.initial

    var body: some View {
        Section {
            NumberField("x_V", value: $draft.position.x, range: 0...Heightmap.extent)
            NumberField("y_V", value: $draft.position.y, range: 0...Heightmap.extent)
            NumberField("z_V", value: $draft.position.z, range: 0...200)
            NumberField("Азимут взгляда φ_V, °", value: $draft.azimuth, range: Ranges.viewAzimuth)
            NumberField("Угол места θ_V, °", value: $draft.elevation, range: Ranges.viewElevation)
            Button("Перенести наблюдателя") { store.applyObserver(draft) }
        } header: {
            Text("Наблюдатель")
        } footer: {
            Text("Мышь: перетаскивание — осмотр, колесо — приближение. z_V не опускается ниже рельефа.")
        }
        .onAppear { draft = store.observer }
        .onChange(of: store.observer) { _, observer in draft = observer }
        .onSubmit { store.applyObserver(draft) }
    }
}
