import XCTest
import UIKit
@testable import OwlLuna

/// The zoom window's geometry: where it sits on the page and how it moves along a line and down to the next.
final class ZoomWindowTests: XCTestCase {
    private let page = CGSize(width: 600, height: 800)

    private func window(at center: CGPoint = CGPoint(x: 300, y: 400), size: CGSize = CGSize(width: 240, height: 60), lineHeight: CGFloat = 28) -> ZoomWindow {
        ZoomWindow(pageID: UUID(), pageSize: page, center: center, size: size, lineHeight: lineHeight)
    }

    func testItStaysOnThePage() {
        XCTAssertEqual(window().rect, CGRect(x: 180, y: 370, width: 240, height: 60))
        XCTAssertEqual(window(at: CGPoint(x: -50, y: 9000)).rect, CGRect(x: 0, y: 740, width: 240, height: 60), "placed past the edge, it is pulled back in")
        XCTAssertEqual(window(size: CGSize(width: 5000, height: 5000)).rect, CGRect(origin: .zero, size: page), "and it is never larger than the page")
        var moved = window()
        moved.move(to: CGPoint(x: 500, y: 100))
        XCTAssertEqual(moved.rect.origin, CGPoint(x: 360, y: 100))
        XCTAssertEqual(moved.lineStart, 360, "placed by hand, that is where its lines start")
    }

    func testItMovesAlongTheLineThenDownToTheNext() {
        var window = window(at: CGPoint(x: 120, y: 100))
        XCTAssertEqual(window.rect.minX, 0)
        XCTAssertTrue(window.advance())
        XCTAssertEqual(window.rect.minX, 132, "a little over half its width, so what was just written stays in view")
        XCTAssertEqual(window.rect.minY, 70)
        XCTAssertTrue(window.advance())
        XCTAssertTrue(window.advance())
        XCTAssertEqual(window.rect.maxX, 600, "it stops at the edge of the page")
        XCTAssertTrue(window.isAtLineEnd)
        XCTAssertTrue(window.advance())
        XCTAssertEqual(window.rect.origin, CGPoint(x: 0, y: 98), "and from there goes to the start of the next line")

        XCTAssertFalse(window.back(), "at the start of a line there is nowhere back to go")
        window.advance()
        XCTAssertTrue(window.back())
        XCTAssertEqual(window.rect.minX, 0)
    }

    func testItStopsAtTheFootOfThePage() {
        var window = window(at: CGPoint(x: 400, y: 770))
        XCTAssertTrue(window.isAtPageEnd)
        XCTAssertFalse(window.newLine(), "already on the last line and at its start")
        window.advance()
        XCTAssertTrue(window.isAtLineEnd)
        XCTAssertTrue(window.newLine(), "back to where the line started, though it can go no lower")
        XCTAssertEqual(window.rect.origin, CGPoint(x: 280, y: 740))
    }

    func testInkInTheBandOnTheRightMovesItOn() {
        let window = window()
        XCTAssertEqual(window.advanceBand.minX, 348, accuracy: 0.01)
        XCTAssertEqual(window.advanceBand.maxX, 420, accuracy: 0.01, "the last three tenths of the window")
        XCTAssertFalse(window.reachesAdvanceBand(CGRect(x: 200, y: 380, width: 100, height: 30)))
        XCTAssertTrue(window.reachesAdvanceBand(CGRect(x: 300, y: 380, width: 60, height: 30)))
        XCTAssertFalse(window.reachesAdvanceBand(CGRect(x: 360, y: 700, width: 20, height: 20)), "ink written elsewhere on the page doesn't count")
        XCTAssertFalse(window.reachesAdvanceBand(.null))
    }

    func testResizingKeepsItsCornerAndRuledPaperSetsTheLineHeight() {
        var window = window()
        window.resize(to: CGSize(width: 360, height: 90))
        XCTAssertEqual(window.rect, CGRect(x: 180, y: 370, width: 360, height: 90))
        window.resize(to: CGSize(width: 500, height: 90))
        XCTAssertEqual(window.rect.origin.x, 100, "pulled back when the new size would run off the page")
        window.fit(pageSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(window.rect, CGRect(x: 0, y: 210, width: 400, height: 90))

        let narrow = NotebookPage.template(.narrowRuled, color: .white, size: .letter), blank = NotebookPage.template(.blank, color: .white, size: .letter)
        XCTAssertEqual(ZoomWindow.lineHeight(for: narrow, windowHeight: 60), 28 * 612 / 800, accuracy: 0.01)
        XCTAssertEqual(ZoomWindow.lineHeight(for: blank, windowHeight: 60), 30)
    }
}

/// The strip's paper is drawn in pieces off the main thread: wherever the window goes, it must match the page drawn whole.
@MainActor
final class ZoomWindowPaperTests: XCTestCase {
    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func pixels(of size: CGSize, _ draw: (CGContext) -> Void) throws -> [UInt8] {
        let width = Int(size.width * 2), height = Int(size.height * 2)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 2, y: -2)
        draw(context)
        let data = try XCTUnwrap(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
    }

