import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum Exporter {
    // MARK: PNG

    public static func pngData(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    /// Transparent PNG whose longest side is `longSide` pixels.
    public static func png(_ doc: VectorDocument, longSide: Int) -> Data {
        let k = Double(longSide) / max(doc.width, doc.height)
        let w = max(1, Int((doc.width * k).rounded())), h = max(1, Int((doc.height * k).rounded()))
        return pngData(Rasterizer.render(doc, width: w, height: h))
    }

    // MARK: square icons

    /// The document centred in a square of `size` px; `inset` = share of the side it occupies.
    public static func squareIcon(_ doc: VectorDocument, size: Int, inset: Double = 1, background: RGB? = nil) -> CGImage {
        // supersample, then downscale with high-quality filtering
        let big = max(size * 4, 256)
        let ctx = CGContext(data: nil, width: big, height: big, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if let bg = background {
            ctx.setFillColor(CGColor(srgbRed: bg.r, green: bg.g, blue: bg.b, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: big, height: big))
        }
        let side = max(doc.width, doc.height)
        let k = Double(big) * inset / side
        ctx.translateBy(x: 0, y: CGFloat(big))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: (Double(big) - doc.width * k) / 2, y: (Double(big) - doc.height * k) / 2)
        ctx.scaleBy(x: k, y: k)
        Rasterizer.draw(doc, in: ctx)
        let hi = ctx.makeImage()!
        let small = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        small.interpolationQuality = .high
        small.draw(hi, in: CGRect(x: 0, y: 0, width: size, height: size))
        return small.makeImage()!
    }

    /// ICO file with PNG-compressed entries (read by every current browser).
    public static func ico(_ images: [CGImage]) -> Data {
        let pngs = images.map(pngData)
        var d = Data()
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        u16(0); u16(1); u16(images.count)
        var offset = 6 + 16 * images.count
        for (img, png) in zip(images, pngs) {
            d.append(UInt8(img.width >= 256 ? 0 : img.width))
            d.append(UInt8(img.height >= 256 ? 0 : img.height))
            d.append(0); d.append(0)
            u16(1); u16(32)
            u32(png.count); u32(offset)
            offset += png.count
        }
        for png in pngs { d.append(png) }
        return d
    }

    /// Writes a complete favicon set into `folder` (created if needed). Returns the file names.
    @discardableResult
    public static func favicons(_ doc: VectorDocument, to folder: URL, name: String,
                                plate: RGB = RGB(1, 1, 1)) throws -> [String] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [String] = []
        func write(_ data: Data, _ file: String) throws {
            try data.write(to: folder.appendingPathComponent(file)); written.append(file)
        }
        try write(Data(SVGWriter.svg(doc, square: true).utf8), "favicon.svg")
        var small: [CGImage] = []
        for n in [16, 32, 48] {
            let img = squareIcon(doc, size: n)
            small.append(img)
            try write(pngData(img), "favicon-\(n)x\(n).png")
        }
        try write(ico(small), "favicon.ico")
        try write(pngData(squareIcon(doc, size: 96)), "favicon-96x96.png")
        try write(pngData(squareIcon(doc, size: 192)), "icon-192.png")
        try write(pngData(squareIcon(doc, size: 512)), "icon-512.png")
        // opaque tiles: iOS fills transparency with black, Android applies its own mask
        try write(pngData(squareIcon(doc, size: 180, inset: 0.84, background: plate)), "apple-touch-icon.png")
        try write(pngData(squareIcon(doc, size: 512, inset: 0.60, background: plate)), "icon-maskable-512.png")
        let manifest = """
        {
          "name": "\(name)",
          "short_name": "\(name)",
          "icons": [
            { "src": "icon-192.png", "sizes": "192x192", "type": "image/png" },
            { "src": "icon-512.png", "sizes": "512x512", "type": "image/png" },
            { "src": "icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
          ],
          "theme_color": "\(plate.hex)",
          "background_color": "\(plate.hex)",
          "display": "standalone"
        }

        """
        try write(Data(manifest.utf8), "site.webmanifest")
        return written
    }
}
