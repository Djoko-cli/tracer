import Foundation

public struct GradientStop: Sendable, Equatable {
    public var offset: Double
    public var color: RGB
    public init(offset: Double, color: RGB) { self.offset = offset; self.color = color }
}

public struct LinearGradient: Sendable, Equatable {
    public var start: Point
    public var end: Point
    public var stops: [GradientStop]
    public init(start: Point, end: Point, stops: [GradientStop]) {
        self.start = start; self.end = end; self.stops = stops
    }
}

public enum Fill: Sendable, Equatable {
    case solid(RGB)
    case linear(LinearGradient)

    /// Representative colour (for swatches).
    public var averageColor: RGB {
        switch self {
        case .solid(let c): return c
        case .linear(let g):
            guard !g.stops.isEmpty else { return RGB(0, 0, 0) }
            return g.stops.map(\.color).reduce(RGB(0, 0, 0), +) * (1 / Double(g.stops.count))
        }
    }
}

public struct VectorLayer: Sendable, Identifiable {
    public let id: Int
    public var path: VectorPath
    public var fill: Fill
    /// Share of the image covered by this colour (its own pixels, not its stacked shape).
    public var coverage: Double
    public var isVisible: Bool = true
}

/// Result of a vectorisation, in the source image's pixel coordinates.
public struct VectorDocument: Sendable {
    public var width: Double
    public var height: Double
    public var layers: [VectorLayer]

    public var visibleLayers: [VectorLayer] { layers.filter(\.isVisible) }
    public var segmentCount: Int { visibleLayers.reduce(0) { $0 + $1.path.segmentCount } }
}
