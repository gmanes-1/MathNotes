import XCTest
import PencilKit
@testable import OwlLuna

/// What the editor keeps in memory: the bitmaps behind items and the laser, and what a memory warning lets go.
@MainActor
final class MemoryTests: XCTestCase {
    private func window() throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        window.isHidden = false
        addTeardownBlock { @MainActor in window.isHidden = true }
        return window
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func warnOfLowMemory() {
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
    }

    func testAPictureHasNothingDrawnBehindItAtAnyZoom() async throws {
        let assets = temporaryRoot(self).url
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 120), format: format).pngData { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
        }
        try png.write(to: assets.appending(path: "photo.png"))
        let item = PageItem(content: .image(file: "photo.png"), center: CGPoint(x: 306, y: 300), size: CGSize(width: 612, height: 459))
        let view = PageItemView(item: item, assets: assets)
        try window().addSubview(view)
        for scale: CGFloat in [1.6, 8] {
            view.layout(scale: scale)
            view.layer.displayIfNeeded()
            XCTAssertNil(view.layer.contents, "no bitmap the size of the picture at \(scale)")
            XCTAssertTrue(view.subviews.isEmpty)
        }
        let picture = try XCTUnwrap(view.layer.sublayers?.first)
        for _ in 0..<100 where picture.contents == nil { await pause(0.05) }
        XCTAssertNotNil(picture.contents, "the picture is shown by its own layer")
        XCTAssertEqual(picture.frame, view.bounds)
        XCTAssertEqual(view.accessibilityLabel, "Picture")
    }

    func testDrawnItemsKeepToAboutAScreenfulOfPixels() throws {
        XCTAssertEqual(PageItemView.drawingScale(for: CGSize(width: 200, height: 200), screen: 2), 2)
        XCTAssertEqual(PageItemView.drawingScale(for: CGSize(width: 3000, height: 120), screen: 2), 2, "a long strip of tape stays sharp")
        XCTAssertEqual(PageItemView.drawingScale(for: CGSize(width: 12000, height: 40), screen: 2), 8192 / 12000, accuracy: 0.0001)
        XCTAssertEqual(PageItemView.drawingScale(for: .zero, screen: 3), 3)

        let window = try window()
        let screen = window.traitCollection.displayScale
        let star = PageItem(content: .sticker("star"), center: CGPoint(x: 306, y: 300), size: CGSize(width: 612, height: 459))
        let view = PageItemView(item: star, assets: FileManager.default.temporaryDirectory)
        view.layout(scale: 1.6)
        window.addSubview(view)
        let art = try XCTUnwrap(view.subviews.first)
        XCTAssertEqual(art.frame, view.bounds)
        XCTAssertEqual(art.contentScaleFactor, screen, "at the size the page shows it, drawn at the screen's scale")
        art.layer.displayIfNeeded()
        XCTAssertNotNil(art.layer.contents)
        XCTAssertNil(view.layer.contents)

        view.layout(scale: 8)
        XCTAssertEqual(art.frame, view.bounds)
        XCTAssertLessThan(art.contentScaleFactor, 1, "enlarged at 5×, fewer pixels than points")
        XCTAssertLessThanOrEqual(art.bounds.width * art.contentScaleFactor * art.bounds.height * art.contentScaleFactor, 2400 * 2400 + 1)
        view.layout(scale: 1.6)
        XCTAssertEqual(art.contentScaleFactor, screen, "and sharp again back at 1×")
    }

    func testTheLaserIsHiddenWithNoTrailAndKeepsNoBitmap() async throws {
        let laser = LaserTrailView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        try window().addSubview(laser)
        XCTAssertTrue(laser.isHidden)
        laser.begin(at: CGPoint(x: 10, y: 10))
        laser.move(to: CGPoint(x: 200, y: 100))
        XCTAssertFalse(laser.isHidden)
        laser.layer.displayIfNeeded()
        XCTAssertNotNil(laser.layer.contents)
        laser.clear()
        XCTAssertTrue(laser.isHidden)
        XCTAssertNil(laser.layer.contents)

        laser.begin(at: CGPoint(x: 10, y: 10))
        laser.move(to: CGPoint(x: 60, y: 40))
        laser.end()
        XCTAssertFalse(laser.isHidden, "the tail fades first")
        for _ in 0..<60 where !laser.isHidden { await pause(0.05) }
        XCTAssertTrue(laser.isHidden, "then the view steps aside")
        XCTAssertNil(laser.layer.contents)
    }

    func testAMemoryWarningEmptiesTheCaches() async {
        let cache = LRUCache<Int>(capacity: 4)
        _ = cache.value("a") { 1 }
        _ = cache.value("b") { 2 }
        XCTAssertEqual(cache.count, 2)
        let request = CoverRequest(notebookID: UUID(), spec: CoverSpec(style: .cloth, cloth: .moss, inks: (.teal, .pink), seed: 9),
                                   title: "Cell Biology", meta: "24 pages", width: 120, scale: 2, dark: false, highContrast: false,
                                   firstPage: nil, firstPageKey: nil, firstPageIsPDF: false)
        let cover = await CoverCache.shared.image(for: request)
        XCTAssertNotNil(cover)
        XCTAssertNotNil(CoverCache.shared.cached(request.key))
        warnOfLowMemory()
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(CoverCache.shared.cached(request.key))
        XCTAssertEqual(cache.value("a") { 3 }, 3, "and fills again as it is used")
    }

    func testAMemoryWarningLetsGoOfSavedInkWithNoCanvas() async throws {
        let root = temporaryRoot(self)
        let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)
        let manifest = NotebookManifest(title: "Memory", defaults: paper, pages: [paper.newPage(), paper.newPage(), paper.newPage()])
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        let ids = document.pages.map(\.id)
        for id in ids { _ = await document.ink(id) }
        document.replaceInk(ids[1], with: PKDrawing(strokes: [stroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 200, y: 80))]))
        document.pinInk([ids[2]])
        document.releaseCleanInk()
        XCTAssertNil(document.loadedInk(ids[0]), "saved, with no canvas: let go")
        XCTAssertEqual(document.loadedInk(ids[1])?.strokes.count, 1, "unsaved ink is kept")
        XCTAssertNotNil(document.loadedInk(ids[2]), "a page with a live canvas is kept")
        let reloaded = await document.ink(ids[0])
        XCTAssertTrue(reloaded.strokes.isEmpty)
        XCTAssertNotNil(document.loadedInk(ids[0]), "and read again when wanted")
    }
}
