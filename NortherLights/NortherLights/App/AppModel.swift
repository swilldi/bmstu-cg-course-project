//
//  AppModel.swift
//  NortherLights
//
//  Загрузка сцены и связывание ParameterStore с рендером.
//

import Foundation
import Metal
import Observation

@Observable
final class AppModel {
    let store: ParameterStore
    let description: SceneDescription
    let heightmap: Heightmap
    let device: MTLDevice
    let renderer: SceneRenderer

    private init(store: ParameterStore, description: SceneDescription, heightmap: Heightmap,
                 device: MTLDevice, renderer: SceneRenderer) {
        self.store = store
        self.description = description
        self.heightmap = heightmap
        self.device = device
        self.renderer = renderer
    }

    enum LoadError: Error, CustomStringConvertible {
        case noMetal

        var description: String { "Нет устройства Metal" }
    }

    static func load() -> Result<AppModel, Error> {
        Result {
            guard let device = MTLCreateSystemDefaultDevice() else { throw LoadError.noMetal }
            let description = try SceneDescription.load()
            let heightmap = try loadHeightmap(description)
            let store = ParameterStore(scene: description)
            let graph = SceneGraph(description: description, heightmap: heightmap)
            let controller = try SceneController(graph: graph, device: device)
            let renderer = SceneRenderer(
                controller: controller,
                onObserverChange: { [weak store] observer in store?.observer = observer },
                onFrameTime: { [weak store] milliseconds in store?.frameTime = milliseconds }
            )
            return AppModel(store: store, description: description, heightmap: heightmap,
                            device: device, renderer: renderer)
        }
    }

    static func loadHeightmap(_ description: SceneDescription) throws -> Heightmap {
        let name = description.terrain.heightmap as NSString
        guard let url = Bundle.main.url(forResource: name.deletingPathExtension, withExtension: name.pathExtension) else {
            throw SceneDescription.LoadError.missingResource(description.terrain.heightmap)
        }
        return try Heightmap.load(url: url, maxHeight: description.terrain.maxHeight)
    }
}
