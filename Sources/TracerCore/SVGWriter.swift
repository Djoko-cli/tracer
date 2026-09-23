import Foundation

public enum SVGWriter {
    /// - Parameter square: pad the viewBox to a centred square (for icons).
    public static func svg(_ doc: VectorDocument, square: Bool = false) -> String {
        var vbX = 0.0, vbY = 0.0, vbW = doc.width, vbH = doc.height
        if square {
            let side = max(doc.width, doc.height)
            vbX = (doc.width - side) / 2; vbY = (doc.height - side) / 2
            vbW = side; vbH = side
        }
        var defs: [String] = []
        var body: [String] = []
        for layer in doc.visibleLayers where !layer.path.elements.isEmpty {
            let d = pathData(layer.path)
            switch layer.fill {
            case .solid(let c):
                body.append("  <path fill=\"\(c.hex)\" fill-rule=\"evenodd\" d=\"\(d)\"/>")
            case .linear(let g):
                let id = "g\(layer.id)"
                var s = "    <linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" "
                s += "x1=\"\(num(g.start.x))\" y1=\"\(num(g.start.y))\" x2=\"\(num(g.end.x))\" y2=\"\(num(g.end.y))\">\n"
                for st in g.stops {
                    s += "      <stop offset=\"\(num(st.offset, 4))\" stop-color=\"\(st.color.hex)\"/>\n"
                }
                s += "    </linearGradient>"
                defs.append(s)
                body.append("  <path fill=\"url(#\(id))\" fill-rule=\"evenodd\" d=\"\(d)\"/>")
            }
        }
        var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(num(vbX)) \(num(vbY)) \(num(vbW)) \(num(vbH))\" "
        out += "width=\"\(num(vbW))\" height=\"\(num(vbH))\">\n"
        if !defs.isEmpty { out += "  <defs>\n" + defs.joined(separator: "\n") + "\n  </defs>\n" }
        out += body.joined(separator: "\n")
        out += "\n</svg>\n"
        return out
    }

    public static func pathData(_ p: VectorPath) -> String {
        var s = ""
        var last: Character? = nil
        func cmd(_ c: Character) { if last != c { s += String(c); last = c } else { s += " " } }
        func pt(_ q: Point) -> String { "\(num(q.x)) \(num(q.y))" }
        for e in p.elements {
            switch e {
            case .move(let q):
                if !s.isEmpty { s += " " }
                s += "M" + pt(q); last = "M"
            case .line(let q): cmd("L"); s += pt(q)
            case .cubic(let a, let b, let c): cmd("C"); s += pt(a) + " " + pt(b) + " " + pt(c)
            case .close: s += "Z"; last = "Z"
            }
        }
        return s
    }

    /// Up to `digits` decimals, trailing zeros removed.
    public static func num(_ v: Double, _ digits: Int = 2) -> String {
        var s = String(format: "%.\(digits)f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if s == "-0" { s = "0" }
        return s
    }
}
