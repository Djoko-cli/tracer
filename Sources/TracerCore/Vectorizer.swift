import Foundation
import CoreGraphics

public enum Vectorizer {
    public struct Settings: Sendable, Equatable {
        /// Number of colour clusters.
        public var colors: Int = 4
        /// Maximum deviation of the curves, in pixels of the working image.
        public var precision: Double = 1.0
        /// The image is resampled so its longest side falls in this range.
        public var workingSizeRange: ClosedRange<Int> = 800...1600
        /// Regions smaller than this fraction of the image are merged into a neighbour.
        public var minRegionFraction: Double = 0.00002
        public init(colors: Int = 4, precision: Double = 1.0) { self.colors = colors; self.precision = precision }
    }

    public struct Result: @unchecked Sendable {
        public var document: VectorDocument
        /// The image the vectorisation was computed on (working resolution).
        public var working: RGBAImage
        /// Working pixels per document unit.
        public var workingScale: Double
        public var duration: TimeInterval
    }

    public static func run(_ source: CGImage, _ settings: Settings) throws -> Result {
        let t0 = Date()
        let longest = max(source.width, source.height)
        guard longest > 0 else { throw TraceError.emptyImage }
        let target = min(max(longest, settings.workingSizeRange.lowerBound), settings.workingSizeRange.upperBound)
        let k = Double(target) / Double(longest)
        let ww = max(1, Int((Double(source.width) * k).rounded()))
        let wh = max(1, Int((Double(source.height) * k).rounded()))
        let img = RGBAImage(cgImage: source, width: ww, height: wh)
        guard img.a.contains(where: { $0 >= 0.5 }) else { throw TraceError.emptyImage }

        let minRegion = max(4, Int(Double(ww * wh) * settings.minRegionFraction))
        let seg = Segmenter.segment(img, colors: settings.colors, minRegion: minRegion)
        let colours = meanColours(img, seg)
        let order = drawingOrder(seg)

        var fitter = CurveFitter(tolerance: settings.precision)
        fitter.straightRadius = 0.2 * Double(max(ww, wh))
        fitter.minLineLength = max(6, 0.006 * Double(max(ww, wh)))
        // pixel corners get rounded by anti-aliasing, more so when the image was enlarged
        fitter.cornerSnap = max(2.5 * settings.precision, 2 + 2 * max(1, k))
        fitter.cornerWindow = 1.5 + 1.5 * max(1, k)

        let scale = Double(source.width) / Double(ww)          // document units per working pixel
        let areas = seg.areas()
        var layers: [VectorLayer] = []
        for (rank, label) in order.enumerated() {
            let higher = Set(order[(rank + 1)...])
            let inside = stackedMask(seg, label: Int32(label), higher: higher)
            let field = coverageField(img, seg, inside: inside, colours: colours).blurred(sigma: 0.6)
            let loops = MarchingSquares.contours(field).filter { abs(signedArea($0)) >= Double(minRegion) }
            let fitted = loops.map { fitter.fitClosed($0) }
            let path = CurveFitter.path(from: fitted).transformed(scale: scale)
            let fill = GradientFit.fill(img, pixels: interiorPixels(seg, label: Int32(label)), scale: scale)
            layers.append(VectorLayer(id: rank, path: path, fill: fill,
                                      coverage: Double(areas[label]) / Double(ww * wh)))
        }
        let doc = VectorDocument(width: Double(source.width), height: Double(source.height), layers: layers)
        return Result(document: doc, working: img, workingScale: 1 / scale, duration: Date().timeIntervalSince(t0))
    }

    /// Pixels of `label` whose 8 neighbours all share it (edges and fringes excluded).
    static func interiorPixels(_ seg: Segmentation, label: Int32) -> [Int] {
        let w = seg.width, h = seg.height
        var out: [Int] = []
        for y in 1..<max(1, h - 1) {
            for x in 1..<max(1, w - 1) {
                let i = y * w + x
                guard seg.labels[i] == label else { continue }
                if seg.labels[i - 1] == label, seg.labels[i + 1] == label,
                   seg.labels[i - w] == label, seg.labels[i + w] == label,
                   seg.labels[i - w - 1] == label, seg.labels[i - w + 1] == label,
                   seg.labels[i + w - 1] == label, seg.labels[i + w + 1] == label { out.append(i) }
            }
        }
        if out.isEmpty { out = seg.labels.indices.filter { seg.labels[$0] == label } }
        return out
    }

