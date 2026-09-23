import Foundation
import CoreGraphics

public enum Rasterizer {
    public static func cgPath(_ p: VectorPath) -> CGPath {
        let m = CGMutablePath()
        for e in p.elements {
            switch e {
            case .move(let q): m.move(to: CGPoint(x: q.x, y: q.y))
            case .line(let q): m.addLine(to: CGPoint(x: q.x, y: q.y))
            case .cubic(let a, let b, let c):
                m.addCurve(to: CGPoint(x: c.x, y: c.y), control1: CGPoint(x: a.x, y: a.y), control2: CGPoint(x: b.x, y: b.y))
            case .close: m.closeSubpath()
            }
        }
        return m
    }

    /// Draws the visible layers into `ctx`, whose user space must already map document units
    /// with y pointing down.
    public static func draw(_ doc: VectorDocument, in ctx: CGContext) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        for layer in doc.visibleLayers where !layer.path.elements.isEmpty {
            let path = cgPath(layer.path)
            switch layer.fill {
            case .solid(let c):
                ctx.setFillColor(CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1))
                ctx.addPath(path)
                ctx.fillPath(using: .evenOdd)
            case .linear(let g):
                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip(using: .evenOdd)
                let colors = g.stops.map { CGColor(srgbRed: $0.color.r, green: $0.color.g, blue: $0.color.b, alpha: 1) }
                let locs = g.stops.map { CGFloat($0.offset) }
                if let grad = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs) {
                    ctx.drawLinearGradient(grad, start: CGPoint(x: g.start.x, y: g.start.y),
                                           end: CGPoint(x: g.end.x, y: g.end.y),
                                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                ctx.restoreGState()
            }
        }
    }

    /// Renders the document to a `width` × `height` bitmap. `background` nil = transparent.
    public static func render(_ doc: VectorDocument, width: Int, height: Int, background: RGB? = nil) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if let bg = background {
            ctx.setFillColor(CGColor(srgbRed: bg.r, green: bg.g, blue: bg.b, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(width) / doc.width, y: -CGFloat(height) / doc.height)
        ctx.interpolationQuality = .high
        draw(doc, in: ctx)
        return ctx.makeImage()!
    }
}

public enum Comparison {
    public struct Report: @unchecked Sendable {
        /// Mean absolute difference per channel, on a 0...255 scale, both images over white.
        public var meanError: Double
        /// Greyscale map of the error (white = identical), same size as the working image.
        public var heatmap: CGImage
    }

    public static func compare(_ doc: VectorDocument, to img: RGBAImage, gain: Float = 4) -> Report {
        let w = img.width, h = img.height
        let rendered = RGBAImage(cgImage: Rasterizer.render(doc, width: w, height: h))
        var total: Double = 0
        var heat = [UInt8](repeating: 255, count: w * h)
        for i in 0..<(w * h) {
            // composite both over white
            let a1 = img.a[i], a2 = rendered.a[i]
            let r1 = img.r[i] * a1 + (1 - a1), g1 = img.g[i] * a1 + (1 - a1), b1 = img.b[i] * a1 + (1 - a1)
            let r2 = rendered.r[i] * a2 + (1 - a2), g2 = rendered.g[i] * a2 + (1 - a2), b2 = rendered.b[i] * a2 + (1 - a2)
            let e = (abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)) / 3
            total += Double(e)
            heat[i] = UInt8(max(0, 255 - min(255, e * 255 * gain)))
        }
        let provider = CGDataProvider(data: Data(heat) as CFData)!
        let map = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                          provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return Report(meanError: total / Double(w * h) * 255, heatmap: map)
    }
}
