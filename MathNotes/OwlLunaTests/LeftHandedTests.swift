import XCTest
import SwiftUI
@testable import OwlLuna

/// What keeps to one side of the editor goes to the left for a left hand; the page and its writing stay as they are.
@MainActor
final class LeftHandedTests: XCTestCase {
    private func find(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        return view.subviews.lazy.compactMap { self.find(identifier, in: $0) }.first
    }

    func testTheEditorsSideFollowsTheWritingHand() {
        XCTAssertEqual(HorizontalEdge.editorSide(leftHanded: false), .trailing)
        XCTAssertEqual(HorizontalEdge.editorSide(leftHanded: true), .leading)
        XCTAssertEqual(HorizontalEdge.trailing.topCorner, .topTrailing, "the ribbons hang from the top right")
        XCTAssertEqual(HorizontalEdge.leading.topCorner, .topLeading, "or the top left")
        XCTAssertEqual(HorizontalEdge.leading.edge, .leading, "and a panel slides in from that side")
        XCTAssertEqual(HorizontalEdge.leading.other.alignment, .trailing, "with its rule on the page's side")
        XCTAssertEqual(HorizontalEdge.trailing.other.alignment, .leading)
    }

    func testTheZoomWindowsButtonsGoToTheLeftAndItsBandStaysWhereLinesEnd() throws {
        let panel = ZoomWindowPanel(frame: CGRect(x: 0, y: 0, width: 834, height: 240))
        panel.setTitle("Page 1")
        func frames() throws -> [String: CGRect] {
            panel.setNeedsLayout()
            panel.layoutIfNeeded()
            var result: [String: CGRect] = [:]
            for id in ["zoom.title", "zoom.close", "zoom.back", "zoom.further"] {
                let view = try XCTUnwrap(find(id, in: panel), id)
                result[id] = view.convert(view.bounds, to: panel)
            }
            return result
        }
        let band = try XCTUnwrap(panel.canvasArea.subviews.last)

        let right = try frames()
        XCTAssertLessThan(try XCTUnwrap(right["zoom.title"]).maxX, try XCTUnwrap(right["zoom.back"]).minX)
        XCTAssertGreaterThan(try XCTUnwrap(right["zoom.close"]).maxX, panel.bounds.width - 60, "close at the right edge")
        XCTAssertEqual(band.frame.minX, panel.bounds.width * ZoomWindow.advanceZone, accuracy: 0.5)

        panel.isLeftHanded = true
        let left = try frames()
        XCTAssertLessThan(try XCTUnwrap(left["zoom.close"]).minX, 60, "close at the left edge")
        XCTAssertLessThan(try XCTUnwrap(left["zoom.close"]).maxX, try XCTUnwrap(left["zoom.back"]).minX)
        XCTAssertLessThan(try XCTUnwrap(left["zoom.back"]).maxX, try XCTUnwrap(left["zoom.further"]).minX, "the buttons keep their order")
        XCTAssertLessThan(try XCTUnwrap(left["zoom.further"]).maxX, try XCTUnwrap(left["zoom.title"]).minX, "and the title takes the rest")
        XCTAssertEqual(band.frame.minX, panel.bounds.width * ZoomWindow.advanceZone, accuracy: 0.5,
                       "writing still runs left to right, so the band that moves the window on stays on the right")

        panel.isLeftHanded = false
        let back = try frames()
        XCTAssertEqual(back["zoom.close"], right["zoom.close"])
        XCTAssertEqual(back["zoom.title"], right["zoom.title"])
    }
}