    /// Mean sRGB colour of each label's opaque pixels.
    static func meanColours(_ img: RGBAImage, _ seg: Segmentation) -> [RGB] {
        var sum = [RGB](repeating: RGB(0, 0, 0), count: seg.colorCount)
        var n = [Double](repeating: 0, count: seg.colorCount)
        for i in 0..<img.count {
            let l = seg.labels[i]
            guard l >= 0 else { continue }
            sum[Int(l)] = sum[Int(l)] + RGB(Double(img.r[i]), Double(img.g[i]), Double(img.b[i]))
            n[Int(l)] += 1
        }
        return (0..<seg.colorCount).map { n[$0] > 0 ? sum[$0] * (1 / n[$0]) : RGB(0, 0, 0) }
    }

    /// Bottom layer = the colour touching the image border most; the rest by decreasing area.
    static func drawingOrder(_ seg: Segmentation) -> [Int] {
        let w = seg.width, h = seg.height
        var border = [Int](repeating: 0, count: seg.colorCount)
        func tally(_ i: Int) { let l = seg.labels[i]; if l >= 0 { border[Int(l)] += 1 } }
        for x in 0..<w { tally(x); tally((h - 1) * w + x) }
        for y in 0..<h { tally(y * w); tally(y * w + w - 1) }
        let areas = seg.areas()
        let present = (0..<seg.colorCount).filter { areas[$0] > 0 }
        guard let bottom = present.max(by: { border[$0] < border[$1] }), border[bottom] > 0 else {
            return present.sorted { areas[$0] > areas[$1] }
        }
        return [bottom] + present.filter { $0 != bottom }.sorted { areas[$0] > areas[$1] }
    }

    /// The layer's own pixels plus the pixels of higher layers that are connected to them,
    /// so the shape runs under what is drawn on top of it (no seams, no needless holes).
    static func stackedMask(_ seg: Segmentation, label: Int32, higher: Set<Int>) -> [Bool] {
        let w = seg.width, h = seg.height, n = w * h
        var candidate = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let l = seg.labels[i]
            candidate[i] = l == label || (l >= 0 && higher.contains(Int(l)))
        }
        var keep = [Bool](repeating: false, count: n)
        var stack: [Int] = []
        for seed in 0..<n where seg.labels[seed] == label && !keep[seed] {
            keep[seed] = true; stack.append(seed)
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                if x > 0, candidate[i - 1], !keep[i - 1] { keep[i - 1] = true; stack.append(i - 1) }
                if x < w - 1, candidate[i + 1], !keep[i + 1] { keep[i + 1] = true; stack.append(i + 1) }
                if y > 0, candidate[i - w], !keep[i - w] { keep[i - w] = true; stack.append(i - w) }
                if y < h - 1, candidate[i + w], !keep[i + w] { keep[i + w] = true; stack.append(i + w) }
            }
        }
        return keep
    }

    /// 1 inside, 0 outside, and on the boundary the fraction of the pixel covered by the
    /// inside colour, estimated from the pixel's colour (or its alpha against transparency).
    static func coverageField(_ img: RGBAImage, _ seg: Segmentation, inside: [Bool], colours: [RGB]) -> Field {
        let w = img.width, h = img.height
        var f = Field(width: w, height: h)
        for i in 0..<(w * h) where inside[i] { f.values[i] = 1 }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                var other = -1
                if x > 0, inside[i - 1] != inside[i] { other = i - 1 }
                else if x < w - 1, inside[i + 1] != inside[i] { other = i + 1 }
                else if y > 0, inside[i - w] != inside[i] { other = i - w }
                else if y < h - 1, inside[i + w] != inside[i] { other = i + w }
                guard other >= 0 else { continue }
                let li = inside[i] ? seg.labels[i] : seg.labels[other]
                let lo = inside[i] ? seg.labels[other] : seg.labels[i]
                if lo < 0 || li < 0 {
                    // against transparency: alpha is the coverage
                    f.values[i] = inside[i] || li >= 0 ? img.a[i] : 0
                    continue
                }
                let cin = colours[Int(li)], cout = colours[Int(lo)]
                let dr = cin.r - cout.r, dg = cin.g - cout.g, db = cin.b - cout.b
                let den = dr * dr + dg * dg + db * db
                guard den > 1e-6 else { continue }
                let pr = Double(img.r[i]) - cout.r, pg = Double(img.g[i]) - cout.g, pb = Double(img.b[i]) - cout.b
                let alpha = (pr * dr + pg * dg + pb * db) / den
                f.values[i] = Float(min(1, max(0, alpha)))
            }
        }
        return f
    }
}
