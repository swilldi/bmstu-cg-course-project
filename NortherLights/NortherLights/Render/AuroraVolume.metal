//
//  AuroraVolume.metal
//  NortherLights
//
//  Объёмный рендер сияния: трассировка луча в светящейся среде по расчётной сетке
//  с пошаговым интегрированием излучения и поглощения (формула (march) РПЗ):
//      I <- I + T * eps * rho * C * ds,   T <- T * exp(-kappa * rho * ds).
//  Шейдер назначен материалу ограничивающего параллелепипеда через SCNProgram:
//  SceneKit только передаёт матрицы и выполняет draw call.
//

#include <metal_stdlib>
using namespace metal;
// scn_metal использует типы Metal без префикса, поэтому подключается после using.
#include <SceneKit/scn_metal>

struct AuroraNodeBuffer {
    float4x4 modelTransform;
    float4x4 modelViewProjectionTransform;
};

// Раскладка совпадает с AuroraVolumeUniforms в AuroraVolume.swift.
struct AuroraVolumeUniforms {
    float4 domainMin;   // РПЗ
    float4 domainMax;   // РПЗ
    float4 gridSize;    // nx, ny, nz
    float  emission;    // eps
    float  absorption;  // kappa
    float  step;        // ds
    float  padding;
};

struct AuroraVertexIn {
    float3 position [[attribute(SCNVertexSemanticPosition)]];
};

struct AuroraVertexOut {
    float4 position [[position]];
    float3 worldPosition;
};

vertex AuroraVertexOut auroraVolumeVertex(AuroraVertexIn in [[stage_in]],
                                          constant AuroraNodeBuffer& scn_node [[buffer(1)]])
{
    AuroraVertexOut out;
    out.position = scn_node.modelViewProjectionTransform * float4(in.position, 1);
    out.worldPosition = (scn_node.modelTransform * float4(in.position, 1)).xyz;
    return out;
}

// Мировые координаты SceneKit (y вверх) -> РПЗ (z вверх); то же отображение, что в Axes.swift.
static float3 toRPZ(float3 p) {
    return float3(p.x, -p.z, p.y);
}

fragment float4 auroraVolumeFragment(AuroraVertexOut in [[stage_in]],
                                     constant SCNSceneBuffer& scn_frame [[buffer(0)]],
                                     constant AuroraVolumeUniforms& aurora [[buffer(2)]],
                                     texture3d<float> grid [[texture(0)]])
{
    constexpr sampler trilinear(filter::linear, address::clamp_to_zero, coord::normalized);

    // Луч P(s) = P_V + s D в координатах РПЗ.
    const float3 eye = toRPZ(scn_frame.inverseViewTransform[3].xyz);
    const float3 direction = normalize(toRPZ(in.worldPosition) - eye);

    // Пересечение с областью сетки (метод плит).
    const float3 inverse = 1.0f / direction;
    const float3 t0 = (aurora.domainMin.xyz - eye) * inverse;
    const float3 t1 = (aurora.domainMax.xyz - eye) * inverse;
    const float3 tNearAxis = min(t0, t1), tFarAxis = max(t0, t1);
    const float tNear = max(max(max(tNearAxis.x, tNearAxis.y), tNearAxis.z), 0.0f);
    const float tFar = min(min(tFarAxis.x, tFarAxis.y), tFarAxis.z);
    if (tFar <= tNear) {
        discard_fragment();
    }

    // Узел i лежит в центре текселя: tc = (t * (N - 1) + 0.5) / N.
    const float3 n = aurora.gridSize.xyz;
    const float3 extent = aurora.domainMax.xyz - aurora.domainMin.xyz;
    const float3 scale = (n - 1) / (extent * n);
    const float3 bias = 0.5f / n - aurora.domainMin.xyz * scale;

    // Сдвиг начала на долю шага убирает полосы от одинаковых положений выборок.
    const float jitter = fract(52.9829189f * fract(dot(in.position.xy, float2(0.06711056f, 0.00583715f))));
    const float ds = aurora.step;

    float3 radiance = 0;
    float transmittance = 1;
    for (float s = tNear + jitter * ds; s < tFar; s += ds) {
        const float3 p = eye + s * direction;
        const float4 cell = grid.sample(trilinear, p * scale + bias);  // (rho C, rho)
        radiance += transmittance * aurora.emission * cell.rgb * ds;
        transmittance *= exp(-aurora.absorption * cell.a * ds);
        if (transmittance < 0.003f) {
            break;
        }
    }
    // Предумноженная альфа: итог = I + I_фон * T.
    return float4(radiance, 1.0f - transmittance);
}
