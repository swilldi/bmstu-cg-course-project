//
//  AuroraGridFill.metal
//  NortherLights
//
//  Заполнение расчётной сетки по основаниям занавесов. Один поток — один узел сетки.
//  Плотность среды в узле: $\rho = b(u)\, e(u)\, \exp(-(d/\sigma)^2)\, f(s)$, где $u$ — координата
//  вдоль основания, $d$ — расстояние от основания поперёк слоя, $s$ — относительная высота.
//

#include <metal_stdlib>
using namespace metal;

// Раскладка совпадает с CurtainGPU / GridUniforms в AuroraSynthesizer.swift.
struct CurtainGPU {
    float4 placement;   // origin.xy, direction.xy
    float4 shape;       // length, hMin, hMax, thickness
    float4 colorLow;
    float4 colorMid;
    float4 colorHigh;
    uint4  sampling;    // sampleCount, sampleOffset
};

struct GridUniforms {
    float4 domainMin;
    float4 domainMax;
    uint4  size;        // nx, ny, nz, curtainCount
};

// Профиль по высоте и цвет третей — те же формулы, что в AuroraSynthesizer.VerticalProfile.
static float verticalDensity(float s) {
    return smoothstep(0.0f, 0.06f, s) * pow(1.0f - s, 1.5f);
}

static float3 heightColor(float s, constant CurtainGPU& c) {
    float3 color = mix(c.colorLow.rgb, c.colorMid.rgb, smoothstep(1.0f / 3 - 0.06f, 1.0f / 3 + 0.06f, s));
    return mix(color, c.colorHigh.rgb, smoothstep(2.0f / 3 - 0.06f, 2.0f / 3 + 0.06f, s));
}

static float endFade(float s) {
    return smoothstep(0.0f, 0.08f, s) * smoothstep(0.0f, 0.08f, 1.0f - s);
}

kernel void fillAuroraGrid(texture3d<half, access::write> grid [[texture(0)]],
                           constant GridUniforms& uniforms [[buffer(0)]],
                           constant CurtainGPU* curtains [[buffer(1)]],
                           const device float4* samples [[buffer(2)]],
                           uint3 gid [[thread_position_in_grid]])
{
    const uint3 size = uniforms.size.xyz;
    if (any(gid >= size)) {
        return;
    }
    // Координаты узла (РПЗ, z вверх).
    const float3 t = float3(gid) / float3(size - 1);
    const float3 p = mix(uniforms.domainMin.xyz, uniforms.domainMax.xyz, t);

    float3 radiance = 0;
    float density = 0;
    for (uint k = 0; k < uniforms.size.w; ++k) {
        constant CurtainGPU& c = curtains[k];
        const float length = c.shape.x, hMin = c.shape.y, hMax = c.shape.z, sigma = c.shape.w;

        const float s = (p.z - hMin) / (hMax - hMin);
        if (s <= 0 || s >= 1) {
            continue;
        }
        const float2 direction = c.placement.zw;
        const float2 rel = p.xy - c.placement.xy;
        const float u = dot(rel, direction);
        if (u <= 0 || u >= length) {
            continue;
        }
        const float lateral = dot(rel, float2(-direction.y, direction.x));

        // Линейная интерполяция основания между соседними точками.
        const uint n = c.sampling.x;
        const float fi = u / length * float(n - 1);
        const uint i0 = min(uint(fi), n - 2);
        const float4 base = mix(samples[c.sampling.y + i0], samples[c.sampling.y + i0 + 1], fi - float(i0));

        // Расстояние по нормали к основанию: смещение поперёк, делённое на $\sqrt{1 + w'^2}$.
        const float d = (lateral - base.x) * rsqrt(1.0f + base.y * base.y);
        const float across = exp(-(d * d) / (sigma * sigma));
        if (across < 1e-3f) {
            continue;
        }
        const float rho = base.z * endFade(u / length) * across * verticalDensity(s);
        radiance += rho * heightColor(s, c);
        density += rho;
    }
    grid.write(half4(half3(radiance), half(density)), gid);
}
