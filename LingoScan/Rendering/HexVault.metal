// Port de JPLights (app del propio autor), con intensidad global atenuada para LingoScan.
// Hex Vault: rejilla hexagonal que una luz suave recorre siguiendo el dedo (o sola, en autoplay),
// dejando una estela que fluye con la velocidad del gesto, ondas al tocar y un brillo que barre la rejilla.
//
// Pasadas por frame:
//   1. `vaultVelocityFragment`  (RG16F, baja resolución): campo de velocidad advectado + pintado por el pincel.
//   2. `vaultLightFragment`     (RG16F, baja resolución): x = luz de la estela, y = "calor"; se advecta con la
//                                velocidad y decae (calor más rápido).
//   3. `vaultCompositeFragment` (drawable): rejilla de hexágonos, aristas iluminadas, glow, pulsos, tonemap.
//      Variante clara (T-30): base casi blanca, rejilla algo más oscura que la base y la luz como veladura del
//      tono. `scheme.x` mezcla las dos variantes (el engine lo interpola ≤ 0,35 s al cambiar de apariencia).
// Todo en píxeles del drawable, con origen en el centro y y hacia abajo (como UIKit).

#include <metal_stdlib>
using namespace metal;

namespace vault {

struct TrailUniforms {
    float4 canvas;     // xy = drawable px · zw = tamaño de la textura de estela
    float4 segment;    // xy = desde · zw = hasta (px, centro = 0)
    float4 brush;      // xy = velocidad del pincel (px/s) · z = radio (px) · w = mezcla de velocidad
    float4 timing;     // x = dt · y = decaimiento de velocidad · z = deriva · w = energía de pintura
    float4 decay;      // xy = decaimiento (luz, calor) · z = radio de estela (px)
};

struct CompositeUniforms {
    float4 frame;      // xy = drawable px · z = tiempo del shimmer · w = reloj (s)
    float4 lens;       // xy = luz (px, centro = 0) · z = intensidad · w = radio (px)
    float4 shape;      // x = celda (px) · y = grosor base (px) · z = grosor encendido (px) · w = antialias (px)
    float4 look;       // x = rejilla · y = glow · z = radio de glow (px) · w = shimmer
    float4 look2;      // x = núcleo blanco · y = grano · z = velocidad de pulso (px/s) · w = intensidad global
    float4 colorA;     // lineal
    float4 colorB;     // lineal
    float4 background; // lineal
    float4 pulses[4];  // xy = origen (px) · z = reloj de inicio · w = fuerza (0 = libre)
    float4 scheme;     // x = claridad (0 oscuro … 1 claro) · y = sombra de la rejilla · z = veladura máx. del tono
    float4 lightBase;  // lineal: base de la variante clara
};

struct FSOut {
    float4 position [[position]];
    float2 uv;
};

static inline float segmentDistance(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

static inline float hash21(float2 p) {
    float3 q = fract(float3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

static inline float3 linearToSRGB(float3 c) {
    c = saturate(c);
    return select(1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, c * 12.92, c < float3(0.0031308));
}

constant float kHalfEdge = 0.28867513;   // media arista de un hexágono de apotema 0.5

} // namespace vault

using namespace vault;

vertex FSOut vaultFullscreenVertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid == 1) ? 3.0 : -1.0, (vid == 2) ? 3.0 : -1.0);
    FSOut out;
    out.position = float4(pos, 0.0, 1.0);
    out.uv = float2(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5);
    return out;
}

// MARK: - Estela

fragment float2 vaultVelocityFragment(FSOut in [[stage_in]],
                                      constant TrailUniforms &u [[buffer(0)]],
                                      texture2d<float> velocity [[texture(0)]],
                                      sampler s [[sampler(0)]]) {
    float2 canvas = u.canvas.xy;
    float2 p = in.uv * canvas - canvas * 0.5;
    float2 v = velocity.sample(s, in.uv).xy;
    float2 carried = velocity.sample(s, in.uv - v * u.timing.x / canvas).xy * u.timing.y;
    float d = segmentDistance(p, u.segment.xy, u.segment.zw) / u.brush.z;
    float w = exp(-d * d * d * d) * u.brush.w;
    return mix(carried, u.brush.xy, w);
}

