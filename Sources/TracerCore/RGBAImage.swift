import Foundation
import CoreGraphics
import ImageIO

/// Straight-alpha sRGB image, planar, components in 0...1.
public struct RGBAImage: Sendable {
    public let width: Int
    public let height: Int
    public var r: [Float], g: [Float], b: [Float], a: [Float]

    public var count: Int { width * height }

    public init(width: Int, height: Int) {
        self.width = width; self.height = height
        let n = width * height
        r = .init(repeating: 0, count: n); g = r; b = r; a = r
    }

    /// Draws `image` into a `width` × `height` sRGB bitmap (high-quality resampling).
    public init(cgImage image: CGImage, width: Int? = nil, height: Int? = nil) {
        let w = width ?? image.width, h = height ?? image.height
        self.init(width: w, height: h)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        for i in 0..<(w * h) {
            let al = Float(bytes[4 * i + 3]) / 255
            a[i] = al
            if al > 0 {
                r[i] = min(1, Float(bytes[4 * i]) / 255 / al)
                g[i] = min(1, Float(bytes[4 * i + 1]) / 255 / al)
                b[i] = min(1, Float(bytes[4 * i + 2]) / 255 / al)
            }
        }
    }

    public static func load(url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
        else { throw TraceError.unreadableImage(url.lastPathComponent) }
        return img
    }

    /// Premultiplied RGBA8 bitmap of this image.
    public func cgImage() -> CGImage {
        var bytes = [UInt8](repeating: 0, count: count * 4)
        for i in 0..<count {
            let al = a[i]
            bytes[4 * i] = UInt8(max(0, min(255, (r[i] * al * 255).rounded())))
            bytes[4 * i + 1] = UInt8(max(0, min(255, (g[i] * al * 255).rounded())))
            bytes[4 * i + 2] = UInt8(max(0, min(255, (b[i] * al * 255).rounded())))
            bytes[4 * i + 3] = UInt8(max(0, min(255, (al * 255).rounded())))
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
}

public enum TraceError: Error, LocalizedError {
    case unreadableImage(String)
    case emptyImage
    public var errorDescription: String? {
        switch self {
        case .unreadableImage(let n): return "Impossible de lire l'image « \(n) »."
        case .emptyImage: return "L'image est vide ou entièrement transparente."
        }
    }
}
