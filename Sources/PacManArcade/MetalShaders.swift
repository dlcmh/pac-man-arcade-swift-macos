// swift-format-ignore-file
import Foundation

enum MetalShaderSource {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        packed_float2 position;
        packed_float4 color;
    };

    struct VertexOut {
        float4 position [[position]];
        float4 color;
    };

    struct Uniforms {
        float2 viewportSize;
        float2 scale;
        float2 offset;
    };

    vertex VertexOut vertex_main(const device VertexIn *vertices [[buffer(0)]],
                                 constant Uniforms &uniforms [[buffer(1)]],
                                 uint vertexID [[vertex_id]]) {
        VertexIn input = vertices[vertexID];
        float2 screenPosition = float2(input.position) * uniforms.scale + uniforms.offset;
        float2 ndc = float2((screenPosition.x / uniforms.viewportSize.x) * 2.0 - 1.0,
                            1.0 - (screenPosition.y / uniforms.viewportSize.y) * 2.0);

        VertexOut out;
        out.position = float4(ndc, 0.0, 1.0);
        out.color = float4(input.color);
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        return in.color;
    }
    """
}
