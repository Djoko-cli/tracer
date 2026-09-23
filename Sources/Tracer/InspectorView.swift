import SwiftUI
import TracerCore

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            if let src = model.source {
                Section {
                    LabeledContent("Fichier") {
                        Text(model.sourceURL?.lastPathComponent ?? "—").lineLimit(1).truncationMode(.middle)
                    }
                    LabeledContent("Taille", value: "\(src.cg.width) × \(src.cg.height) px")
                }
            }

            Section {
                Stepper(value: $model.colors, in: 2...16) {
                    LabeledContent("Couleurs", value: "\(model.colors)")
                }
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Précision", value: String(format: "± %.1f px", model.tolerance))
                    Slider(value: $model.fidelity, in: 0...1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Simple").font(.caption)
                    } maximumValueLabel: {
                        Text("Fidèle").font(.caption)
                    }
                }
            } header: {
                Text("Réglages")
            } footer: {
                Text("Mets plus de couleurs que nécessaire : les bandes d'un même dégradé sont regroupées automatiquement.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(model.source == nil)

            if let doc = model.document {
                Section("Calques") {
                    ForEach(doc.layers) { layer in
                        LayerRow(layer: layer) { model.setVisible($0, layer: layer.id) }
                    }
                }
                Section("Résultat") {
                    LabeledContent("Segments", value: "\(doc.segmentCount)")
                    if let e = model.meanError {
                        LabeledContent("Écart moyen", value: String(format: "%.2f / 255", e))
                    }
                    if let t = model.result?.duration {
                        LabeledContent("Calcul", value: String(format: "%.2f s", t))
                    }
                }
                Section {
                    Button { model.exportSVG() } label: {
                        Label("Exporter le SVG…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    HStack {
                        Menu("PNG…") {
                            ForEach([1024, 2048, 4096], id: \.self) { n in
                                Button("\(n) px") { model.exportPNG(longSide: n) }
                            }
                        }
                        Button("Favicons…") { model.exportFavicons() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .overlay(alignment: .top) {
            if model.isWorking {
                ProgressView().controlSize(.small).padding(6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 6)
            }
        }
    }
}

struct LayerRow: View {
    let layer: VectorLayer
    let setVisible: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { setVisible(!layer.isVisible) } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .frame(width: 18)
                    .foregroundStyle(layer.isVisible ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .help(layer.isVisible ? "Masquer ce calque" : "Afficher ce calque")

            Swatch(fill: layer.fill).frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(.body, design: .monospaced))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.1f %%", 100 * layer.coverage))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .opacity(layer.isVisible ? 1 : 0.55)
    }

    private var title: String {
        switch layer.fill {
        case .solid(let c): return c.hex
        case .linear(let g): return "\(g.stops.first!.color.hex) → \(g.stops.last!.color.hex)"
        }
    }

    private var detail: String {
        let segs = "\(layer.path.segmentCount) segments"
        if case .linear(let g) = layer.fill { return "Dégradé \(g.stops.count) couleurs · " + segs }
        return "Aplat · " + segs
    }
}

struct Swatch: View {
    let fill: Fill
    var body: some View {
        Group {
            switch fill {
            case .solid(let c): Circle().fill(c.color)
            case .linear(let g):
                Circle().fill(LinearGradient(stops: g.stops.map { .init(color: $0.color.color, location: $0.offset) },
                                             startPoint: .leading, endPoint: .trailing))
            }
        }
        .overlay(Circle().strokeBorder(.separator, lineWidth: 1))
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}
