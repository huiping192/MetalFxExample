//
//  default.metal
//  metalfxsample
//
//  Created by 郭 輝平 on 2024/09/28.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
    const float4 vertices[] = {
        float4(-1, -1, 0, 1),
        float4( 1, -1, 0, 1),
        float4(-1,  1, 0, 1),
        float4( 1, -1, 0, 1),
        float4(-1,  1, 0, 1),
        float4( 1,  1, 0, 1)
    };
    
    const float2 texCoords[] = {
        float2(0, 1),
        float2(1, 1),
        float2(0, 0),
        float2(1, 1),
        float2(0, 0),
        float2(1, 0)
    };
    
    VertexOut out;
    out.position = vertices[vertexID];
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    return tex.sample(textureSampler, in.texCoord);
}
