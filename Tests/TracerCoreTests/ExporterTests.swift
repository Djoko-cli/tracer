import Testing
import Foundation
import ImageIO
@testable import TracerCore

@Test func icoHasThreePngEntries() throws {
    let r = try Vectorizer.run(syntheticLogo(), Vectorizer.Settings(colors: 3))
    let imgs = [16, 32, 48].map { Exporter.squareIcon(r.document, size: $0) }
    let ico = Exporter.ico(imgs)
    #expect(ico[0] == 0 && ico[2] == 1 && ico[4] == 3)          // reserved, type = icon, count
    for (k, n) in [16, 32, 48].enumerated() { #expect(Int(ico[6 + 16 * k]) == n) }
    // first entry's data is a PNG
    let off = Int(ico[18]) | Int(ico[19]) << 8 | Int(ico[20]) << 16 | Int(ico[21]) << 24
    #expect(ico[off] == 0x89 && ico[off + 1] == 0x50)
}

@Test func faviconSetIsComplete() throws {
    let r = try Vectorizer.run(syntheticLogo(), Vectorizer.Settings(colors: 3))
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trace-fav-\(UUID().uuidString)")
    let files = try Exporter.favicons(r.document, to: dir, name: "test")
    #expect(Set(files) == ["favicon.svg", "favicon.ico", "favicon-16x16.png", "favicon-32x32.png",
                           "favicon-48x48.png", "favicon-96x96.png", "icon-192.png", "icon-512.png",
                           "apple-touch-icon.png", "icon-maskable-512.png", "site.webmanifest"])
    let src = CGImageSourceCreateWithURL(dir.appendingPathComponent("apple-touch-icon.png") as CFURL, nil)!
    let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    #expect(img.width == 180 && img.height == 180)
    try? FileManager.default.removeItem(at: dir)
}

@Test func pngExportHasTheRequestedLongSide() throws {
    let r = try Vectorizer.run(syntheticLogo(), Vectorizer.Settings(colors: 3))
    let data = Exporter.png(r.document, longSide: 1000)
    let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
    #expect(img.width == 1000 && img.height == 750)
}
