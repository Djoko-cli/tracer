import AppKit

/// Development hook, inactive unless the environment asks for it:
///   TRACER_OPEN=<image>   open this image at launch
///   TRACER_MODE=<Vecteur|Contours|Écart|Original>
///   TRACER_SNAPSHOT=<png> after TRACER_SNAPSHOT_DELAY seconds (default 3), write the window's pixels there
///   TRACER_QUIT=1         quit after the snapshot
@MainActor
enum DebugSnapshot {
    static func runIfRequested(_ model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        if let path = env["TRACER_OPEN"] { model.open(URL(fileURLWithPath: path)) }
        if let m = env["TRACER_MODE"].flatMap(ViewMode.init(rawValue:)) { model.mode = m }
        guard let out = env["TRACER_SNAPSHOT"] else { return }
        let delay = Double(env["TRACER_SNAPSHOT_DELAY"] ?? "") ?? 3
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if let win = NSApp.windows.first(where: \.isVisible),
               let view = win.contentView?.superview ?? win.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            }
            if env["TRACER_QUIT"] != nil { NSApp.terminate(nil) }
        }
    }
}
