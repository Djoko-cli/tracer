import SwiftUI
import TracerCore

struct CanvasView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            if let src = model.source {
                let w = Double(src.cg.width), h = Double(src.cg.height)
                let fit = max(0.01, min((geo.size.width - 48) / w, (geo.size.height - 48) / h))
                let z = model.fitToWindow ? fit : model.zoom
                ScrollView([.horizontal, .vertical]) {
                    content(src, width: w, height: h)
                        .frame(width: w * z, height: h * z)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                        .padding(24)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
                .overlay(alignment: .bottomTrailing) { zoomControls(fit: fit, current: z) }
                .overlay(alignment: .topTrailing) {
                    if model.isWorking {
                        ProgressView().controlSize(.small).padding(10)
                    }
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private func content(_ src: SendableImage, width w: Double, height h: Double) -> some View {
        ZStack {
            Checkerboard()
            switch model.mode {
            case .original:
                Image(decorative: src.cg, scale: 1).resizable().interpolation(.high)
            case .vector:
                if let doc = model.document { DocumentCanvas(document: doc) }
                else { Image(decorative: src.cg, scale: 1).resizable().interpolation(.high).opacity(0.3) }
            case .outlines:
                Image(decorative: src.cg, scale: 1).resizable().interpolation(.high).opacity(0.55)
                if let doc = model.document { OutlineCanvas(document: doc) }
            case .difference:
                if let heat = model.heatmap { Image(decorative: heat.cg, scale: 1).resizable().interpolation(.high) }
            }
        }
    }

    private func zoomControls(fit: Double, current z: Double) -> some View {
        HStack(spacing: 2) {
            Button { setZoom(z / 1.5) } label: { Image(systemName: "minus") }
                .keyboardShortcut("-", modifiers: .command)
            Button { model.fitToWindow = false; model.zoom = 1 } label: {
                Text("\(Int((z * 100).rounded())) %").monospacedDigit().frame(minWidth: 46)
            }
            .help("Taille réelle")
            Button { setZoom(z * 1.5) } label: { Image(systemName: "plus") }
                .keyboardShortcut("=", modifiers: .command)
            Divider().frame(height: 14)
            Button("Ajuster") { model.fitToWindow = true }
                .keyboardShortcut("0", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(14)
    }

    private func setZoom(_ z: Double) {
        model.fitToWindow = false
        model.zoom = min(max(z, 0.05), 32)
    }
}

/// The vector result, drawn as vectors (sharp at any zoom).
struct DocumentCanvas: View {
    let document: VectorDocument
    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / document.width, y: size.height / document.height)
            for layer in document.visibleLayers {
                let path = Path(Rasterizer.cgPath(layer.path))
                switch layer.fill {
                case .solid(let c):
                    ctx.fill(path, with: .color(c.color), style: FillStyle(eoFill: true))
                case .linear(let g):
                    let grad = Gradient(stops: g.stops.map { .init(color: $0.color.color, location: $0.offset) })
                    ctx.fill(path, with: .linearGradient(grad, startPoint: CGPoint(x: g.start.x, y: g.start.y),
                                                          endPoint: CGPoint(x: g.end.x, y: g.end.y)),
                             style: FillStyle(eoFill: true))
                }
            }
        }
    }
}

/// Outlines and anchor points of every visible layer, over the original.
struct OutlineCanvas: View {
    let document: VectorDocument
    var body: some View {
        Canvas { ctx, size in
            let t = CGAffineTransform(scaleX: size.width / document.width, y: size.height / document.height)
            let accent = Color.accentColor
            for layer in document.visibleLayers {
                ctx.stroke(Path(Rasterizer.cgPath(layer.path)).applying(t), with: .color(accent), lineWidth: 1)
            }
            for layer in document.visibleLayers {
                for e in layer.path.elements {
                    let p: Point
                    switch e {
                    case .move(let q), .line(let q): p = q
                    case .cubic(_, _, let q): p = q
                    case .close: continue
                    }
                    let q = CGPoint(x: p.x, y: p.y).applying(t)
                    let r = CGRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5)
                    ctx.fill(Path(r), with: .color(.white))
                    ctx.stroke(Path(r), with: .color(accent), lineWidth: 1)
                }
            }
        }
    }
}

/// Transparency grid.
struct Checkerboard: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 8
            let a = scheme == .dark ? Color(white: 0.22) : Color(white: 1)
            let b = scheme == .dark ? Color(white: 0.28) : Color(white: 0.9)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(a))
            var y: CGFloat = 0, row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : s
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(b))
                    x += 2 * s
                }
                y += s; row += 1
            }
        }
    }
}
