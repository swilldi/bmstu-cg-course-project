//
//  SceneDescription.swift
//  NortherLights
//
//  Файл описания сцены: карта высот, состав, цвета и расстановка объектов,
//  начальные коэффициенты отражения ландшафта и каждого объекта.
//

import Foundation
import simd

nonisolated struct SceneDescription: Codable, Sendable {
    struct Terrain: Codable, Sendable {
        var heightmap: String
        var maxHeight: Float
        var color: SIMD3<Float>
        var reflectance: Reflectance
    }

    enum ObjectKind: String, Codable, Sendable {
        case house, tree, car
    }

    struct Object: Codable, Sendable {
        var name: String
        var kind: ObjectKind
        /// Положение основания в координатах РПЗ, у.е.
        var x: Float
        var y: Float
        /// Поворот вокруг вертикали, градусы.
        var rotation: Float
        var scale: Float
        /// Цвета частей объекта: основная часть, вторая часть (крыша / крона / колёса).
        var colors: [SIMD3<Float>]
        var reflectance: Reflectance
        /// Число сегментов при аппроксимации тел вращения многогранниками.
        var segments: Int?
    }

    var terrain: Terrain
    var objects: [Object]

    enum LoadError: Error, CustomStringConvertible {
        case missingResource(String)
        case tooFewObjects(Int)

        var description: String {
            switch self {
            case .missingResource(let name): "В бандле нет ресурса \(name)"
            case .tooFewObjects(let n): "В описании сцены \(n) объектов, по заданию нужно не меньше пяти"
            }
        }
    }

    static let minimumObjects = 5

    static func load(named name: String = "scene", bundle: Bundle = .main) throws -> SceneDescription {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw LoadError.missingResource("\(name).json")
        }
        let description = try JSONDecoder().decode(SceneDescription.self, from: Data(contentsOf: url))
        guard description.objects.count >= minimumObjects else {
            throw LoadError.tooFewObjects(description.objects.count)
        }
        return description
    }
}
