import Foundation

/// Splits an image into flat colour regions.
public struct Segmentation: Sendable {
    public let width: Int, height: Int
    /// Label per pixel; `transparent` for pixels with alpha < 0.5.
    public var labels: [Int32]
    public let colorCount: Int
    public static let transparent: Int32 = -1

    /// Pixel count per colour label.
    public func areas() -> [Int] {
        var n = [Int](repeating: 0, count: colorCount)
        for l in labels where l >= 0 { n[Int(l)] += 1 }
        return n
    }
}

public enum Segmenter {
    /// - Parameters:
    ///   - colors: number of colour clusters.
    ///   - minRegion: connected regions smaller than this many pixels are absorbed by a neighbour.
    public static func segment(_ img: RGBAImage, colors: Int, minRegion: Int) -> Segmentation {
        let n = img.count
        let w = img.width, h = img.height
        var lab = [SIMD3<Float>](repeating: .zero, count: n)
        var opaque: [Int] = []
        opaque.reserveCapacity(n)
        for i in 0..<n {
            lab[i] = ColorMath.lab(img.r[i], img.g[i], img.b[i])
            if img.a[i] >= 0.5 { opaque.append(i) }
        }
        // Cluster only "flat" pixels: anti-aliased edges would otherwise steal clusters.
        var flat: [Int] = []
        flat.reserveCapacity(opaque.count)
        for i in opaque {
            let x = i % w, y = i / w
            guard x > 0, y > 0, x < w - 1, y < h - 1 else { continue }
            let c = lab[i]
            if img.a[i - 1] >= 0.99, img.a[i + 1] >= 0.99, img.a[i - w] >= 0.99, img.a[i + w] >= 0.99,
               ColorMath.deltaE(c, lab[i - 1]) < 6, ColorMath.deltaE(c, lab[i + 1]) < 6,
               ColorMath.deltaE(c, lab[i - w]) < 6, ColorMath.deltaE(c, lab[i + w]) < 6 {
                flat.append(i)
            }
        }
        let pool = flat.count >= 64 ? flat : opaque
        let stride = max(1, pool.count / 60_000)
        let sample = Swift.stride(from: 0, to: pool.count, by: stride).map { lab[pool[$0]] }
        let centres = KMeans.cluster(sample, k: max(1, colors))
        var labels = [Int32](repeating: Segmentation.transparent, count: n)
        for i in opaque { labels[i] = Int32(KMeans.nearest(lab[i], centres)) }

        removeSlivers(&labels, lab: lab, centres: centres, alpha: img.a, width: w, height: h)
        absorbSmallRegions(&labels, width: w, height: h, minRegion: minRegion)
        let merged = mergeSmoothNeighbours(&labels, lab: lab, count: centres.count, width: w, height: h)
        return Segmentation(width: w, height: h, labels: labels, colorCount: merged)
    }

