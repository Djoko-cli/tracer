import Testing
import Foundation
@testable import TracerCore

private func circlePoly(_ c: Point, _ r: Double, n: Int = 400, noise: Double = 0) -> [Point] {
    var g = SystemRandomNumberGenerator()
    return (0..<n).map { i in
        let a = 2 * Double.pi * Double(i) / Double(n)
        let jitter = noise > 0 ? Double.random(in: -noise...noise, using: &g) : 0
        return c + Point(cos(a), sin(a)) * (r + jitter)
    }
}

private func maxDistanceToCurve(_ segs: [CurveFitter.Segment], _ pts: [Point]) -> Double {
    // dense sampling, then exact distance to the sampled polyline's segments
    var samples: [Point] = []
    for s in segs { for k in 0...200 { samples.append(CurveFitter.eval(s, Double(k) / 200)) } }
    func d(_ p: Point, _ a: Point, _ b: Point) -> Double {
        let ab = b - a, t = max(0, min(1, (p - a).dot(ab) / max(ab.dot(ab), 1e-12)))
        return distance(p, a + ab * t)
    }
    return pts.map { p in
        (0..<(samples.count - 1)).map { d(p, samples[$0], samples[$0 + 1]) }.min()!
    }.max()!
}

@Test func circleBecomesFourExactCubics() {
    let pts = circlePoly(Point(100, 80), 50, noise: 0.2)
    let segs = CurveFitter(tolerance: 1).fitClosed(pts)
    #expect(segs.count == 4)
    #expect(maxDistanceToCurve(segs, pts) < 0.5)
}

@Test func squareBecomesFourLines() {
    var pts: [Point] = []
    for i in 0..<100 { pts.append(Point(10 + Double(i), 10)) }
    for i in 0..<100 { pts.append(Point(110, 10 + Double(i))) }
    for i in 0..<100 { pts.append(Point(110 - Double(i), 110)) }
    for i in 0..<100 { pts.append(Point(10, 110 - Double(i))) }
    let segs = CurveFitter(tolerance: 1).fitClosed(pts)
    let lines = segs.filter { if case .line = $0 { return true } else { return false } }
    #expect(segs.count == 4)
    #expect(lines.count == 4)
    #expect(maxDistanceToCurve(segs, pts) < 0.5)
}

@Test func roundedRectangleMixesLinesAndCurves() {
    // 200 x 120 box with corner radius 20
    var pts: [Point] = []
    let r = 20.0, w = 200.0, h = 120.0
    func arc(_ c: Point, _ a0: Double) {
        for k in 0..<40 { let a = a0 + Double.pi / 2 * Double(k) / 40; pts.append(c + Point(cos(a), sin(a)) * r) }
    }
    for x in stride(from: r, to: w - r, by: 1) { pts.append(Point(x, 0)) }
    arc(Point(w - r, r), -Double.pi / 2)
    for y in stride(from: r, to: h - r, by: 1) { pts.append(Point(w, y)) }
    arc(Point(w - r, h - r), 0)
    for x in stride(from: w - r, to: r, by: -1) { pts.append(Point(x, h)) }
    arc(Point(r, h - r), Double.pi / 2)
    for y in stride(from: h - r, to: r, by: -1) { pts.append(Point(0, y)) }
    arc(Point(r, r), Double.pi)
    let segs = CurveFitter(tolerance: 0.5).fitClosed(pts)
    let lines = segs.filter { if case .line = $0 { return true } else { return false } }.count
    #expect(lines == 4)
    #expect(segs.count <= 12)
    #expect(maxDistanceToCurve(segs, pts) < 0.6)
}

@Test func fittedContourKeepsItsOrientation() {
    let ccw = circlePoly(Point(0, 0), 30)
    let cw = Array(ccw.reversed())
    func area(_ s: [CurveFitter.Segment]) -> Double {
        signedArea(s.flatMap { seg in (0..<20).map { CurveFitter.eval(seg, Double($0) / 20) } })
    }
    let f = CurveFitter(tolerance: 1)
    #expect(area(f.fitClosed(ccw)) * signedArea(ccw) > 0)
    #expect(area(f.fitClosed(cw)) * signedArea(cw) > 0)
}
