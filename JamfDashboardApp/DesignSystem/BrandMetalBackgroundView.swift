import SwiftUI
#if canImport(MetalKit)
import MetalKit
import QuartzCore
#endif

/// Subtle animated Metal backdrop used for dashboard presentation polish.
struct BrandMetalBackgroundView: View {
    var body: some View {
#if canImport(MetalKit)
        if MTLCreateSystemDefaultDevice() != nil {
            BrandMetalBackgroundRepresentable()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
#else
        Color.clear
#endif
    }
}

#if canImport(MetalKit)
private struct BrandMetalUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var padding: Float = 0
}

private final class BrandMetalBackgroundRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let startTime = CACurrentMediaTime()

    init?(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
              let vertexFunction = library.makeFunction(name: "appMetalBackgroundVertex"),
              let fragmentFunction = library.makeFunction(name: "appMetalBackgroundFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        super.init()
    }

    /// Embedded Metal shader source to avoid requiring an external metal toolchain during builds.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct BrandMetalUniforms {
        float2 resolution;
        float time;
        float padding;
    };

    struct BrandMetalVertexOutput {
        float4 position [[position]];
        float2 uv;
    };

    vertex BrandMetalVertexOutput appMetalBackgroundVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };

        BrandMetalVertexOutput output;
        output.position = float4(positions[vertexID], 0.0, 1.0);
        output.uv = positions[vertexID] * 0.5 + 0.5;
        return output;
    }

    fragment float4 appMetalBackgroundFragment(
        BrandMetalVertexOutput input [[stage_in]],
        constant BrandMetalUniforms& uniforms [[buffer(0)]]
    ) {
        float2 uv = input.uv;
        float aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1.0);
        float2 p = (uv - 0.5) * float2(aspect, 1.0);

        float t = uniforms.time * 0.17;
        float waveA = sin((p.x * 2.4 + p.y * 1.7) * 3.0 + t);
        float waveB = cos((p.x * 1.5 - p.y * 2.2) * 4.1 - t * 1.3);

        float2 orbitCenter = float2(0.16 * sin(t * 0.9), -0.12 * cos(t * 0.7));
        float bloom = sin(length(p - orbitCenter) * 8.2 - t * 2.0);

        float mixValue = waveA * 0.48 + waveB * 0.34 + bloom * 0.18;
        mixValue = smoothstep(-0.9, 0.9, mixValue);

        float3 blue = float3(0.06, 0.28, 0.58);
        float3 aqua = float3(0.08, 0.52, 0.66);
        float3 green = float3(0.16, 0.54, 0.38);

        float3 color = mix(blue, aqua, mixValue);
        color = mix(color, green, 0.24 + 0.20 * sin(t + p.x * 2.2 - p.y * 1.0));

        float vignette = smoothstep(1.30, 0.18, length(p));
        float alpha = 0.25 * vignette;

        return float4(color * (0.78 + 0.22 * vignette), alpha);
    }
    """

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        _ = size
    }

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)

        var uniforms = BrandMetalUniforms(
            resolution: SIMD2<Float>(
                Float(max(view.drawableSize.width, 1)),
                Float(max(view.drawableSize.height, 1))
            ),
            time: Float(CACurrentMediaTime() - startTime)
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BrandMetalUniforms>.stride, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

private final class BrandMetalBackgroundCoordinator {
    let renderer: BrandMetalBackgroundRenderer?
    let view: MTKView

    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = BrandMetalBackgroundRenderer(device: device) else {
            self.renderer = nil
            self.view = MTKView(frame: .zero, device: nil)
            self.view.isPaused = true
            return
        }

        self.renderer = renderer
        self.view = MTKView(frame: .zero, device: device)
        self.view.delegate = renderer
        self.view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        self.view.colorPixelFormat = .bgra8Unorm
        self.view.framebufferOnly = true
        self.view.preferredFramesPerSecond = 30
        self.view.enableSetNeedsDisplay = false
        self.view.isPaused = false
#if canImport(UIKit)
        self.view.isOpaque = false
        self.view.backgroundColor = .clear
#elseif canImport(AppKit)
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.clear.cgColor
#endif
    }
}

#if canImport(UIKit)
private struct BrandMetalBackgroundRepresentable: UIViewRepresentable {
    func makeCoordinator() -> BrandMetalBackgroundCoordinator {
        BrandMetalBackgroundCoordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        context.coordinator.view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        _ = context
        _ = uiView
    }
}
#elseif canImport(AppKit)
private struct BrandMetalBackgroundRepresentable: NSViewRepresentable {
    func makeCoordinator() -> BrandMetalBackgroundCoordinator {
        BrandMetalBackgroundCoordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        context.coordinator.view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        _ = context
        _ = nsView
    }
}
#endif
#endif

//endofline
