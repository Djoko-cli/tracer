import Foundation
import TracerCore

// tracer-cli <image> [-o out.svg] [--colors N] [--precision P]
func run() -> Int32 {
    var args = Array(CommandLine.arguments.dropFirst())
    func take(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        args.removeSubrange(i...(i + 1))
        return v
    }
    let output = take("-o")
    var settings = Vectorizer.Settings()
    if let c = take("--colors"), let n = Int(c) { settings.colors = n }
    if let p = take("--precision"), let v = Double(p) { settings.precision = v }
    guard let input = args.first else {
        FileHandle.standardError.write(Data("usage: tracer-cli <image> [-o out.svg] [--colors N] [--precision P]\n".utf8))
        return 2
    }
    do {
        let url = URL(fileURLWithPath: input)
        let result = try Vectorizer.run(try RGBAImage.load(url: url), settings)
        let doc = result.document
        print(String(format: "%@  %.0fx%.0f  working %dx%d  %.2f s", url.lastPathComponent, doc.width, doc.height,
                     result.working.width, result.working.height, result.duration))
        for l in doc.layers {
            print(String(format: "  layer %d  %@  %5.1f%%  %4d segments", l.id, l.fill.averageColor.hex,
                         100 * l.coverage, l.path.segmentCount))
        }
        print("  total segments \(doc.segmentCount)")
        if let output {
            try SVGWriter.svg(doc).write(toFile: output, atomically: true, encoding: .utf8)
            print("  wrote \(output)")
        }
        return 0
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        return 1
    }
}
exit(run())
