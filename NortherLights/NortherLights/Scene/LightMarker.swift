//
//  LightMarker.swift
//  NortherLights
//
//  Изображение источника на бесконечности на небе: диск с ореолом в направлении на
//  источник, цвета $C_L$ и яркости по $I_L$. Это декорация (не объект сцены и не
//  источник света): в освещении и тенях не участвует, геометрию строит SceneKit.
//

import AppKit
import SceneKit

nonisolated final class LightMarker {
    /// Расстояние от наблюдателя до диска: меньше `zFar` камеры, больше области сетки.
    static let distance: Float = 450
    /// Видимый угловой радиус диска, градусы (луна — около 0,25°; здесь крупнее для наглядности).
    static let angularRadius: Float = 1.2

    let node = SCNNode()
    private let disc: SCNMaterial
    private let halo: SCNMaterial
    /// Направление на источник в координатах SceneKit.
    private var direction = SIMD3<Float>(0, 1, 0)

    init() {
        let radius = CGFloat(Self.distance * tan(Self.angularRadius.radians))

        let discPlane = SCNPlane(width: 2 * radius, height: 2 * radius)
        discPlane.cornerRadius = radius
        disc = SCNMaterial()
        disc.lightingModel = .constant
        disc.isDoubleSided = true
        discPlane.materials = [disc]

        let haloPlane = SCNPlane(width: 10 * radius, height: 10 * radius)
        halo = SCNMaterial()
        halo.lightingModel = .constant
        halo.diffuse.contents = Self.haloImage()
        halo.blendMode = .add
        halo.writesToDepthBuffer = false
        halo.isDoubleSided = true
        haloPlane.materials = [halo]

        let discNode = SCNNode(geometry: discPlane)
        let haloNode = SCNNode(geometry: haloPlane)
        haloNode.renderingOrder = -1
        for child in [haloNode, discNode] {
            child.castsShadow = false
            node.addChildNode(child)
        }
        node.name = "light marker"
        node.castsShadow = false
        node.constraints = [SCNBillboardConstraint()]
        // Небо — раньше всей непрозрачной геометрии; рельеф и сияние рисуются поверх.
        node.renderingOrder = -10
    }

    func apply(_ light: LightParameters, visible: Bool) {
        direction = Axes.scene(light.direction)
        node.isHidden = !visible || light.intensity <= 0
        let color = NSColor(srgbRed: CGFloat(light.color.x), green: CGFloat(light.color.y),
                            blue: CGFloat(light.color.z), alpha: 1)
        // Диск светлее цвета источника, чтобы читался как светило, а не как пятно.
        disc.diffuse.contents = color.blended(withFraction: 0.55, of: .white) ?? color
        disc.transparency = CGFloat(0.35 + 0.65 * light.intensity)
        halo.multiply.contents = color
        halo.transparency = CGFloat(light.intensity)
    }

    /// Держит диск на постоянном расстоянии от наблюдателя: без параллакса,
    /// как у бесконечно удалённого источника.
    func follow(_ observer: SCNNode) {
        node.simdWorldPosition = observer.simdWorldPosition + direction * Self.distance
    }

    /// Радиальный градиент ореола: яркий центр, прозрачный край.
    private static func haloImage(size: Int = 256) -> CGImage? {
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [CGColor(gray: 1, alpha: 0.6), CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0.06),
                         CGColor(gray: 1, alpha: 0.015), CGColor(gray: 1, alpha: 0)] as CFArray,
                locations: [0, 0.18, 0.45, 0.75, 1]) else { return nil }
        let center = CGPoint(x: size / 2, y: size / 2)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: CGFloat(size) / 2, options: [])
        return context.makeImage()
    }
}
