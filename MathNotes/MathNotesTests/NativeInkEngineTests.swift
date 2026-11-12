import XCTest
@testable import MathNotes

final class NativeInkEngineTests: XCTestCase {
    func testConstantPenIgnoresForce() {
        XCTAssertEqual(NativeInkGeometry.width(base: 4, force: 0, pressureSensitive: false), 4)
        XCTAssertEqual(NativeInkGeometry.width(base: 4, force: 1, pressureSensitive: false), 4)
    }

    func testFinelinerPressureNeverExceedsSelectedWidth() {
        let maximum: CGFloat = 4
        let light = NativeInkGeometry.width(base: maximum, force: 0, pressureSensitive: true)
        let firm = NativeInkGeometry.width(base: maximum, force: 1, pressureSensitive: true)
        XCTAssertEqual(firm, maximum, accuracy: 0.0001)
        XCTAssertLessThan(light, firm)
        XCTAssertGreaterThan(light, 0)
        XCTAssertLessThanOrEqual(light, maximum)
    }

    func testBothPenModesShareSameMaximumWidth() {
        let selected: CGFloat = 3.25
        XCTAssertEqual(NativeInkGeometry.width(base: selected, force: 1, pressureSensitive: false),
                       NativeInkGeometry.width(base: selected, force: 1, pressureSensitive: true),
                       accuracy: 0.0001)
    }

    func testVectorDocumentRoundTripsThroughCodable() throws {
        let stroke = NativeInkStroke(colorRGBA: 0x123456FF, baseWidth: 2.5,
                                     pressureSensitive: true,
                                     points: [
                                        NativeInkPoint(location: CGPoint(x: 12, y: 18), force: 0.2, time: 1),
                                        NativeInkPoint(location: CGPoint(x: 14, y: 21), force: 0.8, time: 1.01)
                                     ])
        let original = NativeInkDocument(strokes: [stroke])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NativeInkDocument.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.strokes.count, 1)
        XCTAssertEqual(decoded.strokes[0].id, stroke.id)
        XCTAssertEqual(decoded.strokes[0].points.count, 2)
        XCTAssertEqual(decoded.strokes[0].points[1].force, 0.8, accuracy: 0.0001)
    }
}
