import Testing
import CoreGraphics
@testable import TracerCore

/// White canvas with an anti-aliased red disc and a blue square.
func syntheticLogo(width: Int = 400, height: Int = 300, transparentBackground: Bool = false) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if !transparentBackground {
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.2, blue: 0.1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 60, y: 70, width: 160, height: 160))
    ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.2, blue: 0.8, alpha: 1))
    ctx.fill(CGRect(x: 260.5, y: 90.5, width: 100, height: 120))
    return ctx.makeImage()!
}

@Test func kMeansFindsTwoObviousClusters() {
    let pts = (0..<200).map { i in i % 2 == 0 ? SIMD3<Float>(10, 0, 0) : SIMD3<Float>(90, 20, -30) }
    let c = KMeans.cluster(pts, k: 2).sorted { $0.x < $1.x }
    #expect(abs(c[0].x - 10) < 0.01 && abs(c[1].x - 90) < 0.01)
}

@Test func threeColourLogoSegmentsIntoThreeCleanRegions() {
    let img = RGBAImage(cgImage: syntheticLogo())
    let seg = Segmenter.segment(img, colors: 3, minRegion: 20)
    let areas = seg.areas().sorted()
    // square 100 x 120 = 12000, disc pi*80^2 ~ 20106, background the rest.
    // Labels are whole pixels, so each shape may gain or lose its half-covered edge ring
    // (perimeter / 2); sub-pixel accuracy is recovered later from the colour coverage.
    #expect(areas.count == 3)
    #expect(abs(areas[0] - 12000) <= 230)
    #expect(abs(areas[1] - 20106) <= 260)
}

@Test func transparentBackgroundIsNotAColour() {
    let img = RGBAImage(cgImage: syntheticLogo(transparentBackground: true))
    let seg = Segmenter.segment(img, colors: 2, minRegion: 20)
    #expect(seg.colorCount == 2)
    #expect(seg.labels.filter { $0 == Segmentation.transparent }.count > 80_000)
}