    /// Two colours that meet without an edge (the jump between neighbouring pixels across
    /// their border is small) are two bands of the same gradient: merge them.
    /// Returns the number of labels left; labels are renumbered 0..<n.
    static func mergeSmoothNeighbours(_ labels: inout [Int32], lab: [SIMD3<Float>], count: Int,
                                      width w: Int, height h: Int, threshold: Float = 3.5) -> Int {
        guard count > 1 else { return count }
        var sum = [Float](repeating: 0, count: count * count)
        var num = [Int](repeating: 0, count: count * count)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x, a = labels[i]
                guard a >= 0 else { continue }
                for j in [x + 1 < w ? i + 1 : -1, y + 1 < h ? i + w : -1] where j >= 0 {
                    let b = labels[j]
                    guard b >= 0, b != a else { continue }
                    let lo = Int(min(a, b)), hi = Int(max(a, b))
                    sum[lo * count + hi] += ColorMath.deltaE(lab[i], lab[j])
                    num[lo * count + hi] += 1
                }
            }
        }
        var parent = Array(0..<count)
        func find(_ x: Int) -> Int { var x = x; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
        for a in 0..<count {
            for b in (a + 1)..<count where num[a * count + b] >= 8 {
                if sum[a * count + b] / Float(num[a * count + b]) < threshold {
                    let ra = find(a), rb = find(b)
                    if ra != rb { parent[rb] = ra }
                }
            }
        }
        var newId = [Int: Int32]()
        var used = Set<Int32>(labels.filter { $0 >= 0 })
        for l in 0..<count where used.contains(Int32(l)) { let r = find(l); if newId[r] == nil { newId[r] = Int32(newId.count) } }
        used.removeAll()
        for i in labels.indices where labels[i] >= 0 { labels[i] = newId[find(Int(labels[i]))]! }
        return newId.count
    }

    /// Pixels that are not part of any uniform 3×3 block (anti-aliasing fringes, 1–2 px slivers)
    /// are re-assigned from their neighbours, picking the neighbouring label of closest colour.
    static func removeSlivers(_ labels: inout [Int32], lab: [SIMD3<Float>], centres: [SIMD3<Float>],
                              alpha: [Float], width w: Int, height h: Int) {
        guard w >= 3, h >= 3 else { return }
        var core = [Bool](repeating: false, count: w * h)
        for y in 0...(h - 3) {
            for x in 0...(w - 3) {
                let l = labels[y * w + x]
                var uniform = true
                outer: for dy in 0..<3 {
                    for dx in 0..<3 where labels[(y + dy) * w + x + dx] != l { uniform = false; break outer }
                }
                if uniform { for dy in 0..<3 { for dx in 0..<3 { core[(y + dy) * w + x + dx] = true } } }
            }
        }
        var pending = (0..<(w * h)).filter { !core[$0] }
        var assigned = core
        var guardPasses = 0
        while !pending.isEmpty && guardPasses < 64 {
            guardPasses += 1
            var updates: [(Int, Int32)] = []
            var rest: [Int] = []
            for i in pending {
                let x = i % w, y = i / w
                var best: Int32? = nil, bestD = Float.infinity
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < w && ny < h && assigned[ny * w + nx] {
                    let l = labels[ny * w + nx]
                    let d: Float
                    if l == Segmentation.transparent { d = alpha[i] < 0.5 ? -1 : .infinity }
                    else if alpha[i] < 0.5 { d = .infinity }
                    else { d = KMeans.dist2(lab[i], centres[Int(l)]) }
                    if d < bestD { bestD = d; best = l }
                }
                if let b = best, bestD.isFinite { updates.append((i, b)) } else { rest.append(i) }
            }
            if updates.isEmpty { break }
            for (i, l) in updates { labels[i] = l; assigned[i] = true }
            pending = rest
        }
    }

    /// 4-connected regions smaller than `minRegion` take the label most common along their border.
    static func absorbSmallRegions(_ labels: inout [Int32], width w: Int, height h: Int, minRegion: Int) {
        guard minRegion > 1 else { return }
        var comp = [Int32](repeating: -1, count: w * h)
        var stack: [Int] = []
        var nextId: Int32 = 0
        for seed in 0..<(w * h) where comp[seed] < 0 {
            let l = labels[seed]
            var members: [Int] = []
            stack.append(seed); comp[seed] = nextId
            var border: [Int32: Int] = [:]
            while let i = stack.popLast() {
                members.append(i)
                let x = i % w, y = i / w
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < w && ny < h {
                    let j = ny * w + nx
                    if labels[j] == l {
                        if comp[j] < 0 { comp[j] = nextId; stack.append(j) }
                    } else {
                        border[labels[j], default: 0] += 1
                    }
                }
            }
            if members.count < minRegion, let (target, _) = border.max(by: { $0.value < $1.value }) {
                for i in members { labels[i] = target }
            }
            nextId += 1
        }
    }
}
