import Foundation

/// sRGB colour, components 0...1.
public struct RGB: Sendable, Equatable, Hashable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    public var hex: String {
        func c(_ v: Double) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }

    public static func + (a: RGB, b: RGB) -> RGB { RGB(a.r + b.r, a.g + b.g, a.b + b.b) }
    public static func * (a: RGB, k: Double) -> RGB { RGB(a.r * k, a.g * k, a.b * k) }
}

public enum ColorMath {
    @inlinable public static func linear(_ c: Float) -> Float {
        c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    /// sRGB (0...1) → CIE Lab (D65).
    @inlinable public static func lab(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> {
        let R = linear(r), G = linear(g), B = linear(b)
        let x = (0.4124564 * R + 0.3575761 * G + 0.1804375 * B) / 0.95047
        let y = 0.2126729 * R + 0.7151522 * G + 0.0721750 * B
        let z = (0.0193339 * R + 0.1191920 * G + 0.9503041 * B) / 1.08883
        @inline(__always) func f(_ t: Float) -> Float { t > 0.008856 ? cbrtf(t) : 7.787 * t + 16.0 / 116.0 }
        let fx = f(x), fy = f(y), fz = f(z)
        return SIMD3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    public static func lab(_ c: RGB) -> SIMD3<Float> { lab(Float(c.r), Float(c.g), Float(c.b)) }

    /// CIE76 colour difference.
    @inlinable public static func deltaE(_ p: SIMD3<Float>, _ q: SIMD3<Float>) -> Float {
        let d = p - q
        return (d * d).sum().squareRoot()
    }
}
