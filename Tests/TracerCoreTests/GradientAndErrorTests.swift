import Testing
import Foundation
import CoreGraphics
@testable import TracerCore

/// White canvas with a horizontal orange gradient bar.
func gradientBar(width: Int = 400, height: Int = 200) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 40, y: 50, width: 320, height: 100))
    let g = CGGradient(colorsSpace: space,
                       colors: [CGColor(srgbRed: 0.93, green: 0.30, blue: 0.0, alpha: 1),
                                CGColor(srgbRed: 1.0, green: 0.50, blue: 0.0, alpha: 1)] as CFArray,
                       locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 40, y: 100), end: CGPoint(x: 360, y: 100), options: [])
    ctx.restoreGState()
    return ctx.makeImage()!
}

@Test func gradientBarStaysOneLayerWithAHorizontalGradient() throws {
    // many clusters on purpose: the bands of the gradient must be merged back
    let r = try Vectorizer.run(gradientBar(), Vectorizer.Settings(colors: 8, precision: 1))
    #expect(r.document.layers.count == 2)
    guard case let .linear(g) = r.document.layers[1].fill else {
        Issue.record("expected a gradient fill"); return
    }
    let d = (g.end - g.start).normalized
    #expect(abs(d.y) < 0.05)                        // horizontal
    let left = g.start.x < g.end.x ? g.stops.first! : g.stops.last!
    #expect(abs(left.color.g - 0.30) < 0.05)        // darker orange on the left
}

@Test func renderedResultIsCloseToTheSource() throws {
    for (img, k) in [(syntheticLogo(), 3), (gradientBar(), 6)] {
        let r = try Vectorizer.run(img, Vectorizer.Settings(colors: k, precision: 0.8))
        let rep = Comparison.compare(r.document, to: r.working)
        #expect(rep.meanError < 1.5)
    }
}
