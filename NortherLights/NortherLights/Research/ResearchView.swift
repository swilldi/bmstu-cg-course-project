//
//  ResearchView.swift
//  NortherLights
//
//  Окно исследования: два ряда замеров — по шагу интегрирования при максимальной
//  сетке и по размеру сетки при фиксированном шаге; результат выгружается в CSV.
//

import os
import SwiftUI
import UniformTypeIdentifiers

struct ResearchView: View {
    static let windowID = "research"

    let model: AppModel

    @State private var stepsText = "0,05; 0,1; 0,2; 0,4; 0,8; 1,6; 3,2; 5"
    @State private var stepGridText = "256×256×128"
    @State private var gridsText = "16×16×8; 32×32×16; 64×64×32; 128×128×64; 192×192×96; 256×256×128"
    @State private var gridStep: Float = 0.4
    @State private var frames = 30
    @State private var results: [ResearchMeasurement] = []
    @State private var total = 0
    @State private var running = false
    @State private var errorText: String?
    @State private var cancelFlag = OSAllocatedUnfairLock(initialState: false)
    @State private var exporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section("Ряд 1: шаг интегрирования Δs, у.е.") {
                    TextField("Значения Δs через «;»", text: $stepsText)
                    TextField("Сетка для ряда 1", text: $stepGridText)
                }
                Section("Ряд 2: размер расчётной сетки") {
                    TextField("Размеры Nx×Ny×Nz через «;»", text: $gridsText)
                    NumberField("Δs для ряда 2", value: $gridStep, range: Ranges.step)
                }
                Section {
                    IntegerField("Кадров на замер", value: $frames, range: 5...500)
                } footer: {
                    Text("Сцена фиксирована: 8 занавесов, неподвижное время, кадр \(Int(ResearchHarness.viewport.width))×\(Int(ResearchHarness.viewport.height)) вне экрана. Время кадра — от начала синтеза сетки до завершения рендера на GPU.")
                }
            }
            .formStyle(.grouped)
            .disabled(running)
            .frame(height: 330)

            HStack {
                Button(running ? "Идёт замер…" : "Запустить") { start() }
                    .disabled(running)
                Button("Остановить") { cancelFlag.withLock { $0 = true } }
                    .disabled(!running)
                if running {
                    ProgressView(value: Double(results.count), total: Double(max(total, 1)))
                        .frame(width: 160)
                }
                Spacer()
                Button("Сохранить CSV…") { exporting = true }
                    .disabled(results.isEmpty || running)
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }

            Table(results) {
                TableColumn("Δs") { Text($0.configuration.step.formatted()) }
                TableColumn("Сетка") { Text($0.configuration.grid.description) }
                TableColumn("Узлов") { Text($0.nodeCount.formatted()) }
                TableColumn("Кадр, мс") { Text($0.meanMilliseconds.formatted(.number.precision(.fractionLength(2)))) }
                TableColumn("Мин, мс") { Text($0.minMilliseconds.formatted(.number.precision(.fractionLength(2)))) }
                TableColumn("GPU, мс") { Text($0.gpuMilliseconds.formatted(.number.precision(.fractionLength(2)))) }
            }
        }
        .padding()
        .frame(minWidth: 720, minHeight: 620)
        .fileExporter(isPresented: $exporting, document: CSVDocument(rows: results), contentType: .commaSeparatedText,
                      defaultFilename: "frame-time.csv") { result in
            if case .failure(let error) = result { errorText = error.localizedDescription }
        }
    }

    private func start() {
        guard let steps = Self.parseSteps(stepsText), let stepGrid = Self.parseGrids(stepGridText)?.first,
              let grids = Self.parseGrids(gridsText) else {
            errorText = "Не удалось разобрать списки: Δs — числа через «;», сетки — в виде 128×128×64."
            return
        }
        let configurations = steps.map { ResearchConfiguration(step: $0.clamped(to: Ranges.step), grid: stepGrid) }
            + grids.map { ResearchConfiguration(step: gridStep, grid: $0) }
        errorText = nil
        results = []
        total = configurations.count
        running = true
        cancelFlag.withLock { $0 = false }

        let description = model.description, heightmap = model.heightmap, device = model.device
        let frames = frames, cancelFlag = cancelFlag
        Task.detached(priority: .userInitiated) {
            do {
                let harness = try ResearchHarness(description: description, heightmap: heightmap, device: device)
                harness.run(configurations, frames: frames,
                            isCancelled: { cancelFlag.withLock { $0 } },
                            progress: { measurement in
                                Task { @MainActor in results.append(measurement) }
                            })
                await MainActor.run { running = false }
            } catch {
                await MainActor.run {
                    errorText = String(describing: error)
                    running = false
                }
            }
        }
    }

    static func parseSteps(_ text: String) -> [Float]? {
        let values = text.split(separator: ";").map { Float($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }
    }

    /// Размеры вида «128×128×64» (допускается латинская x).
    static func parseGrids(_ text: String) -> [GridSize]? {
        let grids = text.split(separator: ";").map { item -> GridSize? in
            let parts = item.lowercased().split(whereSeparator: { $0 == "×" || $0 == "x" })
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 3 else { return nil }
            return GridSize(nx: parts[0], ny: parts[1], nz: parts[2]).clamped()
        }
        guard !grids.isEmpty, grids.allSatisfy({ $0 != nil }) else { return nil }
        return grids.compactMap { $0 }
    }
}

struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]

    var text: String

    init(rows: [ResearchMeasurement]) {
        text = ([ResearchMeasurement.csvHeader] + rows.map(\.csvRow)).joined(separator: "\n") + "\n"
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
