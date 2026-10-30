//
//  Heightmap.swift
//  NortherLights
//
//  Загрузка карты высот — отдельная функция, построение геометрии от неё не зависит.
//

import CoreGraphics
import Foundation
import ImageIO

/// Карта высот $H(x, y) \in [0; H_{\max}]$ над квадратом $[0;100]\times[0;100]$ у.е.
/// Строка 0 изображения соответствует $y = 100$ (север сверху, как на карте).
nonisolated struct Heightmap: Sendable {
    static let extent: Float = 100

    let width: Int
    let height: Int
    /// Высоты в у.е., построчно.
    let values: [Float]

    enum LoadError: Error, CustomStringConvertible {
        case unreadable(URL)

        var description: String {
            switch self {
            case .unreadable(let url): "Не удалось прочитать карту высот \(url.lastPathComponent)"
            }
        }
    }

    /// Читает полутоновое изображение (8 или 16 бит) и масштабирует яркость в $[0; H_{\max}]$.
    static func load(url: URL, maxHeight: Float) throws -> Heightmap {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LoadError.unreadable(url)
        }
        let width = image.width, height = image.height
        var pixels = [UInt16](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 16, bytesPerRow: width * 2,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw LoadError.unreadable(url) }
        let scale = maxHeight / Float(UInt16.max)
        return Heightmap(width: width, height: height, values: pixels.map { Float($0) * scale })
    }

    /// Высота узла $(i, j)$ изображения.
    func value(_ i: Int, _ j: Int) -> Float {
        values[j.clamped(to: 0...(height - 1)) * width + i.clamped(to: 0...(width - 1))]
    }

    /// Координаты РПЗ узла $(i, j)$.
    func position(_ i: Int, _ j: Int) -> SIMD3<Float> {
        SIMD3(Float(i) / Float(width - 1) * Self.extent,
              (1 - Float(j) / Float(height - 1)) * Self.extent,
              value(i, j))
    }

    /// Билинейная интерполяция $H(x, y)$ в координатах РПЗ.
    func height(x: Float, y: Float) -> Float {
        let fx = (x / Self.extent).clamped(to: 0...1) * Float(width - 1)
        let fy = (1 - (y / Self.extent).clamped(to: 0...1)) * Float(height - 1)
        let i = Int(fx), j = Int(fy)
        let tx = fx - Float(i), ty = fy - Float(j)
        let top = value(i, j) * (1 - tx) + value(i + 1, j) * tx
        let bottom = value(i, j + 1) * (1 - tx) + value(i + 1, j + 1) * tx
        return top * (1 - ty) + bottom * ty
    }
}
