import SwiftUI
import TracerCore
import UniformTypeIdentifiers

/// CGImage wrapper that can cross into background tasks (CGImage is immutable).
struct SendableImage: @unchecked Sendable { let cg: CGImage }

enum ViewMode: String, CaseIterable, Identifiable {
    case original = "Original", vector = "Vecteur", outlines = "Contours", difference = "Écart"
    var id: String { rawValue }
}

@MainActor @Observable
final class AppModel {
    // input
    private(set) var sourceURL: URL?
    private(set) var source: SendableImage?

    // settings (a change re-runs the vectorisation)
    var colors: Int = 8 { didSet { if colors != oldValue { schedule() } } }
    /// 0 = simple … 1 = faithful; mapped to a curve tolerance of 4 … 0.3 px.
    var fidelity: Double = 0.55 { didSet { if fidelity != oldValue { schedule() } } }
    var tolerance: Double { 4 * pow(0.3 / 4, fidelity) }

    // output
    private(set) var result: Vectorizer.Result?
    private(set) var meanError: Double?
    private(set) var heatmap: SendableImage?
    private(set) var isWorking = false
    var errorMessage: String?

    // view state
    var mode: ViewMode = .vector
    var zoom: Double = 1
    var fitToWindow = true

    /// Colours the user hid; kept across re-runs by matching colours.
    private var hiddenColors: [RGB] = []
    private var generation = 0
    private var pending: Task<Void, Never>?

    var document: VectorDocument? { result?.document }
    var fileName: String { sourceURL?.deletingPathExtension().lastPathComponent ?? "image" }

    // MARK: input

    func open(_ url: URL) {
        do {
            let img = try RGBAImage.load(url: url)
            sourceURL = url
            source = SendableImage(cg: img)
            hiddenColors = []
            result = nil; meanError = nil; heatmap = nil
            fitToWindow = true
            mode = .vector
            schedule(delay: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: processing

    private func schedule(delay: Double = 0.15) {
        guard let source else { return }
        pending?.cancel()
        generation += 1
        let gen = generation
        let settings = Vectorizer.Settings(colors: colors, precision: tolerance)
        isWorking = true
        pending = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<(Vectorizer.Result, Comparison.Report), Error> in
                do {
                    let r = try Vectorizer.run(source.cg, settings)
                    return .success((r, Comparison.compare(r.document, to: r.working)))
                } catch { return .failure(error) }
            }.value
            guard let self, gen == self.generation else { return }
            self.isWorking = false
            switch outcome {
            case .success(let (r, report)):
                var r = r
                for i in r.document.layers.indices where self.isHidden(r.document.layers[i].fill.averageColor) {
                    r.document.layers[i].isVisible = false
                }
                self.result = r
                self.meanError = report.meanError
                self.heatmap = SendableImage(cg: report.heatmap)
            case .failure(let e):
                self.errorMessage = e.localizedDescription
            }
        }
    }

    // MARK: layers

    private func isHidden(_ c: RGB) -> Bool {
        let lab = ColorMath.lab(c)
        return hiddenColors.contains { ColorMath.deltaE(ColorMath.lab($0), lab) < 12 }
    }

    func setVisible(_ visible: Bool, layer id: Int) {
        guard var r = result, let i = r.document.layers.firstIndex(where: { $0.id == id }) else { return }
        r.document.layers[i].isVisible = visible
        let c = r.document.layers[i].fill.averageColor
        let lab = ColorMath.lab(c)
        hiddenColors.removeAll { ColorMath.deltaE(ColorMath.lab($0), lab) < 12 }
        if !visible { hiddenColors.append(c) }
        result = r
    }

    // MARK: export

    func exportSVG() {
        guard let doc = document else { return }
        Panels.save(suggested: "\(fileName).svg", type: .svg) { url in
            try SVGWriter.svg(doc).write(to: url, atomically: true, encoding: .utf8)
        } onError: { self.errorMessage = $0 }
    }

    func exportPNG(longSide: Int) {
        guard let doc = document else { return }
        Panels.save(suggested: "\(fileName)-\(longSide).png", type: .png) { url in
            try Exporter.png(doc, longSide: longSide).write(to: url)
        } onError: { self.errorMessage = $0 }
    }

    func exportFavicons() {
        guard let doc = document else { return }
        let name = fileName
        Panels.chooseFolder(prompt: "Exporter ici") { folder in
            try Exporter.favicons(doc, to: folder.appendingPathComponent("\(name)-favicons"), name: name)
        } onError: { self.errorMessage = $0 }
    }
}
