import SwiftUI

@main
struct TracerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        // One window: files opened from the Finder or the Dock land in it.
        Window("Tracer", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 560)
                .task { DebugSnapshot.runIfRequested(model) }
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
