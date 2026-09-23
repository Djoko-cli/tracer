import Testing
@testable import TracerCore

private func square(_ n: Int, from a: Int, to b: Int, hole: (Int, Int)? = nil) -> Field {
    var f = Field(width: n, height: n)
    for y in a..<b { for x in a..<b { f[x, y] = 1 } }
    if let (ha, hb) = hole { for y in ha..<hb { for x in ha..<hb { f[x, y] = 0 } } }
    return f
}

@Test func filledSquareGivesOneLoopWithTheRightArea() {
    let loops = MarchingSquares.contours(square(20, from: 5, to: 15))
    #expect(loops.count == 1)
    // pixels 5..<15 cover [5, 15) in image coords; the 0.5 crossing sits on the pixel boundary,
    // except at the corners where the staircase is chamfered (4 half-pixel triangles).
    #expect(abs(abs(signedArea(loops[0])) - 99.5) < 0.01)
}

@Test func holeHasTheOppositeOrientation() {
    let loops = MarchingSquares.contours(square(30, from: 3, to: 27, hole: (10, 20)))
    #expect(loops.count == 2)
    let areas = loops.map(signedArea).sorted { abs($0) > abs($1) }
    #expect(areas[0] * areas[1] < 0)
}

@Test func twoDiagonalPixelsAreSeparateUnlessBridged() {
    var f = Field(width: 4, height: 4)
    f[1, 1] = 1; f[2, 2] = 1
    #expect(MarchingSquares.contours(f).count == 2)
}

@Test func blurKeepsTheEdgeOfAHalfPlaneInPlace() {
    var f = Field(width: 40, height: 10)
    for y in 0..<10 { for x in 0..<20 { f[x, y] = 1 } }
    let b = f.blurred(sigma: 1.0)
    // symmetric kernel: the 0.5 crossing stays between pixels 19 and 20
    #expect(abs(b[19, 5] + b[20, 5] - 1) < 1e-4)
}
