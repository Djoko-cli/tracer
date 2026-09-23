import Foundation

/// Iso-contours of a scalar field, as closed polylines in image coordinates
/// (pixel (i, j) has its centre at (i + 0.5, j + 0.5)).
///
/// Contours are oriented consistently: the inside (value >= iso) is always on the
/// right-hand side of the direction of travel, in y-down coordinates. Outer
/// boundaries and holes therefore come out with opposite signed areas.
public enum MarchingSquares {

    // Cell edges.
    private enum Edge: Int { case top = 0, right, bottom, left }

    // Nominal geometry of a unit cell (TL at origin, y down), used to orient segments.
    private static let corner: [Point] = [Point(0, 0), Point(1, 0), Point(1, 1), Point(0, 1)] // TL TR BR BL
    private static let edgeMid: [Point] = [Point(0.5, 0), Point(1, 0.5), Point(0.5, 1), Point(0, 0.5)]
    // The corner shared by two adjacent edges.
    private static func sharedCorner(_ a: Edge, _ b: Edge) -> Int? {
        let s = Set([a, b])
        if s == [.top, .left] { return 0 }
        if s == [.top, .right] { return 1 }
        if s == [.right, .bottom] { return 2 }
        if s == [.bottom, .left] { return 3 }
        return nil
    }

    /// Orient an unordered edge pair so that inside corners lie on the right.
    private static func orient(_ a: Edge, _ b: Edge, inside: [Bool]) -> (Edge, Edge) {
        let p = edgeMid[a.rawValue], q = edgeMid[b.rawValue]
        let d = q - p
        // pick a reference corner: the one cut off by the segment, or any corner otherwise
        let ref = sharedCorner(a, b) ?? (inside[0] != inside[3] ? 0 : 0)
        let c = corner[ref] - (p + q) / 2
        // right-hand normal in y-down coords is (-dy, dx)
        let onRight = c.dot(Point(-d.y, d.x)) > 0
        // the reference corner must be on the right iff it is inside
        return onRight == inside[ref] ? (a, b) : (b, a)
    }

    /// Unordered edge pairs per case, bits TL=8 TR=4 BR=2 BL=1. Saddles handled separately.
    private static let pairs: [[(Edge, Edge)]] = [
        [], [(.left, .bottom)], [(.bottom, .right)], [(.left, .right)],
        [(.top, .right)], [], [(.top, .bottom)], [(.left, .top)],
        [(.left, .top)], [(.top, .bottom)], [], [(.top, .right)],
        [(.left, .right)], [(.bottom, .right)], [(.left, .bottom)], [],
    ]

    public static func contours(_ field: Field, iso: Float = 0.5) -> [[Point]] {
        // pad with a ring of zeros so every contour closes
        let W = field.width + 2, H = field.height + 2
        var f = [Float](repeating: 0, count: W * H)
        for y in 0..<field.height {
            for x in 0..<field.width { f[(y + 1) * W + (x + 1)] = field.values[y * field.width + x] }
        }
        @inline(__always) func v(_ x: Int, _ y: Int) -> Float { f[y * W + x] }

        // edge keys: horizontal edge (x,y)-(x+1,y) -> 2*(y*W+x); vertical (x,y)-(x,y+1) -> 2*(y*W+x)+1
        @inline(__always) func key(_ cx: Int, _ cy: Int, _ e: Edge) -> Int {
            switch e {
            case .top: return 2 * (cy * W + cx)
            case .bottom: return 2 * ((cy + 1) * W + cx)
            case .left: return 2 * (cy * W + cx) + 1
            case .right: return 2 * (cy * W + cx + 1) + 1
            }
        }
        @inline(__always) func crossing(_ cx: Int, _ cy: Int, _ e: Edge) -> Point {
            let (ax, ay, bx, by): (Int, Int, Int, Int)
            switch e {
            case .top: (ax, ay, bx, by) = (cx, cy, cx + 1, cy)
            case .bottom: (ax, ay, bx, by) = (cx, cy + 1, cx + 1, cy + 1)
            case .left: (ax, ay, bx, by) = (cx, cy, cx, cy + 1)
            case .right: (ax, ay, bx, by) = (cx + 1, cy, cx + 1, cy + 1)
            }
            let fa = v(ax, ay), fb = v(bx, by)
            var t = fb != fa ? Double((iso - fa) / (fb - fa)) : 0.5
            t = min(max(t, 0), 1)
            // sample (i,j) of the padded grid has its pixel centre at (i - 0.5, j - 0.5)
            let x = Double(ax) + t * Double(bx - ax) - 0.5
            let y = Double(ay) + t * Double(by - ay) - 0.5
            return Point(x, y)
        }

        var next: [Int: Int] = [:]
        var point: [Int: Point] = [:]
        next.reserveCapacity(4096); point.reserveCapacity(4096)

        for cy in 0..<(H - 1) {
            for cx in 0..<(W - 1) {
                let tl = v(cx, cy) >= iso, tr = v(cx + 1, cy) >= iso
                let br = v(cx + 1, cy + 1) >= iso, bl = v(cx, cy + 1) >= iso
                let c = (tl ? 8 : 0) | (tr ? 4 : 0) | (br ? 2 : 0) | (bl ? 1 : 0)
                if c == 0 || c == 15 { continue }
                let inside = [tl, tr, br, bl]
                var segs: [(Edge, Edge)]
                if c == 5 || c == 10 {
                    let centre = (v(cx, cy) + v(cx + 1, cy) + v(cx + 1, cy + 1) + v(cx, cy + 1)) / 4
                    let joined = centre > iso           // inside corners connected through the centre (ties separate)
                    if c == 5 {                          // TR and BL inside
                        segs = joined ? [(.left, .top), (.bottom, .right)] : [(.top, .right), (.left, .bottom)]
                    } else {                             // TL and BR inside
                        segs = joined ? [(.top, .right), (.left, .bottom)] : [(.left, .top), (.bottom, .right)]
                    }
                } else {
                    segs = pairs[c]
                }
                for (a, b) in segs {
                    let (s, e) = orient(a, b, inside: inside)
                    let ks = key(cx, cy, s), ke = key(cx, cy, e)
                    next[ks] = ke
                    if point[ks] == nil { point[ks] = crossing(cx, cy, s) }
                    if point[ke] == nil { point[ke] = crossing(cx, cy, e) }
                }
            }
        }

        var loops: [[Point]] = []
        var visited = Set<Int>()
        visited.reserveCapacity(next.count)
        for start in next.keys where !visited.contains(start) {
            var loop: [Point] = []
            var k = start
            while !visited.contains(k) {
                visited.insert(k)
                if let p = point[k] { loop.append(p) }
                guard let n = next[k] else { break }
                k = n
            }
            if loop.count >= 3 { loops.append(loop) }
        }
        return loops
    }
}
