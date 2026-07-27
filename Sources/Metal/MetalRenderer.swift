import CoreText
import MetalKit
import SwiftUI

#if os(macOS)
import AppKit
typealias ViewRepresentable = NSViewRepresentable
#else
import UIKit
typealias ViewRepresentable = UIViewRepresentable
#endif

private struct TextVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
    var color: SIMD4<Float>
}

public final class MetalRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice?
    public let commandQueue: MTLCommandQueue?

    private let parser = ANSIParser()
    private var pipelineState: MTLRenderPipelineState?
    private var atlasTexture: MTLTexture?
    private var vertexBuffer: MTLBuffer?
    private var vertices: [TextVertex] = []
    private var terminalText = ""
    private var needsGeometry = true

    private let atlasSize = 1024
    private let fontSize: CGFloat = 16
    private let cellWidth: CGFloat = 12
    private let cellHeight: CGFloat = 22
    private let firstGlyph = 32
    private let lastGlyph = 126

    public override init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        super.init()
        guard let device else { return }
        atlasTexture = makeFontAtlas(device: device)
        pipelineState = makePipelineState(device: device)
    }

    public func configure(_ view: MTKView) {
        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.015, green: 0.025, blue: 0.02, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = true
        view.isPaused = true
    }

    public func update(text: String) {
        guard text != terminalText else { return }
        terminalText = text
        needsGeometry = true
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        needsGeometry = true
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        if needsGeometry { rebuildVertices(for: view.drawableSize) }
        if let pipelineState, let atlasTexture, let vertexBuffer, !vertices.isEmpty {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(atlasTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makePipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "terminal_vertex"),
              let fragmentFunction = library.makeFunction(name: "terminal_fragment") else { return nil }

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float4
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD2<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<TextVertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func makeFontAtlas(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: atlasSize, height: atlasSize, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let font = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
        var pixels = [UInt8](repeating: 0, count: atlasSize * atlasSize)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        pixels.withUnsafeMutableBytes { rawBuffer in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: atlasSize,
                height: atlasSize,
                bitsPerComponent: 8,
                bytesPerRow: atlasSize,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.setFillColor(gray: 1, alpha: 1)
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.translateBy(x: 0, y: CGFloat(atlasSize))
            context.scaleBy(x: 1, y: -1)

            let columns = Int(CGFloat(atlasSize) / cellWidth)
            for code in firstGlyph...lastGlyph {
                let glyphIndex = code - firstGlyph
                let cellX = CGFloat(glyphIndex % columns) * cellWidth
                let cellY = CGFloat(glyphIndex / columns) * cellHeight
                var character = UniChar(code)
                var glyph: CGGlyph = 0
                guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1), glyph != 0 else { continue }
                var position = CGPoint(x: cellX + 1, y: cellY + CTFontGetAscent(font))
                CTFontDrawGlyphs(font, &glyph, &position, 1, context)
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, atlasSize, atlasSize),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: atlasSize
        )
        return texture
    }

    private func rebuildVertices(for drawableSize: CGSize) {
        needsGeometry = false
        vertices.removeAll(keepingCapacity: true)
        guard drawableSize.width > 0, drawableSize.height > 0, let device else { return }

        var x: CGFloat = 12
        var y: CGFloat = 12
        let columns = Int(CGFloat(atlasSize) / cellWidth)
        let maximumY = drawableSize.height - cellHeight

        for segment in parser.parse(terminalText) {
            let color = colorVector(for: segment.foreground, bold: segment.isBold, dim: segment.isDim)
            for character in segment.text {
                if character == "\n" {
                    x = 12
                    y += cellHeight
                    continue
                }
                if character == "\r" { continue }
                if x + cellWidth > drawableSize.width {
                    x = 12
                    y += cellHeight
                }
                if y > maximumY { break }

                let scalar = character.unicodeScalars.first?.value ?? 63
                let code = (firstGlyph...lastGlyph).contains(Int(scalar)) ? Int(scalar) : 63
                let glyphIndex = code - firstGlyph
                let glyphX = CGFloat(glyphIndex % columns) * cellWidth
                let glyphY = CGFloat(glyphIndex / columns) * cellHeight
                appendQuad(
                    x: x, y: y, width: cellWidth, height: cellHeight,
                    u0: glyphX / CGFloat(atlasSize), v0: glyphY / CGFloat(atlasSize),
                    u1: (glyphX + cellWidth) / CGFloat(atlasSize), v1: (glyphY + cellHeight) / CGFloat(atlasSize),
                    color: color, drawableSize: drawableSize
                )
                x += cellWidth
            }
        }

        guard !vertices.isEmpty else { vertexBuffer = nil; return }
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<TextVertex>.stride * vertices.count,
            options: .storageModeShared
        )
    }

    private func appendQuad(
        x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
        u0: CGFloat, v0: CGFloat, u1: CGFloat, v1: CGFloat,
        color: SIMD4<Float>, drawableSize: CGSize
    ) {
        func clip(_ x: CGFloat, _ y: CGFloat) -> SIMD2<Float> {
            SIMD2(Float((x / drawableSize.width) * 2 - 1), Float(1 - (y / drawableSize.height) * 2))
        }
        let topLeft = clip(x, y)
        let topRight = clip(x + width, y)
        let bottomLeft = clip(x, y + height)
        let bottomRight = clip(x + width, y + height)
        let uvTopLeft = SIMD2<Float>(Float(u0), Float(v0))
        let uvTopRight = SIMD2<Float>(Float(u1), Float(v0))
        let uvBottomLeft = SIMD2<Float>(Float(u0), Float(v1))
        let uvBottomRight = SIMD2<Float>(Float(u1), Float(v1))
        vertices += [
            TextVertex(position: topLeft, uv: uvTopLeft, color: color),
            TextVertex(position: bottomLeft, uv: uvBottomLeft, color: color),
            TextVertex(position: topRight, uv: uvTopRight, color: color),
            TextVertex(position: topRight, uv: uvTopRight, color: color),
            TextVertex(position: bottomLeft, uv: uvBottomLeft, color: color),
            TextVertex(position: bottomRight, uv: uvBottomRight, color: color)
        ]
    }

    private func colorVector(for color: ANSIColor, bold: Bool, dim: Bool) -> SIMD4<Float> {
        var rgb: SIMD3<Float>
        switch color {
        case .default: rgb = SIMD3(0.45, 1.0, 0.62)
        case .ansi(let code): rgb = ansiRGB(code)
        case .indexed(let index): rgb = indexedRGB(index)
        case .rgb(let red, let green, let blue): rgb = SIMD3(Float(red) / 255, Float(green) / 255, Float(blue) / 255)
        }
        if bold {
            rgb = SIMD3(
                Swift.min(rgb.x * 1.15, 1),
                Swift.min(rgb.y * 1.15, 1),
                Swift.min(rgb.z * 1.15, 1)
            )
        }
        if dim { rgb *= 0.55 }
        return SIMD4(rgb.x, rgb.y, rgb.z, 1)
    }

    private func ansiRGB(_ code: Int) -> SIMD3<Float> {
        let palette: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(0.8, 0.18, 0.2), SIMD3(0.2, 0.8, 0.35), SIMD3(0.85, 0.75, 0.2),
            SIMD3(0.25, 0.5, 0.95), SIMD3(0.75, 0.3, 0.8), SIMD3(0.2, 0.75, 0.8), SIMD3(0.85, 0.85, 0.85),
            SIMD3(0.35, 0.35, 0.35), SIMD3(1, 0.35, 0.38), SIMD3(0.4, 1, 0.55), SIMD3(1, 0.9, 0.35),
            SIMD3(0.4, 0.65, 1), SIMD3(1, 0.45, 1), SIMD3(0.35, 1, 1), SIMD3(1, 1, 1)
        ]
        switch code {
        case 30...37: return palette[code - 30]
        case 90...97: return palette[code - 90 + 8]
        default: return SIMD3(0.45, 1, 0.62)
        }
    }

    private func indexedRGB(_ index: Int) -> SIMD3<Float> {
        if index < 16 { return ansiRGB(index < 8 ? index + 30 : index - 8 + 90) }
        if index >= 232 {
            let value = Float(index - 232) / 23
            return SIMD3(repeating: value)
        }
        let value = index - 16
        let levels: [Float] = [0, 0.37, 0.53, 0.68, 0.84, 1]
        return SIMD3(levels[value / 36], levels[(value / 6) % 6], levels[value % 6])
    }
}

#if os(macOS)
public struct MetalTerminalView: NSViewRepresentable {
    public let text: String
    private let renderer: MetalRenderer

    public init(text: String) { self.text = text; self.renderer = MetalRenderer() }

    public func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        renderer.configure(view)
        renderer.update(text: text)
        return view
    }

    public func updateNSView(_ view: MTKView, context: Context) {
        renderer.update(text: text)
        view.setNeedsDisplay(view.bounds)
    }
}
#else
public struct MetalTerminalView: UIViewRepresentable {
    public let text: String
    private let renderer: MetalRenderer

    public init(text: String) { self.text = text; self.renderer = MetalRenderer() }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        renderer.configure(view)
        renderer.update(text: text)
        return view
    }

    public func updateUIView(_ view: MTKView, context: Context) {
        renderer.update(text: text)
        view.setNeedsDisplay()
    }
}
#endif
