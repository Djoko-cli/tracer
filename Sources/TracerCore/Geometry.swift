import Foundation

public typealias Point = SIMD2<Double>

extension SIMD2 where Scalar == Double {
    @inlinable public var length: Double { (x * x + y * y).squareRoot() }
    @inlinable public var normalized: Point {
        let l = length
        return l > 1e-12 ? self / l : Point(1, 0)
    }
    @inlinable public func dot(_ o: Point) -> Double { x * o.x + y * o.y }
    @inlinable public func cross(_ o: Point) -> Double { x * o.y - y * o.x }
    /// perpendicular (rotated +90°)
    @inlinable public var perp: Point { Point(-y, x) }
}

@inlinable public func distance(_ a: Point, _ b: Point) -> Double { (a - b).length }

/// Signed area of a closed polygon (shoelace). Positive = counter-clockwise in y-up coordinates.
public func signedArea(_ p: [Point]) -> Double {
    guard p.count > 2 else { return 0 }
    var s = 0.0
    for i in 0..<p.count {
        let a = p[i], b = p[(i + 1) % p.count]
        s += a.x * b.y - b.x * a.y
    }
    return s / 2
}
