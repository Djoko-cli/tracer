import Foundation

/// Turns a closed polyline (e.g. a marching-squares contour) into a short sequence of
/// straight lines and cubic Béziers within a distance tolerance.
///
/// Pipeline: uniform resampling → exact circle test → corner detection → per piece,
/// straight runs become lines and the rest is fitted with Schneider's algorithm.
public struct CurveFitter: Sendable {
    /// Maximum distance between the polyline and the fitted curve, in the polyline's units.
    public var tolerance: Double = 1.0
    /// A turn sharper than this (degrees) over `cornerWindow` is a corner.
    public var cornerAngle: Double = 40
    /// Radius of curvature above which a run counts as straight.
    public var straightRadius: Double = 300
    /// Minimum length of a straight run to be emitted as a line.
    public var minLineLength: Double = 10
    /// Resampling step of the input polyline.
    public var step: Double = 0.5
    /// Tiny segments (total length below this) between two lines are replaced by the lines'
    /// intersection. `nil` = 2.5 × tolerance, at least 2.
    public var cornerSnap: Double? = nil
    /// Length over which the turning angle is measured to find corners.
    public var cornerWindow: Double = 2.5

    public init(tolerance: Double = 1.0) { self.tolerance = tolerance }

    public enum Segment: Sendable {
        case line(Point, Point)
        case cubic(Point, Point, Point, Point)
        var start: Point { switch self { case .line(let a, _): return a; case .cubic(let a, _, _, _): return a } }
        var end: Point { switch self { case .line(_, let b): return b; case .cubic(_, _, _, let d): return d } }
    }

    // MARK: - public entry points

    /// Fit one closed contour; the result keeps the input's orientation.
    public func fitClosed(_ input: [Point]) -> [Segment] {
        var poly = input
        if poly.count > 1, distance(poly[0], poly[poly.count - 1]) < 1e-9 { poly.removeLast() }
        guard poly.count >= 3 else { return [] }
        let P = Self.resampleClosed(poly, step: step)
        guard P.count >= 8 else { return Self.polygon(poly) }

        if let c = circle(P) { return c }

        let n = P.count
        let corners = detectCorners(P)
        // pieces between consecutive cut points; with no corner, cut a smooth loop in 4
        var cuts = corners
        var hard = Set(corners)
        if cuts.isEmpty {
            cuts = [0, n / 4, n / 2, (3 * n) / 4]
            hard = []
        }
        var out: [Segment] = []
        for (i, a) in cuts.enumerated() {
            let b = cuts[(i + 1) % cuts.count]
            let piece = Self.slice(P, from: a, to: b)
            guard piece.count >= 2 else { continue }
            let tStart = hard.contains(a) ? Self.chordTangent(piece, atStart: true) : Self.centralTangent(P, a)
            let tEndBack = hard.contains(b) ? Self.chordTangent(piece, atStart: false) : -Self.centralTangent(P, b)
            out += fitPiece(piece, tStart: tStart, tEndBack: tEndBack)
        }
        let sharp = Self.sharpenCorners(Self.stitch(out), snap: cornerSnap ?? max(2.0, 2.5 * tolerance))
        return Self.mergeCollinearLines(sharp, tolerance: tolerance)
    }

    // MARK: - pieces

    private func fitPiece(_ piece: [Point], tStart: Point, tEndBack: Point) -> [Segment] {
        if piece.count < 3 { return [.line(piece[0], piece[piece.count - 1])] }
        let runs = straightRuns(piece)
        if runs.isEmpty { return bezierOrLine(piece, tStart, tEndBack) }

        var out: [Segment] = []
        var cursor = 0
        var tCursor = tStart
        for (a, b) in runs {
            let (A, B, d) = Self.fitLine(Array(piece[a...b]))
            if a > cursor {
                let span = Array(piece[cursor...a].dropLast()) + [A]
                out += bezierOrLine(span, tCursor, -d)
            } else if cursor == 0 {
                // run starts at the piece start: keep the piece's own start point
            }
            let start = (a == 0) ? piece[0] : A
            let end = (b == piece.count - 1) ? piece[piece.count - 1] : B
            out.append(.line(start, end))
            cursor = b
            tCursor = d
        }
        if cursor < piece.count - 1 {
            let last = out.last!.end
            let span = [last] + Array(piece[(cursor + 1)...])
            out += bezierOrLine(span, tCursor, tEndBack)
        }
        return out
    }

