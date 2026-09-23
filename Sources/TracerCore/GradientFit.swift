import Foundation

/// Fits a flat colour or a linear gradient to the pixels of one region.
public enum GradientFit {
    /// - Parameters:
    ///   - pixels: indices of the region's interior pixels in `img`.
    ///   - scale: document units per working pixel (the gradient is returned in document units).
    public static func fill(_ img: RGBAImage, pixels: [Int], scale: Double) -> Fill {
        guard !pixels.isEmpty else { return .solid(RGB(0, 0, 0)) }
        let w = img.width
        let step = max(1, pixels.count / 150_000)
        var sample: [Int] = []
        sample.reserveCapacity(pixels.count / step + 1)
        var i = 0
        while i < pixels.count { sample.append(pixels[i]); i += step }

        let mean = meanColor(img, sample)
        guard sample.count >= 30 else { return .solid(mean) }

        // least squares  c = c0 + gx·x + gy·y  per channel (centred coordinates)
        var mx = 0.0, my = 0.0
        for p in sample { mx += Double(p % w); my += Double(p / w) }
        mx /= Double(sample.count); my /= Double(sample.count)
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        var sxc = [0.0, 0.0, 0.0], syc = [0.0, 0.0, 0.0]
        for p in sample {
            let dx = Double(p % w) - mx, dy = Double(p / w) - my
            sxx += dx * dx; sxy += dx * dy; syy += dy * dy
            let c = [Double(img.r[p]), Double(img.g[p]), Double(img.b[p])]
            for k in 0..<3 { sxc[k] += dx * c[k]; syc[k] += dy * c[k] }
        }
        let det = sxx * syy - sxy * sxy
        guard det > 1e-9 else { return .solid(mean) }
        var gx = [0.0, 0.0, 0.0], gy = [0.0, 0.0, 0.0]
        for k in 0..<3 {
            gx[k] = (sxc[k] * syy - syc[k] * sxy) / det
            gy[k] = (syc[k] * sxx - sxc[k] * sxy) / det
        }
        // direction of strongest change: top eigenvector of JᵀJ
        var a = 0.0, b = 0.0, c = 0.0
        for k in 0..<3 { a += gx[k] * gx[k]; b += gx[k] * gy[k]; c += gy[k] * gy[k] }
        let theta = 0.5 * atan2(2 * b, a - c)
        let d = Point(cos(theta), sin(theta))

        // extent of the region along d
        var proj = sample.map { Double($0 % w) * d.x + Double($0 / w) * d.y }
        proj.sort()
        let s0 = proj[Int(Double(proj.count - 1) * 0.01)], s1 = proj[Int(Double(proj.count - 1) * 0.99)]
        guard s1 - s0 > 2 else { return .solid(mean) }

        // bin the colours along d
        let bins = 10
        var sums = [RGB](repeating: RGB(0, 0, 0), count: bins)
        var counts = [Double](repeating: 0, count: bins)
        for p in sample {
            let s = Double(p % w) * d.x + Double(p / w) * d.y
            guard s >= s0, s <= s1 else { continue }
            let k = min(bins - 1, Int((s - s0) / (s1 - s0) * Double(bins)))
            sums[k] = sums[k] + RGB(Double(img.r[p]), Double(img.g[p]), Double(img.b[p]))
            counts[k] += 1
        }
        var stops: [GradientStop] = []
        for k in 0..<bins where counts[k] >= 5 {
            stops.append(GradientStop(offset: (Double(k) + 0.5) / Double(bins), color: sums[k] * (1 / counts[k])))
        }
        guard stops.count >= 2 else { return .solid(mean) }
        let first = ColorMath.lab(stops[0].color), last = ColorMath.lab(stops[stops.count - 1].color)
        var spread: Float = ColorMath.deltaE(first, last)
        for st in stops { spread = max(spread, ColorMath.deltaE(ColorMath.lab(st.color), ColorMath.lab(mean)) * 2) }
        guard spread >= 3 else { return .solid(mean) }

        stops = simplify(stops, tolerance: 1.2)
        // gradient vector: the points on the line through the region's centroid, at s0 and s1
        let centroidS = mx * d.x + my * d.y
        let base = Point(mx, my) - d * centroidS
        let p0 = (base + d * s0 + Point(0.5, 0.5)) * scale
        let p1 = (base + d * s1 + Point(0.5, 0.5)) * scale
        return .linear(LinearGradient(start: p0, end: p1, stops: stops))
    }

    static func meanColor(_ img: RGBAImage, _ pix: [Int]) -> RGB {
        var r = 0.0, g = 0.0, b = 0.0
        for p in pix { r += Double(img.r[p]); g += Double(img.g[p]); b += Double(img.b[p]) }
        let n = Double(max(1, pix.count))
        return RGB(r / n, g / n, b / n)
    }

    /// Drop interior stops that linear interpolation between their neighbours reproduces.
    static func simplify(_ input: [GradientStop], tolerance: Float) -> [GradientStop] {
        var s = input
        var changed = true
        while changed && s.count > 2 {
            changed = false
            var best = -1, bestErr = Float.infinity
            for i in 1..<(s.count - 1) {
                let a = s[i - 1], b = s[i + 1]
                let t = (s[i].offset - a.offset) / (b.offset - a.offset)
                let interp = a.color * (1 - t) + b.color * t
                let e = ColorMath.deltaE(ColorMath.lab(interp), ColorMath.lab(s[i].color))
                if e < bestErr { bestErr = e; best = i }
            }
            if best > 0 && bestErr < tolerance { s.remove(at: best); changed = true }
        }
        return s
    }
}
