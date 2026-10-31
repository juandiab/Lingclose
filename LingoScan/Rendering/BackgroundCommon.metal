// Piezas comunes de los fondos: triángulo de pantalla completa y fundido al color de estudio (claro u oscuro) entre renderers.

#include <metal_stdlib>
using namespace metal;

struct BGFullscreenOut {
    float4 position [[position]];
    float2 uv;   // 0–1, origen arriba-izquierda (igual que las texturas Metal)
};

vertex BGFullscreenOut bgFullscreenVertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid == 1) ? 3.0 : -1.0, (vid == 2) ? 3.0 : -1.0);
    BGFullscreenOut out;
    out.position = float4(pos, 0.0, 1.0);
    out.uv = float2(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5);
    return out;
}

/// `color.rgb` = color de estudio de la variante (sRGB: el drawable es `bgra8Unorm`) · `color.a` = opacidad.
fragment float4 bgFadeFragment(BGFullscreenOut in [[stage_in]], constant float4 &color [[buffer(0)]]) {
    return color;
}
