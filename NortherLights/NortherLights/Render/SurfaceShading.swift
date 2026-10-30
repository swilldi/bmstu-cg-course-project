//
//  SurfaceShading.swift
//  NortherLights
//
//  Собственная модель освещения ландшафта и объектов. Подключается одинаково ко всем
//  материалам сцены, стандартная модель отражения SceneKit не используется:
//
//  1. Точка входа `lightingModel` — модель Блинна — Фонга без фоновой составляющей для
//     источника на бесконечности. SceneKit вызывает её по разу на каждый SCNLight; в сцене
//     он ровно один. Тень приходит множителем в `_light.intensity` — для этого у источника
//     выставлено `shadowMode = .forward` (см. SceneGraph.makeSunLight).
//  2. Точка входа `fragment` — подсветка сиянием: сумма по точечным источникам с
//     множителем видимости $S_j = 1$. Выполняется ровно один раз на фрагмент, поэтому сумма
//     не зависит от числа SCNLight. Источники — свой массив (текстура), не SCNLight:
//     SceneKit учитывает не более восьми источников на узел.
//

import Metal
import SceneKit

nonisolated enum SurfaceShading {
    /// $I = I_L C_L \circ (C_п k_d \max(0, N \cdot L) + k_s \max(0, N \cdot H)^n)$.
    /// Цвет поверхности $C_п$ SceneKit умножает на `diffuse` сам (`_surface.diffuse`),
    /// у `specular` материала цвет белый, поэтому блик — цвета источника.
    static let lightingModifier = """
    #pragma arguments
    float kd;
    float ks;
    float blinnExponent;

    #pragma body
    float3 N = _surface.normal;
    float3 L = _light.direction;
    float3 V = _surface.view;
    float NdotL = max(0.0, dot(N, L));
    float3 H = normalize(L + V);
    float NdotH = max(0.0, dot(N, H));
    float3 incoming = _light.intensity.rgb;  // I_L C_L, уже с учётом тени
    _lightingContribution.diffuse += incoming * (kd * NdotL);
    _lightingContribution.specular += incoming * (NdotL > 0.0 ? ks * pow(NdotH, blinnExponent) : 0.0);
    """

    /// $E(x) = \varepsilon \sum_j I_j C_j \max(0, N \cdot L_j) / |x - y_j|^2$;
    /// вклад в цвет — $C_п k_d E(x)$ (диффузное отражение свечения).
    /// Строка 0 текстуры — (y_j, I_j) в мировых координатах SceneKit, строка 1 — C_j.
    static let auroraGlowModifier = """
    #pragma arguments
    texture2d<float> auroraLights;
    float auroraLightCount;
    float auroraEmission;
    float glowKd;

    #pragma body
    float3 glow = float3(0.0);
    int count = int(auroraLightCount);
    for (int j = 0; j < count; ++j) {
        float4 source = auroraLights.read(uint2(j, 0));
        float3 color = auroraLights.read(uint2(j, 1)).rgb;
        float3 toSource = (scn_frame.viewTransform * float4(source.xyz, 1.0)).xyz - _surface.position;
        float distance2 = max(dot(toSource, toSource), 1.0);
        float NdotL = max(0.0, dot(_surface.normal, toSource * rsqrt(distance2)));
        glow += source.w * color * (NdotL / distance2);
    }
    _output.color.rgb += _surface.diffuse.rgb * (glowKd * auroraEmission) * glow;
    """

    /// Настраивает материал под собственную модель освещения.
    static func configure(_ material: SCNMaterial, color: SIMD3<Float>, reflectance: Reflectance) {
        material.lightingModel = .blinn
        material.diffuse.contents = NSColor(srgbRed: CGFloat(color.x), green: CGFloat(color.y),
                                            blue: CGFloat(color.z), alpha: 1)
        material.specular.contents = NSColor.white
        material.ambient.contents = NSColor.black
        material.shaderModifiers = [
            .lightingModel: lightingModifier,
            .fragment: auroraGlowModifier,
        ]
        apply(reflectance, to: material)
        material.setValue(NSNumber(value: Float(0)), forKey: "auroraLightCount")
        material.setValue(NSNumber(value: Float(0)), forKey: "auroraEmission")
    }

    /// Имена аргументов не совпадают со свойствами SCNMaterial (например, `shininess`):
    /// иначе `setValue(_:forKey:)` запишет встроенное свойство, а не аргумент шейдера.
    static func apply(_ reflectance: Reflectance, to material: SCNMaterial) {
        material.setValue(NSNumber(value: reflectance.kd), forKey: "kd")
        // Те же $k_d$ для подсветки сиянием; имя другое, чтобы аргументы двух точек входа не совпадали.
        material.setValue(NSNumber(value: reflectance.kd), forKey: "glowKd")
        material.setValue(NSNumber(value: reflectance.ks), forKey: "ks")
        material.setValue(NSNumber(value: reflectance.n), forKey: "blinnExponent")
    }

    static func apply(lights: SCNMaterialProperty, count: Int, emission: Float, to material: SCNMaterial) {
        material.setValue(lights, forKey: "auroraLights")
        material.setValue(NSNumber(value: Float(count)), forKey: "auroraLightCount")
        material.setValue(NSNumber(value: emission), forKey: "auroraEmission")
    }
}

/// Кольцо текстур с точечными источниками подсветки: CPU пишет в одну,
/// пока GPU читает предыдущие кадры.
nonisolated final class AuroraLightTable {
    private static let framesInFlight = 3
    private let textures: [MTLTexture]
    private let properties: [SCNMaterialProperty]
    private var index = 0

    init?(device: MTLDevice) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: AuroraLimits.maxLights, height: 2, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        var textures: [MTLTexture] = []
        for _ in 0..<Self.framesInFlight {
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            textures.append(texture)
        }
        self.textures = textures
        properties = textures.map { SCNMaterialProperty(contents: $0) }
    }

    /// Записывает источники (координаты РПЗ) и возвращает свойство материала с ними.
    func upload(_ lights: [AuroraLightSource]) -> SCNMaterialProperty {
        index = (index + 1) % Self.framesInFlight
        var texels = [SIMD4<Float>](repeating: .zero, count: AuroraLimits.maxLights * 2)
        for (j, light) in lights.prefix(AuroraLimits.maxLights).enumerated() {
            texels[j] = SIMD4(Axes.scene(light.position), light.intensity)
            texels[AuroraLimits.maxLights + j] = SIMD4(light.color, 1)
        }
        texels.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                textures[index].replace(region: MTLRegionMake2D(0, 0, AuroraLimits.maxLights, 2), mipmapLevel: 0,
                                        withBytes: base, bytesPerRow: AuroraLimits.maxLights * MemoryLayout<SIMD4<Float>>.stride)
            }
        }
        return properties[index]
    }
}
