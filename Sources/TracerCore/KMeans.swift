import Foundation

/// Deterministic k-means++ on 3-D features.
public enum KMeans {
    public struct RNG: RandomNumberGenerator {
        var state: UInt64
        public init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
        public mutating func next() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
    }

    public static func cluster(_ x: [SIMD3<Float>], k: Int, iterations: Int = 20, seed: UInt64 = 7) -> [SIMD3<Float>] {
        guard !x.isEmpty else { return [] }
        let k = min(k, x.count)
        var rng = RNG(seed: seed)
        var centres: [SIMD3<Float>] = [x[Int(rng.next() % UInt64(x.count))]]
        var d2 = x.map { dist2($0, centres[0]) }
        while centres.count < k {
            let total = d2.reduce(0, +)
            if total <= 0 { break }
            var t = Float(Double(rng.next() % 1_000_000) / 1_000_000) * total
            var pick = x.count - 1
            for i in 0..<x.count { t -= d2[i]; if t <= 0 { pick = i; break } }
            centres.append(x[pick])
            for i in 0..<x.count { d2[i] = min(d2[i], dist2(x[i], x[pick])) }
        }
        var assign = [Int](repeating: 0, count: x.count)
        for _ in 0..<iterations {
            var changed = false
            for i in 0..<x.count {
                let c = nearest(x[i], centres)
                if c != assign[i] { assign[i] = c; changed = true }
            }
            var sum = [SIMD3<Float>](repeating: .zero, count: centres.count)
            var n = [Int](repeating: 0, count: centres.count)
            for i in 0..<x.count { sum[assign[i]] += x[i]; n[assign[i]] += 1 }
            for c in 0..<centres.count where n[c] > 0 { centres[c] = sum[c] / Float(n[c]) }
            if !changed { break }
        }
        return centres
    }

    @inlinable public static func dist2(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b; return (d * d).sum()
    }

    @inlinable public static func nearest(_ p: SIMD3<Float>, _ centres: [SIMD3<Float>]) -> Int {
        var best = 0, bd = Float.infinity
        for (i, c) in centres.enumerated() {
            let d = dist2(p, c)
            if d < bd { bd = d; best = i }
        }
        return best
    }
}
