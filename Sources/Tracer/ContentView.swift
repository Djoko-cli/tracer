import SwiftUI
import TracerCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showInspector = true
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.source == nil { DropZoneView() } else { CanvasView() }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3).padding(8)
                    .allowsHitTesting(false)
            }
        }
        .inspector(isPresented: $showInspector) {
            InspectorView().inspectorColumnWidth(min: 270, ideal: 300, max: 380)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { Panels.openImage { model.open($0) } } label: {
                    Label("Ouvrir", systemImage: "photo.badge.plus")
                }
                .help("Ouvrir une image (⌘O)")
            }
            ToolbarItem(placement: .principal) {
                Picker("Affichage", selection: $model.mode) {
                    ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(model.source == nil)
                .help("Original, résultat vectoriel, contours sur l'original, carte de l'écart")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("SVG…") { model.exportSVG() }
                    Divider()
                    ForEach([1024, 2048, 4096], id: \.self) { n in
                        Button("PNG \(n) px…") { model.exportPNG(longSide: n) }
                    }
                    Divider()
                    Button("Favicons…") { model.exportFavicons() }
                } label: {
                    Label("Exporter", systemImage: "square.and.arrow.up")
                }
                .disabled(model.document == nil)
                Button { showInspector.toggle() } label: {
                    Label("Réglages", systemImage: "sidebar.right")
                }
            }
        }
        .onOpenURL { model.open($0) }          // « Ouvrir avec Tracer » depuis le Finder
        .navigationTitle(model.sourceURL?.lastPathComponent ?? "Tracer")
        .alert("Oups", isPresented: Binding(get: { model.errorMessage != nil },
                                             set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct DropZoneView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("Dépose une image ici")
                .font(.title2.weight(.medium))
            Text("Logos, pictos, illustrations en aplats et dégradés — PNG, JPEG, WebP, TIFF, HEIC")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choisir une image…") { Panels.openImage { model.open($0) } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                .foregroundStyle(.quaternary)
                .padding(28)
        }
    }
}