fragment float2 vaultLightFragment(FSOut in [[stage_in]],
                                   constant TrailUniforms &u [[buffer(0)]],
                                   texture2d<float> velocity [[texture(0)]],
                                   texture2d<float> light [[texture(1)]],
                                   sampler s [[sampler(0)]]) {
    float2 canvas = u.canvas.xy;
    float2 p = in.uv * canvas - canvas * 0.5;
    float2 v = velocity.sample(s, in.uv).xy;
    float2 previous = light.sample(s, in.uv - v * u.timing.z * u.timing.x / canvas).xy * u.decay.xy;
    float d = segmentDistance(p, u.segment.xy, u.segment.zw) / u.decay.z;
    float paint = exp(-d * d) * u.timing.w;
    return max(previous, float2(paint));
}

// MARK: - Composición

fragment float4 vaultCompositeFragment(FSOut in [[stage_in]],
                                       constant CompositeUniforms &u [[buffer(0)]],
                                       texture2d<float> light [[texture(0)]],
                                       sampler s [[sampler(0)]]) {
    float2 res = u.frame.xy;
    float cell = u.shape.x;
    float aa = u.shape.w;
    float2 p = in.position.xy - res * 0.5;

    // Celda hexagonal más cercana (dos rejillas rectangulares desfasadas).
    float2 q = p.yx / cell;
    const float2 spacing = float2(1.0, 1.7320508);
    float4 cellIndex = floor(float4(q, q - float2(0.5, 1.0)) / spacing.xyxy) + 0.5;
    float4 local = float4(q - cellIndex.xy * spacing, q - (cellIndex.zw + 0.5) * spacing);
    bool first = dot(local.xy, local.xy) < dot(local.zw, local.zw);
    float2 offset = first ? local.xy : local.zw;
    float2 center = first ? cellIndex.xy * spacing : (cellIndex.zw + 0.5) * spacing;

    const float2 axes[3] = { float2(1.0, 0.0), float2(0.5, 0.8660254), float2(-0.5, 0.8660254) };
    float glowRadius = max(u.look.z, 0.5);

    float nearest = 1e9;
    float2 nearestMid = float2(0.0);
    float lineLit = 0.0, glowLit = 0.0, haloLit = 0.0, heatSum = 0.0, heatWeight = 1e-4;
    float pulseLine = 0.0, pulseGlow = 0.0, pulseHeat = 0.0;

    for (int e = 0; e < 6; e++) {
        float2 n = axes[e % 3] * (e < 3 ? 1.0 : -1.0);
        float2 t = float2(-n.y, n.x);
        float2 rel = offset - n * 0.5;
        float along = dot(rel, t);
        float across = dot(rel, n);
        float dist = length(float2(across, max(abs(along) - kHalfEdge, 0.0))) * cell;
        float2 mid = (center + n * 0.5).yx * cell;
        if (dist < nearest) { nearest = dist; nearestMid = mid; }

        float2 tangent = t.yx;
        float2 endA = mid - tangent * kHalfEdge * cell;
        float2 endB = mid + tangent * kHalfEdge * cell;
        float clampedAlong = clamp(along, -kHalfEdge, kHalfEdge) * cell;
        float falloff = exp(-dist / glowRadius);

        // Luz en este punto de la arista: estela (textura) o la lente que sigue al dedo.
        float2 at = mid + tangent * clampedAlong;
        float2 wake = light.sample(s, at / res + 0.5).xy;
        float2 lo = (at - u.lens.xy) / u.lens.w;
        float r2 = dot(lo, lo);
        float lens = (0.62 * exp(-r2 * 4.0) + 0.38 * exp(-r2 * 0.8)) * u.lens.z;
        float lit = max(wake.x, lens);
        float warm = max(wake.y, lens) * smoothstep(0.0, 0.3, lit);
        lit = pow(lit, 1.4);

        float width = mix(u.shape.y, u.shape.z, saturate(lit));
        float cover = 1.0 - smoothstep(width * 0.5 - aa, width * 0.5 + aa, dist);
        float edgeLine = cover * lit;
        float edgeGlow = falloff * lit;
        lineLit = max(lineLit, edgeLine);
        glowLit = max(glowLit, edgeGlow);
        haloLit = max(haloLit, exp(-dist / (glowRadius * 1.8)) * lit * warm * warm);
        heatSum += warm * (edgeLine + edgeGlow);
        heatWeight += edgeLine + edgeGlow;

        // Pulsos: un frente que avanza arista a arista desde el toque.
        float spark = 0.0, head = 0.0;
        for (int k = 0; k < 4; k++) {
            float4 pulse = u.pulses[k];
            float age = u.frame.w - pulse.z;
            if (pulse.w <= 0.0 || age < 0.0 || age > 7.0) continue;
            float da = length(endA - pulse.xy), db = length(endB - pulse.xy);
            float fromNear = da < db ? clampedAlong + kHalfEdge * cell : kHalfEdge * cell - clampedAlong;
            float jitter = (hash21(floor(mid * 0.25) + pulse.z) - 0.5) * 0.3 * cell;
            float front = age * u.look2.z - min(da, db) + jitter;
            float gap = fromNear - front;
            float fade = exp(-age * 0.55) * pulse.w;
            float headK = exp(-gap * gap / (0.018 * cell * cell)) * fade;
            float tailK = (gap < 0.0 ? exp(gap / (0.7 * cell)) : 0.0) * fade;
            spark += headK + tailK * 0.3;
            head = max(head, headK);
        }
        float pulseWidth = mix(u.shape.y, u.shape.z, saturate(spark));
        float pulseCover = 1.0 - smoothstep(pulseWidth * 0.5 - aa, pulseWidth * 0.5 + aa, dist);
        pulseLine = max(pulseLine, pulseCover * spark);
        pulseGlow = max(pulseGlow, falloff * spark);
        pulseHeat = max(pulseHeat, head * max(pulseCover, falloff));
    }

    float heat = heatSum / heatWeight;
    float baseLine = 1.0 - smoothstep(u.shape.y * 0.5 - aa, u.shape.y * 0.5 + aa, nearest);
    float sweep = 0.5 + 0.5 * sin(dot(nearestMid / cell, float2(0.21, 0.13)) - u.frame.z * 0.35);
    float shimmer = pow(sweep, 8.0) * u.look.w;

    float energy = clamp(lineLit + pulseLine, 0.0, 1.6);
    float glow = clamp(glowLit + pulseGlow, 0.0, 1.6);
    float hot = saturate(heat * 0.9 + pulseHeat);

    float3 colorA = u.colorA.rgb, colorB = u.colorB.rgb;
    float3 cool = mix(colorA, float3(dot(colorA, float3(0.2126, 0.7152, 0.0722))) * 1.6, 0.2);
    float3 lineColor = mix(cool, colorB, smoothstep(0.2, 0.75, hot));

    float3 latticeColor = mix(float3(0.62, 0.62, 0.70), colorA, 0.25);
    float3 emission = latticeColor * baseLine * u.look.x * (0.055 + 0.14 * shimmer);
    float white = smoothstep(0.55, 1.0, hot * min(energy, 1.0));
    float3 core = mix(lineColor, float3(1.0), u.look2.x * white);
    emission += core * energy * (1.3 + 1.1 * white);
    emission += lineColor * glow * u.look.y * 0.6;
    emission += mix(lineColor, colorB, 0.5) * haloLit * u.look.y * 0.12;

    float lightness = saturate(u.scheme.x);
    float3 color = float3(0.0);
    if (lightness < 1.0) {
        float3 dark = u.background.rgb + emission * u.look2.w;
        color = 1.0 - exp(-dark * 1.05);
    }
    if (lightness > 0.0) {
        // Claro: la rejilla oscurece la base (nunca la aclara) y la luz tiñe la base hacia el tono.
        float3 base = u.lightBase.rgb;
        float3 ink = mix(float3(0.40, 0.41, 0.48), colorA, 0.3);
        float shade = saturate(baseLine * u.scheme.y * (1.0 + 1.2 * shimmer));
        float3 paper = mix(base, base * ink, shade);
        float veil = saturate(energy * 0.55 + glow * u.look.y * 0.22 + haloLit * u.look.y * 0.1) * u.scheme.z;
        float3 veilColor = mix(colorA, colorA * 0.72, white);
        paper = mix(paper, veilColor, veil);
        color = mix(color, paper, lightness);
    }

    float2 fc = in.position.xy;
    float dither = (fract(52.9829189 * fract(dot(fc, float2(0.06711056, 0.00583715)))) - 0.5) / 255.0;
    float grain = (hash21(fc + fract(u.frame.z) * 91.0) - 0.5) * u.look2.y * 0.05;
    return float4(linearToSRGB(color) + dither + grain, 1.0);
}
