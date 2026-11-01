import XCTest
import PencilKit
@testable import OwlLuna

/// Draw and hold: reading a shape out of a wobbly stroke, and redrawing the stroke as that shape.
final class ShapeSnapTests: XCTestCase {
    /// The same wobble every run.
    private func wobble(_ index: Int, _ amount: CGFloat) -> CGPoint {
        CGPoint(x: sin(CGFloat(index) * 12.9898) * amount, y: cos(CGFloat(index) * 78.233) * amount)
    }

    private func along(_ corners: [CGPoint], spacing: CGFloat = 4, wobble amount: CGFloat = 1.5) -> [CGPoint] {
        var points: [CGPoint] = []
        for (a, b) in zip(corners, corners.dropFirst()) {
            let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) / spacing))
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps), jitter = wobble(points.count, amount)
                points.append(CGPoint(x: a.x + (b.x - a.x) * t + jitter.x, y: a.y + (b.y - a.y) * t + jitter.y))
            }
        }
        if let last = corners.last { points.append(last) }
        return points
    }

    private func ellipse(centre: CGPoint, a: CGFloat, b: CGFloat, turned: CGFloat = 0, wobble amount: CGFloat = 1.5, overshoot: CGFloat = 0.1) -> [CGPoint] {
        (0...70).map { index in
            let angle = 0.4 + (2 * .pi + overshoot) * CGFloat(index) / 70, jitter = wobble(index, amount)
            let x = a * cos(angle), y = b * sin(angle)
            return CGPoint(x: centre.x + x * cos(turned) - y * sin(turned) + jitter.x, y: centre.y + x * sin(turned) + y * cos(turned) + jitter.y)
        }
    }

    func testAWobblyLineBecomesStraight() throws {
        let drawn = along([CGPoint(x: 100, y: 200), CGPoint(x: 420, y: 330)])
        guard case .line(let a, let b)? = ShapeRecognizer.recognize(drawn) else { return XCTFail("not read as a line") }
        XCTAssertEqual(a.x, 100, accuracy: 3)
        XCTAssertEqual(b.y, 330, accuracy: 3)

        guard case .line(let left, let right)? = ShapeRecognizer.recognize(along([CGPoint(x: 80, y: 300), CGPoint(x: 400, y: 308)])) else { return XCTFail() }
        XCTAssertEqual(left.y, right.y, "a line drawn nearly level is made level")
        guard case .line(let top, let bottom)? = ShapeRecognizer.recognize(along([CGPoint(x: 200, y: 100), CGPoint(x: 206, y: 500)])) else { return XCTFail() }
        XCTAssertEqual(top.x, bottom.x, "and one drawn nearly upright, upright")
    }

    func testClosedFiguresAreToldApart() throws {
        let square = along([CGPoint(x: 160, y: 100), CGPoint(x: 300, y: 104), CGPoint(x: 296, y: 240), CGPoint(x: 98, y: 236), CGPoint(x: 102, y: 98), CGPoint(x: 150, y: 101)])
        guard case .polygon(let corners)? = ShapeRecognizer.recognize(square) else { return XCTFail("a rectangle started mid-side wasn't read as one") }
        XCTAssertEqual(corners.count, 4)
        XCTAssertEqual(Set(corners.map { $0.x.rounded() }).count, 2, "its sides are made upright")
        XCTAssertEqual(Set(corners.map { $0.y.rounded() }).count, 2, "and level")
        XCTAssertEqual(SnappedShape.polygon(corners).displayName, "rectangle")

        let triangle = along([CGPoint(x: 200, y: 100), CGPoint(x: 320, y: 300), CGPoint(x: 90, y: 290), CGPoint(x: 198, y: 104)])
        guard case .polygon(let three)? = ShapeRecognizer.recognize(triangle) else { return XCTFail("not read as a triangle") }
        XCTAssertEqual(three.count, 3)

        let diamond = along([CGPoint(x: 200, y: 80), CGPoint(x: 330, y: 200), CGPoint(x: 200, y: 320), CGPoint(x: 70, y: 200), CGPoint(x: 198, y: 82)])
        guard case .polygon(let four)? = ShapeRecognizer.recognize(diamond) else { return XCTFail("not read as a diamond") }
        XCTAssertEqual(four.count, 4)
        XCTAssertGreaterThan(Set(four.map { $0.x.rounded() }).count, 2, "a square drawn on its corner stays on its corner")

        guard case .ellipse(let centre, let radii, let rotation)? = ShapeRecognizer.recognize(ellipse(centre: CGPoint(x: 300, y: 300), a: 96, b: 104)) else {
            return XCTFail("not read as a circle")
        }
        XCTAssertEqual(radii.width, radii.height, "nearly round is made round")
        XCTAssertEqual(radii.width, 100, accuracy: 6)
        XCTAssertEqual(centre.x, 300, accuracy: 5)
        XCTAssertEqual(rotation, 0)

        guard case .ellipse(_, let wide, let level)? = ShapeRecognizer.recognize(ellipse(centre: CGPoint(x: 300, y: 300), a: 160, b: 70)) else { return XCTFail() }
        XCTAssertEqual(wide.width, 160, accuracy: 6)
        XCTAssertEqual(wide.height, 70, accuracy: 6)
        XCTAssertEqual(level, 0)

        guard case .ellipse(_, let tilted, let turn)? = ShapeRecognizer.recognize(ellipse(centre: CGPoint(x: 300, y: 300), a: 160, b: 60, turned: 0.6)) else { return XCTFail() }
        XCTAssertEqual(turn, 0.6, accuracy: 0.08, "an ellipse drawn at a slant keeps its slant")
        XCTAssertEqual(tilted.width, 160, accuracy: 10)
    }

    func testOpenCornersAreStraightenedAndHandwritingIsLeftAlone() {
        let corner = along([CGPoint(x: 100, y: 100), CGPoint(x: 104, y: 300), CGPoint(x: 320, y: 296)])
        guard case .polyline(let points)? = ShapeRecognizer.recognize(corner) else { return XCTFail("an L wasn't read as two straight lines") }
        XCTAssertEqual(points.count, 3)

        let arc = (0...40).map { CGPoint(x: 200 + 150 * cos(CGFloat($0) / 40 * .pi), y: 300 - 150 * sin(CGFloat($0) / 40 * .pi)) }
        XCTAssertNil(ShapeRecognizer.recognize(arc), "a curve stays as it was drawn")
        let scribble = (0...120).map { CGPoint(x: 100 + CGFloat($0) * 2 + 40 * sin(CGFloat($0) * 0.9), y: 200 + 60 * sin(CGFloat($0) * 0.37) + 30 * cos(CGFloat($0) * 1.3)) }
        XCTAssertNil(ShapeRecognizer.recognize(scribble))
        XCTAssertNil(ShapeRecognizer.recognize(along([CGPoint(x: 100, y: 100), CGPoint(x: 110, y: 104)])), "a dot or a tick is too small to be a shape")
        XCTAssertNil(ShapeRecognizer.recognize([]))
    }

    private func pencilStroke(_ points: [CGPoint], width: CGFloat = 5) -> PKStroke {
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.01, size: CGSize(width: width, height: width), opacity: 0.9, force: 1, azimuth: 0.3, altitude: 1)
        }, creationDate: date)
        return PKStroke(ink: PKInk(.pen, color: .blue), path: path)
    }

    func testAStrokeIsRedrawnAsItsShape() throws {
        let drawn = pencilStroke(along([CGPoint(x: 100, y: 200), CGPoint(x: 420, y: 330)]))
        let line = try XCTUnwrap(ShapeSnap.snapped(drawn))
        XCTAssertEqual(line.stroke.ink.inkType, .pen)
        XCTAssertEqual(line.stroke.ink.color, drawn.ink.color)
        XCTAssertEqual(line.stroke.path.creationDate, drawn.path.creationDate, "the stroke keeps its place in a recording")
        let sampled = line.stroke.path.interpolatedPoints(by: .distance(5)).map(\.location)
        XCTAssertGreaterThan(sampled.count, 20)
        for point in sampled {
            XCTAssertLessThan(ShapeRecognizer.distance(point, toSegment: CGPoint(x: 100, y: 200), CGPoint(x: 420, y: 330)), 2.5, "every part of it lies on the line")
        }
        XCTAssertEqual(try XCTUnwrap(sampled.first).x, 100, accuracy: 3, "and it runs the whole way")
        XCTAssertEqual(try XCTUnwrap(sampled.last).x, 420, accuracy: 3)
        XCTAssertEqual(try XCTUnwrap(line.stroke.path.first).size.width, 5, accuracy: 0.01, "at the weight it was drawn")

        let square = pencilStroke(along([CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 104), CGPoint(x: 296, y: 300), CGPoint(x: 98, y: 296), CGPoint(x: 101, y: 103)]))
        let box = try XCTUnwrap(ShapeSnap.snapped(square))
        guard case .polygon(let corners) = box.shape else { return XCTFail() }
        let outline = box.stroke.path.interpolatedPoints(by: .distance(2)).map(\.location)
        for corner in corners {
            XCTAssertLessThan(outline.map { ShapeRecognizer.distance($0, corner) }.min() ?? 99, 1.5, "corners stay sharp")
        }

        let ring = pencilStroke(ellipse(centre: CGPoint(x: 300, y: 300), a: 100, b: 100))
        let circle = try XCTUnwrap(ShapeSnap.snapped(ring))
        for point in circle.stroke.path.interpolatedPoints(by: .distance(6)).map(\.location) {
            XCTAssertEqual(ShapeRecognizer.distance(point, CGPoint(x: 300, y: 300)), 100, accuracy: 6)
        }
        XCTAssertNil(ShapeSnap.snapped(pencilStroke((0...40).map { CGPoint(x: 200 + 150 * cos(CGFloat($0) / 40 * .pi), y: 300 - 150 * sin(CGFloat($0) / 40 * .pi)) })))
    }

    private let start = CGPoint(x: 100, y: 300)

    /// Half a second of drawing from `time`, coming to rest at `time + 0.5`.
    private func drag(_ touch: AnyHashable, _ rests: inout TouchRests, from time: TimeInterval) {
        for step in 1...10 { rests.moved(touch, to: CGPoint(x: start.x + 30 * CGFloat(step), y: start.y), time: time + 0.05 * Double(step)) }
    }

    func testTheRestIsTakenFromTheEndOfTheStrokeOnce() throws {
        var rests = TouchRests()
        rests.began("pencil", isPencil: true, fingersDraw: false, at: start, time: 0)
        drag("pencil", &rests, from: 0)
        rests.ended("pencil", time: 1.1)
        XCTAssertTrue(rests.isEmpty)
        XCTAssertEqual(try XCTUnwrap(rests.take(at: 1.15, within: 2)), 0.6, accuracy: 0.001)
        XCTAssertNil(rests.take(at: 1.2, within: 2), "a rest is taken once")

        rests.began("pencil", isPencil: true, fingersDraw: false, at: start, time: 2)
        drag("pencil", &rests, from: 2)
        rests.ended("pencil", time: 2.52)
        XCTAssertNil(rests.take(at: 5, within: 2), "and is forgotten after a while")
    }

    func testAPalmThatLandsFirstDoesNotHideThePencilsRest() throws {
        var rests = TouchRests()
        rests.began("palm", isPencil: false, fingersDraw: false, at: CGPoint(x: 600, y: 700), time: 0)
        rests.began("pencil", isPencil: true, fingersDraw: false, at: start, time: 1)
        drag("pencil", &rests, from: 1)
        rests.ended("pencil", time: 2.1)
        XCTAssertEqual(try XCTUnwrap(rests.take(at: 2.15, within: 2)), 0.6, accuracy: 0.001, "the Pencil's hold is measured though a palm was down first")

        rests.began("pencil", isPencil: true, fingersDraw: false, at: start, time: 3)
        drag("pencil", &rests, from: 3)
        rests.ended("pencil", time: 3.55)
        XCTAssertEqual(try XCTUnwrap(rests.take(at: 3.6, within: 2)), 0.05, accuracy: 0.001, "and so is every stroke after it while the palm rests")
        XCTAssertFalse(rests.isEmpty, "the palm is still down, so the strokes go on being watched")

        rests.ended("palm", time: 4)
        XCTAssertNil(rests.take(at: 4.05, within: 2), "the palm lifting is no stroke")
        XCTAssertTrue(rests.isEmpty)
    }

    func testAThumbLiftingMidStrokeLendsTheStrokeNoRest() throws {
        for fingersDraw in [false, true] {
            var rests = TouchRests()
            rests.began("thumb", isPencil: false, fingersDraw: fingersDraw, at: CGPoint(x: 20, y: 500), time: 0)
            rests.began("pencil", isPencil: true, fingersDraw: fingersDraw, at: start, time: 1)
            rests.ended("thumb", time: 1.2)
            drag("pencil", &rests, from: 1)
            rests.ended("pencil", time: 1.55)
            XCTAssertEqual(try XCTUnwrap(rests.take(at: 1.6, within: 2)), 0.05, accuracy: 0.001, "a quick stroke stays quick: the thumb's long rest isn't its")
        }
    }

    func testAFingerFeedsTheHoldOnlyWhenFingersDraw() throws {
        var rests = TouchRests()
        rests.began("finger", isPencil: false, fingersDraw: false, at: start, time: 0)
        drag("finger", &rests, from: 0)
        rests.ended("finger", time: 1.3)
        XCTAssertNil(rests.take(at: 1.35, within: 2), "with Apple Pencil Only a finger never holds")

        rests.began("finger", isPencil: false, fingersDraw: true, at: start, time: 2)
        drag("finger", &rests, from: 2)
        rests.ended("finger", time: 3.3)
        XCTAssertEqual(try XCTUnwrap(rests.take(at: 3.35, within: 2)), 0.8, accuracy: 0.001, "a finger that draws holds like the Pencil")

        rests.began("pencil", isPencil: true, fingersDraw: true, at: start, time: 4)
        drag("pencil", &rests, from: 4)
        rests.ended("pencil", time: 5.1)
        rests.began("palm", isPencil: false, fingersDraw: true, at: CGPoint(x: 600, y: 700), time: 5.12)
        XCTAssertEqual(try XCTUnwrap(rests.take(at: 5.15, within: 2)), 0.6, accuracy: 0.001, "a palm landing as the Pencil lifts leaves its rest alone")
    }
}