    private func bezierOrLine(_ pts: [Point], _ t1: Point, _ t2: Point) -> [Segment] {
        guard pts.count >= 2 else { return [] }
        if pts.count == 2 || Self.deviationFromChord(pts) <= tolerance * 0.5 {
            return [.line(pts[0], pts[pts.count - 1])]
        }
        return Self.fitCubic(pts, t1, t2, tolerance, depth: 0).map { c in
            Self.lineIfStraight(c, tol: tolerance * 0.25)
        }
    }

    // MARK: - circle

    private func circle(_ P: [Point]) -> [Segment]? {
        // algebraic least-squares circle fit: x² + y² = a x + b y + c
        var sxx = 0.0, sxy = 0.0, syy = 0.0, sx = 0.0, sy = 0.0, sz = 0.0, sxz = 0.0, syz = 0.0
        let n = Double(P.count)
        for p in P {
            let z = p.x * p.x + p.y * p.y
            sxx += p.x * p.x; sxy += p.x * p.y; syy += p.y * p.y
            sx += p.x; sy += p.y; sz += z; sxz += p.x * z; syz += p.y * z
        }
        // normal equations [[sxx sxy sx][sxy syy sy][sx sy n]] [a b c] = [sxz syz sz]
        guard let s = Self.solve3([[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, n]], [sxz, syz, sz]) else { return nil }
        let cx = s[0] / 2, cy = s[1] / 2
        let r2 = s[2] + cx * cx + cy * cy
        guard r2 > 0 else { return nil }
        let r = r2.squareRoot()
        let c = Point(cx, cy)
        var dev = 0.0
        for p in P { dev = max(dev, abs(distance(p, c) - r)) }
        guard r > 3, dev < max(0.5, tolerance * 0.75) else { return nil }
        // the contour must actually go all the way round
        let area = abs(signedArea(P))
        guard abs(area - Double.pi * r * r) < 0.03 * Double.pi * r * r else { return nil }
        return Self.circleCubics(center: c, radius: r, positive: signedArea(P) > 0, startNear: P[0])
    }

    static func circleCubics(center c: Point, radius r: Double, positive: Bool, startNear p0: Point) -> [Segment] {
        let k = 0.5522847498307936 * r
        // four quadrant points in the travel direction; signedArea > 0 means +angle direction
        let dirs: [Point] = positive
            ? [Point(1, 0), Point(0, 1), Point(-1, 0), Point(0, -1)]
            : [Point(1, 0), Point(0, -1), Point(-1, 0), Point(0, 1)]
        // start at the quadrant point closest to the original start, to keep it stable
        let startIdx = (0..<4).min { distance(c + dirs[$0] * r, p0) < distance(c + dirs[$1] * r, p0) } ?? 0
        var out: [Segment] = []
        for i in 0..<4 {
            let d0 = dirs[(startIdx + i) % 4], d1 = dirs[(startIdx + i + 1) % 4]
            let a = c + d0 * r, b = c + d1 * r
            out.append(.cubic(a, a + d1 * k, b + d0 * k, b))
        }
        return out
    }

    // MARK: - corners and straight runs

