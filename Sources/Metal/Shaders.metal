#include <metal_stdlib>
using namespace metal;

struct TextVertex {
    float2 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
    float4 color [[attribute(2)]];
};

struct RasterizerData {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex RasterizerData terminal_vertex(TextVertex vertex [[stage_in]]) {
    RasterizerData output;
    output.position = float4(vertex.position, 0.0, 1.0);
    output.uv = vertex.uv;
    output.color = vertex.color;
    return output;
}

fragment float4 terminal_fragment(
    RasterizerData input [[stage_in]],
    texture2d<float> atlas [[texture(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float coverage = atlas.sample(linearSampler, input.uv).r;
    return float4(input.color.rgb, input.color.a * coverage);
}
