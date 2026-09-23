import SwiftUI

@main
struct TracerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Tracer") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ouvrir une image…") { Panels.openImage { model.open($0) } }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .saveItem) {
                Button("Exporter le SVG…") { model.exportSVG() }
                    .keyboardShortcut("e")
                    .disabled(model.document == nil)
                Button("Exporter les favicons…") { model.exportFavicons() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.document == nil)
            }
        }
    }
}
