import Testing
import Foundation
@testable import TracerCore

private func cubicCount(_ p: VectorPath) -> Int {
    p.elements.filter { if case .cubic = $0 { return true } else { return false } }.count
}
private func lineCount(_ p: VectorPath) -> Int {
    p.elements.filter { if case .line = $0 { return true } else { return false } }.count
}
private func subpaths(_ p: VectorPath) -> Int {
    p.elements.filter { if case .move = $0 { return true } else { return false } }.count
}

@Test func syntheticLogoBecomesThreeCleanLayers() throws {
    let r = try Vectorizer.run(syntheticLogo(), Vectorizer.Settings(colors: 3, precision: 1))
    let layers = r.document.layers
    #expect(layers.count == 3)
    // bottom: white background covering the canvas (a rectangle)
    #expect(subpaths(layers[0].path) == 1 && lineCount(layers[0].path) == 4)
    // disc: one exact circle, and it does not run under the square
    #expect(subpaths(layers[1].path) == 1 && cubicCount(layers[1].path) == 4)
    // square: four lines
    #expect(subpaths(layers[2].path) == 1 && lineCount(layers[2].path) == 4)
}

@Test func squareEdgesLandOnTheSubPixelBoundary() throws {
    // the square spans x 260.5 ... 360.5 in the source (bottom-left origin in CG, y flips)
    let r = try Vectorizer.run(syntheticLogo(), Vectorizer.Settings(colors: 3, precision: 0.5))
    let xs = r.document.layers[2].path.elements.compactMap { e -> Double? in
        switch e { case .move(let p), .line(let p): return p.x; default: return nil }
    }
    #expect(abs(xs.min()! - 260.5) < 0.15)
    #expect(abs(xs.max()! - 360.5) < 0.15)
}

@Test func svgIsWellFormed() throws {
    let r = try Vectorizer.run(syntheticLogo(), Vectorizer.Settings(colors: 3))
    let svg = SVGWriter.svg(r.document)
    let parser = XMLParser(data: Data(svg.utf8))
    #expect(parser.parse())
    #expect(svg.components(separatedBy: "<path ").count - 1 == 3)
}