    private func detectCorners(_ P: [Point]) -> [Int] {
        let n = P.count
        let w = max(2, Int((cornerWindow / step).rounded()))
        guard n > 2 * w + 2 else { return [] }
        let limit = cornerAngle * Double.pi / 180
        var turn = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let a = P[(i - w + n) % n], b = P[i], c = P[(i + w) % n]
            let u = (b - a).normalized, v = (c - b).normalized
            turn[i] = acos(min(1, max(-1, u.dot(v))))
        }
        var out: [Int] = []
        for i in 0..<n where turn[i] > limit {
            var isMax = true
            for j in -w...w where j != 0 {
                let t = turn[(i + j + n) % n]
                if t > turn[i] || (t == turn[i] && j < 0) { isMax = false; break }
            }
            if isMax { out.append(i) }
        }
        return out
    }

    private func straightRuns(_ P: [Point]) -> [(Int, Int)] {
        let n = P.count
        let w = max(2, Int((2.0 / step).rounded()))
        guard n > 2 * w + 1 else { return [] }
        var flat = [Bool](repeating: false, count: n)
        for i in w..<(n - w) {
            let a = P[i - w], b = P[i], c = P[i + w]
            let u = b - a, v = c - b
            let ang = acos(min(1, max(-1, u.normalized.dot(v.normalized))))
            let arc = (u.length + v.length) / 2
            flat[i] = arc > 1e-9 && ang / arc < 1 / straightRadius
        }
        var runs: [(Int, Int)] = []
        var i = 0
        let minPts = Int((minLineLength / step).rounded(.up))
        while i < n {
            guard flat[i] else { i += 1; continue }
            var j = i
            while j + 1 < n && flat[j + 1] { j += 1 }
            var a = max(0, i - w), b = min(n - 1, j + w)
            if b - a >= minPts {
                while b > a && Self.deviationFromChord(Array(P[a...b])) > tolerance * 0.5 { b -= 1 }
                while b > a && Self.deviationFromChord(Array(P[a...b])) > tolerance * 0.5 { a += 1 }
                if b - a >= minPts { runs.append((a, b)) }
            }
            i = j + 1
        }
        return runs
    }

    // MARK: - Schneider

    static func fitCubic(_ P: [Point], _ t1: Point, _ t2: Point, _ tol: Double, depth: Int) -> [Segment] {
        let first = P[0], last = P[P.count - 1]
        if P.count < 3 {
            let d = distance(first, last) / 3
            return [.cubic(first, first + t1 * d, last + t2 * d, last)]
        }
        var u = chordParam(P)
        var B = generateBezier(P, u, t1, t2)
        var (err, split) = maxError(P, u, B)
        if err < tol { return [B] }
        for _ in 0..<12 {
            let u2 = reparameterize(P, u, B)
            let B2 = generateBezier(P, u2, t1, t2)
            let (e2, s2) = maxError(P, u2, B2)
            if e2 < tol { return [B2] }
            if e2 >= err - 1e-9 { break }
            u = u2; B = B2; err = e2; split = s2
        }
        if depth > 32 {
            let d = distance(first, last) / 3
            return [.cubic(first, first + t1 * d, last + t2 * d, last)]
        }
        if split <= 0 || split >= P.count - 1 { split = P.count / 2 }
        let tc = (P[split + 1] - P[split - 1]).normalized
        return fitCubic(Array(P[0...split]), t1, -tc, tol, depth: depth + 1)
             + fitCubic(Array(P[split...]), tc, t2, tol, depth: depth + 1)
    }

    static func chordParam(_ P: [Point]) -> [Double] {
        var u = [Double](repeating: 0, count: P.count)
        for i in 1..<P.count { u[i] = u[i - 1] + distance(P[i], P[i - 1]) }
        let total = u[u.count - 1]
        guard total > 0 else { return (0..<P.count).map { Double($0) / Double(P.count - 1) } }
        return u.map { $0 / total }
    }

    static func generateBezier(_ P: [Point], _ u: [Double], _ t1: Point, _ t2: Point) -> Segment {
        let p0 = P[0], p3 = P[P.count - 1]
        var c00 = 0.0, c01 = 0.0, c11 = 0.0, x0 = 0.0, x1 = 0.0
        for i in 0..<P.count {
            let t = u[i], mt = 1 - t
            let b0 = mt * mt * mt, b1 = 3 * mt * mt * t, b2 = 3 * mt * t * t, b3 = t * t * t
            let a0 = t1 * b1, a1 = t2 * b2
            c00 += a0.dot(a0); c01 += a0.dot(a1); c11 += a1.dot(a1)
            let tmp = P[i] - (p0 * (b0 + b1) + p3 * (b2 + b3))
            x0 += a0.dot(tmp); x1 += a1.dot(tmp)
        }
        let det = c00 * c11 - c01 * c01
        let seg = distance(p0, p3)
        var alpha1 = seg / 3, alpha2 = seg / 3
        if abs(det) > 1e-12 {
            let a1 = (x0 * c11 - x1 * c01) / det
            let a2 = (c00 * x1 - c01 * x0) / det
            if a1 > 1e-6 * seg && a2 > 1e-6 * seg { alpha1 = a1; alpha2 = a2 }
        }
        return .cubic(p0, p0 + t1 * alpha1, p3 + t2 * alpha2, p3)
    }

    static func eval(_ s: Segment, _ t: Double) -> Point {
        switch s {
        case .line(let a, let b): return a + (b - a) * t
        case .cubic(let p0, let p1, let p2, let p3):
            let mt = 1 - t
            return p0 * (mt * mt * mt) + p1 * (3 * mt * mt * t) + p2 * (3 * mt * t * t) + p3 * (t * t * t)
        }
    }

    static func maxError(_ P: [Point], _ u: [Double], _ B: Segment) -> (Double, Int) {
        var best = 0.0, idx = P.count / 2
        for i in 1..<(P.count - 1) {
            let d = distance(eval(B, u[i]), P[i])
            if d > best { best = d; idx = i }
        }
        return (best, idx)
    }

    static func reparameterize(_ P: [Point], _ u: [Double], _ B: Segment) -> [Double] {
        guard case let .cubic(p0, p1, p2, p3) = B else { return u }
        let d1 = (p1 - p0) * 3, d2 = (p2 - p1) * 3, d3 = (p3 - p2) * 3
        let dd1 = (d2 - d1) * 2, dd2 = (d3 - d2) * 2
        return (0..<P.count).map { i in
            let t = u[i], mt = 1 - t
            let q = eval(B, t)
            let qp = d1 * (mt * mt) + d2 * (2 * mt * t) + d3 * (t * t)
            let qpp = dd1 * mt + dd2 * t
            let num = (q - P[i]).dot(qp)
            let den = qp.dot(qp) + (q - P[i]).dot(qpp)
            guard abs(den) > 1e-12 else { return t }
            return min(1, max(0, t - num / den))
        }
    }

    // MARK: - helpers

    static func lineIfStraight(_ s: Segment, tol: Double) -> Segment {
        guard case let .cubic(p0, p1, p2, p3) = s else { return s }
        let ch = p3 - p0, L = ch.length
        guard L > 1e-9 else { return s }
        let u = ch / L, nrm = u.perp
        let d1 = abs((p1 - p0).dot(nrm)), d2 = abs((p2 - p0).dot(nrm))
        let a1 = (p1 - p0).dot(u), a2 = (p2 - p0).dot(u)
        if d1 < tol && d2 < tol && a1 >= -0.05 * L && a1 <= 1.05 * L && a2 >= -0.05 * L && a2 <= 1.05 * L {
            return .line(p0, p3)
        }
        return s
    }

    static func deviationFromChord(_ P: [Point]) -> Double {
        guard P.count > 2 else { return 0 }
        let a = P[0], b = P[P.count - 1]
        let v = b - a, L = v.length
        if L < 1e-9 { return P.map { distance($0, a) }.max() ?? 0 }
        let nrm = (v / L).perp
        return P.map { abs(($0 - a).dot(nrm)) }.max() ?? 0
    }

    /// Total-least-squares line through the points, snapped to horizontal/vertical when within 1.5°.
    static func fitLine(_ P: [Point]) -> (Point, Point, Point) {
        let c = P.reduce(Point.zero, +) / Double(P.count)
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for p in P { let d = p - c; sxx += d.x * d.x; sxy += d.x * d.y; syy += d.y * d.y }
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        var d = Point(cos(theta), sin(theta))
        let deg = theta * 180 / .pi
        for target in [-180.0, -90, 0, 90, 180] where abs(deg - target) < 1.5 {
            let r = target * .pi / 180; d = Point(cos(r), sin(r))
        }
        // orient along travel
        if (P[P.count - 1] - P[0]).dot(d) < 0 { d = -d }
        let A = c + d * (P[0] - c).dot(d)
        let B = c + d * (P[P.count - 1] - c).dot(d)
        return (A, B, d)
    }

    static func centralTangent(_ P: [Point], _ i: Int) -> Point {
        let n = P.count
        return (P[(i + 1) % n] - P[(i - 1 + n) % n]).normalized
    }

    static func chordTangent(_ piece: [Point], atStart: Bool) -> Point {
        // direction over the first/last ~2 px of the piece, pointing into the piece
        let k = min(piece.count - 1, 4)
        return atStart ? (piece[k] - piece[0]).normalized
                       : (piece[piece.count - 1 - k] - piece[piece.count - 1]).normalized
    }

    static func slice(_ P: [Point], from a: Int, to b: Int) -> [Point] {
        if a < b { return Array(P[a...b]) }
        return Array(P[a...]) + Array(P[...b])
    }

    static func resampleClosed(_ poly: [Point], step: Double) -> [Point] {
        let pts = poly + [poly[0]]
        var s = [Double](repeating: 0, count: pts.count)
        for i in 1..<pts.count { s[i] = s[i - 1] + distance(pts[i], pts[i - 1]) }
        let L = s[s.count - 1]
        guard L > 1e-9 else { return poly }
        let m = max(8, Int((L / step).rounded()))
        var out: [Point] = []
        out.reserveCapacity(m)
        var j = 0
        for k in 0..<m {
            let t = L * Double(k) / Double(m)
            while j < s.count - 2 && s[j + 1] < t { j += 1 }
            let seg = s[j + 1] - s[j]
            let f = seg > 1e-12 ? (t - s[j]) / seg : 0
            out.append(pts[j] + (pts[j + 1] - pts[j]) * f)
        }
        return out
    }

    static func polygon(_ poly: [Point]) -> [Segment] {
        (0..<poly.count).map { .line(poly[$0], poly[($0 + 1) % poly.count]) }
    }

    static func chordLength(_ s: Segment) -> Double { distance(s.start, s.end) }

    /// Where two lines meet through a few tiny segments (a chamfered or rounded pixel corner),
    /// extend both lines to their intersection and drop the tiny segments.
    static func sharpenCorners(_ input: [Segment], snap: Double) -> [Segment] {
        var segs = input
        var changed = true
        while changed && segs.count > 2 {
            changed = false
            let n = segs.count
            for i in 0..<n {
                guard case let .line(a1, b1) = segs[i], chordLength(segs[i]) > snap else { continue }
                var skipped = 0.0, k = 0
                var found = -1
                while k < 3 {
                    let j = (i + 1 + k) % n
                    if j == i { break }
                    if case .line = segs[j], chordLength(segs[j]) > snap { found = j; break }
                    skipped += chordLength(segs[j]); k += 1
                    if skipped > snap { break }
                }
                guard found >= 0, k >= 1, skipped <= snap, case let .line(a2, b2) = segs[found] else { continue }
                let d1 = (b1 - a1).normalized, d2 = (b2 - a2).normalized
                let sinA = abs(d1.cross(d2))
                guard sinA > sin(20 * Double.pi / 180) else { continue }
                // intersection of a1 + t d1 and a2 + u d2
                let t = (a2 - a1).cross(d2) / d1.cross(d2)
                let X = a1 + d1 * t
                guard distance(X, b1) < 2 * snap, distance(X, a2) < 2 * snap else { continue }
                var out: [Segment] = []
                for m in 0..<n {
                    let offset = (m - i + n) % n
                    if offset >= 1 && offset <= k { continue }          // the tiny segments
                    if m == i { out.append(.line(a1, X)) }
                    else if m == found { out.append(.line(X, b2)) }
                    else { out.append(segs[m]) }
                }
                segs = out
                changed = true
                break
            }
        }
        return segs
    }

    /// Consecutive lines that continue each other become one line.
    static func mergeCollinearLines(_ input: [Segment], tolerance: Double) -> [Segment] {
        var s = input
        var changed = true
        while changed && s.count > 3 {
            changed = false
            for i in 0..<s.count {
                let j = (i + 1) % s.count
                guard case let .line(a, b) = s[i], case let .line(_, c) = s[j] else { continue }
                let ac = c - a, L = ac.length
                guard L > 1e-9, (b - a).dot(c - b) > 0 else { continue }
                if abs((b - a).cross(ac)) / L < tolerance * 0.5 {
                    if j == 0 { s[0] = .line(a, c); s.removeLast() }
                    else { s[i] = .line(a, c); s.remove(at: j) }
                    changed = true
                    break
                }
            }
        }
        return s
    }

    /// Make consecutive segments share exact endpoints.
    static func stitch(_ segs: [Segment]) -> [Segment] {
        guard segs.count > 1 else { return segs }
        var out = segs
        for i in 0..<out.count {
            let next = out[(i + 1) % out.count].start
            switch out[i] {
            case .line(let a, _): out[i] = .line(a, next)
            case .cubic(let a, let b, let c, _): out[i] = .cubic(a, b, c, next)
            }
        }
        return out
    }

    static func solve3(_ A: [[Double]], _ b: [Double]) -> [Double]? {
        var m = A.map { $0 }, r = b
        for col in 0..<3 {
            var piv = col
            for row in col..<3 where abs(m[row][col]) > abs(m[piv][col]) { piv = row }
            guard abs(m[piv][col]) > 1e-12 else { return nil }
            m.swapAt(col, piv); r.swapAt(col, piv)
            for row in 0..<3 where row != col {
                let f = m[row][col] / m[col][col]
                for k in col..<3 { m[row][k] -= f * m[col][k] }
                r[row] -= f * r[col]
            }
        }
        return (0..<3).map { r[$0] / m[$0][$0] }
    }
}

extension CurveFitter {
    /// Convert fitted segments of several contours into one compound path.
    public static func path(from contours: [[Segment]]) -> VectorPath {
        var el: [PathElement] = []
        for segs in contours where !segs.isEmpty {
            el.append(.move(segs[0].start))
            for s in segs {
                switch s {
                case .line(_, let b): el.append(.line(b))
                case .cubic(_, let c1, let c2, let d): el.append(.cubic(c1, c2, d))
                }
            }
            el.append(.close)
        }
        return VectorPath(elements: el)
    }
}
