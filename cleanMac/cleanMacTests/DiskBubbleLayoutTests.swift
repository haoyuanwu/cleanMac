import XCTest
@testable import cleanMac

final class DiskBubbleLayoutTests: XCTestCase {
    func testBubblesFitAndDoNotOverlapAcrossViewportShapes() {
        let weights = (1...18).map { (id: "node-\($0)", size: Int64(1_000_000 / ($0 * $0))) }
        for size in [CGSize(width: 300, height: 500), CGSize(width: 900, height: 400), CGSize(width: 100, height: 100)] {
            let bubbles = DiskBubbleLayout.arrange(weights: weights, in: size)
            XCTAssertEqual(bubbles.count, 18)
            for (index, bubble) in bubbles.enumerated() {
                XCTAssertGreaterThanOrEqual(bubble.center.x - bubble.radius, 0)
                XCTAssertGreaterThanOrEqual(bubble.center.y - bubble.radius, 0)
                XCTAssertLessThanOrEqual(bubble.center.x + bubble.radius, size.width)
                XCTAssertLessThanOrEqual(bubble.center.y + bubble.radius, size.height)
                for other in bubbles.dropFirst(index + 1) {
                    XCTAssertGreaterThanOrEqual(hypot(bubble.center.x - other.center.x, bubble.center.y - other.center.y),
                                               bubble.radius + other.radius - 0.01)
                }
            }
        }
    }

    func testCircleAreasRemainProportionalToFileSizes() throws {
        let bubbles = DiskBubbleLayout.arrange(weights: [("large", 400), ("small", 100)], in: CGSize(width: 500, height: 300))
        let large = try XCTUnwrap(bubbles.first { $0.id == "large" })
        let small = try XCTUnwrap(bubbles.first { $0.id == "small" })
        XCTAssertEqual(pow(large.radius / small.radius, 2), 4, accuracy: 0.001)
    }

    func testEmptyInvalidAndZeroSizedInputs() {
        XCTAssertTrue(DiskBubbleLayout.arrange(weights: [], in: CGSize(width: 300, height: 300)).isEmpty)
        XCTAssertTrue(DiskBubbleLayout.arrange(weights: [("zero", 0), ("negative", -5)], in: CGSize(width: 300, height: 300)).isEmpty)
        XCTAssertTrue(DiskBubbleLayout.arrange(weights: [("file", 50)], in: .zero).isEmpty)
    }

    func testLayoutIsStableWhenInputOrderChanges() {
        let weights: [(id: String, size: Int64)] = [("a", 50), ("b", 50), ("c", 10)]
        let size = CGSize(width: 500, height: 300)
        let first = DiskBubbleLayout.arrange(weights: weights, in: size)
        let second = DiskBubbleLayout.arrange(weights: weights.reversed(), in: size)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.map(\.center), second.map(\.center))
    }
}
