import AppKit
import UniformTypeIdentifiers

@MainActor
enum Panels {
    static func openImage(_ done: @escaping (URL) -> Void) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        p.message = "Choisis une image à vectoriser"
        if p.runModal() == .OK, let url = p.url { done(url) }
    }

    static func save(suggested: String, type: UTType, write: (URL) throws -> Void, onError: (String) -> Void) {
        let p = NSSavePanel()
        p.allowedContentTypes = [type]
        p.nameFieldStringValue = suggested
        p.canCreateDirectories = true
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try write(url) } catch { onError(error.localizedDescription) }
    }

    static func chooseFolder(prompt: String, write: (URL) throws -> Void, onError: (String) -> Void) {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.prompt = prompt
        p.message = "Un dossier « …-favicons » sera créé à cet emplacement."
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try write(url) } catch { onError(error.localizedDescription) }
    }
}
