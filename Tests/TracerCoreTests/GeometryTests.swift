import Testing
@testable import TracerCore

@Test func unitSquareAreaIsOne() {
    let sq: [Point] = [Point(0, 0), Point(1, 0), Point(1, 1), Point(0, 1)]
    #expect(abs(signedArea(sq) - 1) < 1e-12)
}
