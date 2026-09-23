import Foundation

public enum PathElement: Sendable, Equatable {
    case move(Point)
    case line(Point)
    case cubic(Point, Point, Point)
    case close
}

/// A (possibly compound) vector path. Holes are handled with the even-odd rule.
public struct VectorPath: Sendable, Equatable {
    public var elements: [PathElement] = []
    public init(elements: [PathElement] = []) { self.elements = elements }

    public var segmentCount: Int {
        elements.reduce(0) { n, e in
            switch e { case .line, .cubic: return n + 1; default: return n }
        }
    }

    public func transformed(scale s: Double, offset o: Point = .zero) -> VectorPath {
        VectorPath(elements: elements.map {
            switch $0 {
            case .move(let p): return .move(p * s + o)
            case .line(let p): return .line(p * s + o)
            case .cubic(let a, let b, let c): return .cubic(a * s + o, b * s + o, c * s + o)
            case .close: return .close
            }
        })
    }
}