    /// The share of 16-pixel squares whose average colour differs by more than a few levels.
    private func mismatch(_ a: [UInt8], _ b: [UInt8], size: CGSize) -> Double {
        let width = Int(size.width * 2), height = Int(size.height * 2), side = 16
        var differing = 0, squares = 0
        for top in stride(from: 0, through: height - side, by: side) {
            for left in stride(from: 0, through: width - side, by: side) {
                var sums = [0, 0, 0]
                for y in top..<top + side {
                    for x in left..<left + side {
                        let i = (y * width + x) * 4
                        for c in 0..<3 { sums[c] += Int(a[i + c]) - Int(b[i + c]) }
                    }
                }
                squares += 1
                if sums.contains(where: { abs($0) / (side * side) > 12 }) { differing += 1 }
            }
        }
        return Double(differing) / Double(max(squares, 1))
    }

    private func checkStrip(_ controller: PageStackController, page: NotebookPage, document: NotebookDocument, _ label: String) async throws {
        let panel = try XCTUnwrap(controller.view.subviews.lazy.compactMap { $0 as? ZoomWindowPanel }.first)
        for _ in 0..<200 {
            let papers = panel.paper.subviews.compactMap { $0 as? PagePaperView }
            if papers.count == 1, papers[0].isDrawn { break }
            await pause(0.05)
        }
        let papers = panel.paper.subviews.compactMap { $0 as? PagePaperView }
        XCTAssertEqual(papers.count, 1, "\(label): the paper drawn before is gone once the new is in")
        XCTAssertTrue(papers.first?.isDrawn ?? false, "\(label): the strip's paper is drawn")
        let rect = try XCTUnwrap(controller.zoomWindowRect), area = panel.paper.bounds.size
        let strip = Int(area.width * area.height * controller.traitCollection.displayScale * controller.traitCollection.displayScale)
        XCTAssertLessThan(papers.first?.pixelCount ?? 0, strip * 5, "\(label): it holds only the pieces near the window")
        let scale = area.width / rect.width, night = PaperNight.isOn(controller.traitCollection)
        let titles = LinkTitles(pages: document.pages, notebooks: nil), assets = document.package.assetsDirectory
        func whole(at origin: CGPoint) throws -> [UInt8] {
            try pixels(of: area) { context in
                context.translateBy(x: -origin.x * scale, y: -origin.y * scale)
                PageRenderer.drawBackground(page, assets: assets, in: context, size: CGSize(width: page.size.width * scale, height: page.size.height * scale),
                                            links: titles, night: night)
            }
        }
        let shown = try pixels(of: area) { panel.paper.layer.render(in: $0) }
        let expected = try whole(at: rect.origin), off = try whole(at: CGPoint(x: rect.minX + 3, y: rect.minY + 3))
        XCTAssertLessThan(mismatch(shown, expected, size: area), 0.02, "\(label): the strip shows the page where the window is")
        XCTAssertGreaterThan(mismatch(off, expected, size: area), 0.1, "\(label): and a strip three points off would not pass")
    }

    func testTheStripsPaperMatchesThePageOnRulesPDFsPhotosItemsAndAtNight() async throws {
        let darkPaper = UserDefaults.standard.object(forKey: SettingsKey.darkPaper)
        UserDefaults.standard.set(true, forKey: SettingsKey.darkPaper)
        addTeardownBlock { UserDefaults.standard.set(darkPaper, forKey: SettingsKey.darkPaper) }
        let root = temporaryRoot(self)
        let id = try await V2StressFixture.writeBackgrounds(root: root)
        let document = try await NotebookDocument.open(id, root: root)
        let session = EditorSession(document: document)
        let controller = PageStackController(session: session)
        session.canvas = controller
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in window.isHidden = true }
        controller.view.layoutIfNeeded()
        await pause(0.5)

        for (index, name) in ["ruled", "PDF", "photo"].enumerated() {
            session.go(to: index, animated: false)
            await pause(0.3)
            session.setZoomWindow(true)
            let panel = try XCTUnwrap(controller.view.subviews.lazy.compactMap { $0 as? ZoomWindowPanel }.first)
            try await checkStrip(controller, page: document.pages[index], document: document, name)
            panel.onAction?(.forward)
            panel.onAction?(.forward)
            try await checkStrip(controller, page: document.pages[index], document: document, "\(name), moved along")
            panel.onAction?(.newLine)
            panel.onAction?(index == 1 ? .further : .closer)
            try await checkStrip(controller, page: document.pages[index], document: document, "\(name), next line and another zoom")
            session.setZoomWindow(false)
        }

        session.go(to: 0, animated: false)
        await pause(0.3)
        session.setZoomWindow(true)
        let rect = try XCTUnwrap(controller.zoomWindowRect), ruled = document.pages[0].id
        document.updateItems(onPage: ruled, actionName: "Add") { items in
            items.append(PageItem(content: .text(TextBox(string: "Zoom window")), center: CGPoint(x: rect.minX + 70, y: rect.midY), size: CGSize(width: 120, height: 30)))
            items.append(PageItem(content: .link(PageLink(target: ruled)), center: CGPoint(x: rect.maxX - 70, y: rect.midY), size: CGSize(width: 120, height: 36)))
        }
        XCTAssertTrue(document.pages[0].hasItems)
        try await checkStrip(controller, page: document.pages[0], document: document, "with a text box and a link")
        window.overrideUserInterfaceStyle = .dark
        await pause(0.3)
        XCTAssertTrue(PaperNight.isOn(controller.traitCollection))
        try await checkStrip(controller, page: document.pages[0], document: document, "ruled at night")
        session.setZoomWindow(false)
    }
}
