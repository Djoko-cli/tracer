import Foundation

/// A scalar field sampled at pixel centres (row-major, y down).
public struct Field: Sendable {
    public let width: Int
    public let height: Int
    public var values: [Float]

    public init(width: Int, height: Int, values: [Float]) {
        precondition(values.count == width * height)
        self.width = width; self.height = height; self.values = values
    }

    public init(width: Int, height: Int, fill: Float = 0) {
        self.init(width: width, height: height, values: Array(repeating: fill, count: width * height))
    }

    @inlinable public subscript(x: Int, y: Int) -> Float {
        get { values[y * width + x] }
        set { values[y * width + x] = newValue }
    }

    /// Separable Gaussian blur. `sigma` in pixels; the border is replicated, so a shape touching
    /// the image edge keeps its edge exactly there.
    public func blurred(sigma: Double) -> Field {
        guard sigma > 0.05 else { return self }
        let r = max(1, Int((3 * sigma).rounded(.up)))
        var k = [Float](repeating: 0, count: 2 * r + 1)
        var sum: Float = 0
        for i in -r...r {
            let v = Float(exp(-Double(i * i) / (2 * sigma * sigma)))
            k[i + r] = v; sum += v
        }
        for i in k.indices { k[i] /= sum }
        var tmp = [Float](repeating: 0, count: values.count)
        var out = [Float](repeating: 0, count: values.count)
        let w = width, h = height
        values.withUnsafeBufferPointer { src in
            tmp.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    let row = y * w
                    for x in 0..<w {
                        var acc: Float = 0
                        for i in -r...r {
                            let xx = min(max(x + i, 0), w - 1)      // replicate the border
                            acc += src[row + xx] * k[i + r]
                        }
                        dst[row + x] = acc
                    }
                }
            }
        }
        tmp.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    for x in 0..<w {
                        var acc: Float = 0
                        for i in -r...r {
                            let yy = min(max(y + i, 0), h - 1)      // replicate the border
                            acc += src[yy * w + x] * k[i + r]
                        }
                        dst[y * w + x] = acc
                    }
                }
            }
        }
        return Field(width: w, height: h, values: out)
    }
}
