import XCTest
import PDFKit
import PencilKit
@testable import OwlLuna

/// Cropping a picture on a page: the manifest, where the picture stays, undo, and every place a page is drawn.
@MainActor
final class PictureCropTests: XCTestCase {
    private let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)
    private let rightHalf = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
    private let red: [UInt8] = [255, 0, 0], green: [UInt8] = [0, 255, 0], blue: [UInt8] = [0, 0, 255], yellow: [UInt8] = [255, 255, 0]
    private let white: [UInt8] = [255, 255, 255]

    /// 40 by 20 pixels: red then green along the top, blue then yellow along the bottom.
    private func quarters() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).pngData { context in
            for (color, rect) in [(UIColor.red, CGRect(x: 0, y: 0, width: 20, height: 10)), (.green, CGRect(x: 20, y: 0, width: 20, height: 10)),
                                  (.blue, CGRect(x: 0, y: 10, width: 20, height: 10)), (.yellow, CGRect(x: 20, y: 10, width: 20, height: 10))] {
                color.setFill()
                context.fill(rect)
            }
        }
    }

    private func makeDocument() async throws -> NotebookDocument {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Whiteboard", defaults: paper, pages: [paper.newPage()])
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        return try await NotebookDocument.open(manifest.id, root: root)
    }

    /// A 400 by 200 point picture in the middle of a Letter page.
    private func placePicture(in document: NotebookDocument, rotation: CGFloat = 0) async throws -> PageItem {
        let file = try await document.package.writeAsset(quarters(), ext: "png")
        let item = PageItem(content: .image(file: file), center: CGPoint(x: 306, y: 396), size: CGSize(width: 400, height: 200), rotation: rotation)
        document.updateItems(onPage: document.pages[0].id, actionName: "Add to Page") { $0.append(item) }
        return try XCTUnwrap(document.pages[0].items.first)
    }

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

    /// Where a point of the picture, in its unit square, lands on the page.
    private func onPage(_ unit: CGPoint, of item: PageItem) -> CGPoint {
        let crop = item.crop ?? PageItem.wholePicture
        let x = (unit.x - crop.midX) / crop.width * item.size.width, y = (unit.y - crop.midY) / crop.height * item.size.height
        return CGPoint(x: item.center.x + x * cos(item.rotation) - y * sin(item.rotation), y: item.center.y + x * sin(item.rotation) + y * cos(item.rotation))
    }

    private func assertSamePlace(_ a: CGPoint, _ b: CGPoint, _ message: String = "", line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 0.001, message, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 0.001, message, line: line)
    }

    private func pixel(of image: CGImage, at point: CGPoint) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: -point.x.rounded(.down), y: point.y.rounded(.down) - CGFloat(image.height) + 1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(bytes.prefix(3))
    }

    /// What a picture 400 by 200 in the middle of the page shows once cropped to its right half, in an image of the page.
    private func assertShowsTheRightHalf(_ image: CGImage, _ what: String, line: UInt = #line) {
        let factor = CGFloat(image.width) / 612
        func at(_ x: CGFloat, _ y: CGFloat) -> [UInt8] { pixel(of: image, at: CGPoint(x: x * factor, y: y * factor)) }
        XCTAssertEqual(at(406, 340), green, "\(what): the top of what is kept", line: line)
        XCTAssertEqual(at(406, 450), yellow, "\(what): the bottom of what is kept", line: line)
        XCTAssertEqual(at(250, 340), white, "\(what): the part cropped away isn't drawn", line: line)
        XCTAssertEqual(at(250, 450), white, "\(what): the part cropped away isn't drawn", line: line)
        XCTAssertEqual(at(406, 280), white, "\(what): nothing is drawn past the kept part", line: line)
    }

    // MARK: The manifest

    func testACropIsKeptInTheManifestAndAPictureWithoutOneIsUnchanged() throws {
        var page = paper.newPage()
        let plain = PageItem(content: .image(file: "board.jpg"), center: CGPoint(x: 300, y: 400), size: CGSize(width: 200, height: 150))
        let crop = CGRect(x: 0.125, y: 0.25, width: 0.5, height: 0.625)
        page.items = [plain, plain.cropped(to: crop)]
        XCTAssertEqual(Set(page.items[0].json.objectValue.map { Array($0.keys) } ?? []), ["id", "kind", "file", "x", "y", "w", "h", "r"],
                       "a picture without a crop is written as it always was")
        XCTAssertEqual(page.items[1].json["crop"], .array([.number(0.125), .number(0.25), .number(0.5), .number(0.625)]))

        let decoded = try XCTUnwrap(ManifestCodec.decodePage(JSONValue.parse(ManifestCodec.encodePage(page).serialized())))
        XCTAssertNil(decoded.items[0].crop)
        XCTAssertEqual(decoded.items[0].json, plain.json)
        XCTAssertEqual(decoded.items[1].crop, crop)
        XCTAssertEqual(decoded.items[1].size, CGSize(width: 100, height: 93.75))

        var item = decoded.items[1]
        item.crop = PageItem.wholePicture
        XCTAssertNil(item.json["crop"], "all of the picture is no crop at all")
        item.raw["crop"] = .array([.number(-0.5), .number(0.25), .number(3), .number(0.5)])
        XCTAssertEqual(item.crop, CGRect(x: 0, y: 0.25, width: 1, height: 0.5), "cut to the picture")
        for unreadable: JSONValue in [.string("wide"), .array([.number(0.2), .number(0.2), .number(0), .number(0.5)]), .array([.number(0.5)]),
                                      .array([.number(2), .number(2), .number(1), .number(1)])] {
            item.raw["crop"] = unreadable
            XCTAssertNil(item.crop, "\(unreadable) shows the whole picture")
        }
    }

    /// The crop is a key a build reads only as part of the picture's own keys: one that doesn't know it moves or turns
    /// the picture and writes it back as it found it.
    func testTheCropTravelsUntouchedThroughABuildThatOnlyArrangesThePicture() throws {
        let crop: JSONValue = .array([.number(0.25), .number(0), .number(0.5), .number(1)])
        var page = paper.newPage()
        page.extra["items"] = .array([.object(["id": .string(UUID().uuidString), "kind": .string("image"), "file": .string("board.jpg"),
                                               "x": .number(300), "y": .number(400), "w": .number(100), "h": .number(150), "r": .number(0),
                                               "crop": crop, "later": .string("kept too")])])
        let read = try XCTUnwrap(ManifestCodec.decodePage(JSONValue.parse(ManifestCodec.encodePage(page).serialized())))
        var arranged = read
        arranged.items = read.items.map { item in
            var item = item
            item.center.x += 40
            item.rotation = 0.3
            return item.scaled(by: 1.5, limit: 1000)
        }
        let again = try XCTUnwrap(ManifestCodec.decodePage(JSONValue.parse(ManifestCodec.encodePage(arranged).serialized())))
        let entry = try XCTUnwrap(again.extra["items"]?.arrayValue?.first)
        XCTAssertEqual(entry["crop"], crop)
        XCTAssertEqual(entry["later"], .string("kept too"))
        XCTAssertEqual(entry["w"], .number(150))
    }

    // MARK: Where it stays

    func testWhatIsKeptStaysWhereItWasTurnedOrNot() {
        for rotation: CGFloat in [0, 0.6, .pi / 2, -2.2] {
            let item = PageItem(content: .image(file: "board.jpg"), center: CGPoint(x: 300, y: 400), size: CGSize(width: 240, height: 180), rotation: rotation)
            let cropped = item.cropped(to: CGRect(x: 0.1, y: 0.25, width: 0.6, height: 0.5))
            XCTAssertEqual(cropped.size.width, 144, accuracy: 0.001)
            XCTAssertEqual(cropped.size.height, 90, accuracy: 0.001)
            XCTAssertEqual(cropped.rotation, rotation)
            for unit in [CGPoint(x: 0.1, y: 0.25), CGPoint(x: 0.7, y: 0.75), CGPoint(x: 0.4, y: 0.3)] {
                assertSamePlace(onPage(unit, of: cropped), onPage(unit, of: item), "turned \(rotation)")
            }
            let smaller = cropped.cropped(to: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2))
            assertSamePlace(onPage(CGPoint(x: 0.4, y: 0.45), of: smaller), onPage(CGPoint(x: 0.4, y: 0.45), of: item), "a crop of a crop")
            let whole = smaller.cropped(to: nil)
            XCTAssertNil(whole.crop, "and back to the whole picture")
            assertSamePlace(whole.center, item.center)
            XCTAssertEqual(whole.size.width, item.size.width, accuracy: 0.001)
            XCTAssertEqual(whole.size.height, item.size.height, accuracy: 0.001)
        }
        let item = PageItem(content: .image(file: "board.jpg"), center: CGPoint(x: 300, y: 400), size: CGSize(width: 240, height: 180))
        XCTAssertEqual(item.cropped(to: CGRect(x: -0.5, y: 0.5, width: 1, height: 2)).crop, CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
        XCTAssertEqual(item.cropped(to: CGRect(x: 2, y: 2, width: 1, height: 1)), item, "nothing left to show changes nothing")
    }

    func testCropEdgesStayInsideThePictureAndBigEnoughToGrab() {
        let least = CGSize(width: 0.1, height: 0.1), whole = PageItem.wholePicture
        XCTAssertEqual(ItemCropView.moved(whole, edges: [.left, .top], by: CGPoint(x: 0.2, y: 0.3), least: least), CGRect(x: 0.2, y: 0.3, width: 0.8, height: 0.7))
        XCTAssertEqual(ItemCropView.moved(whole, edges: [.right, .bottom], by: CGPoint(x: 0.4, y: 0.4), least: least), whole, "never past the picture")
        let thin = ItemCropView.moved(whole, edges: [.right], by: CGPoint(x: -3, y: 0), least: least)
        XCTAssertEqual(thin.width, 0.1, accuracy: 0.0001, "never thinner than a fingertip")
        XCTAssertEqual(thin.minX, 0)
        XCTAssertEqual(ItemCropView.slid(CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5), by: CGPoint(x: 0.6, y: -0.5)),
                       CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), "slid only as far as the picture goes")
        XCTAssertEqual(PageItemRenderer.pixels(of: CGRect(x: 0.5, y: 0, width: 0.5, height: 1), width: 40, height: 20), CGRect(x: 20, y: 0, width: 20, height: 20))
        XCTAssertEqual(PageItemRenderer.pixels(of: CGRect(x: 0.999, y: 0.999, width: 0.001, height: 0.001), width: 40, height: 20).size, CGSize(width: 1, height: 1))
    }

    // MARK: Undo

    func testACropIsOneUndoStepAndCancelLeavesThePictureAsItWas() async throws {
        let document = try await makeDocument()
        document.undoManager.groupsByEvent = false
        document.undoManager.beginUndoGrouping()
        let placed = try await placePicture(in: document, rotation: 0.4)
        document.undoManager.endUndoGrouping()
        let pageID = document.pages[0].id
        let session = EditorSession(document: document)
        let controller = PageStackController(session: session)
        session.canvas = controller
        let window = try window()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        for _ in 0..<100 where controller.canvas(forPage: 0)?.isLoaded != true { await pause(0.05) }
        controller.select(ItemSelection(pageID: pageID, itemID: placed.id))
        XCTAssertNotNil(session.selection)

        func cropView() -> ItemCropView? {
            var views: [UIView] = [controller.view]
            while !views.isEmpty {
                let view = views.removeFirst()
                if let crop = view as? ItemCropView { return crop }
                views += view.subviews
            }
            return nil
        }
        func edge(_ label: String) throws -> UIAccessibilityElement {
            try XCTUnwrap((XCTUnwrap(cropView()).accessibilityElements as? [UIAccessibilityElement])?.first { $0.accessibilityLabel == label })
        }
        func step(_ change: () -> Void) {
            document.undoManager.beginUndoGrouping()
            change()
            document.undoManager.endUndoGrouping()
        }

        controller.beginCrop()
        XCTAssertEqual(session.crop, PageItem.wholePicture)
        let left = try edge("Left Edge")
        XCTAssertEqual(left.accessibilityValue, "0% cut off")
        for _ in 0..<4 { left.accessibilityIncrement() }
        XCTAssertEqual(left.accessibilityValue, "20% cut off")
        XCTAssertEqual(session.crop?.minX ?? 0, 0.2, accuracy: 0.0001)
        controller.endCrop(keeping: false)
        XCTAssertNil(session.crop)
        XCTAssertNil(cropView())
        XCTAssertEqual(document.pages[0].items, [placed], "Cancel leaves the picture as it was")
        XCTAssertEqual(document.undoManager.undoActionName, "Add to Page")

        controller.beginCrop()
        for _ in 0..<2 { try edge("Left Edge").accessibilityIncrement() }
        for _ in 0..<10 { try edge("Right Edge").accessibilityIncrement() }
        try edge("Top Edge").accessibilityDecrement()
        XCTAssertEqual(try edge("Top Edge").accessibilityValue, "0% cut off", "an edge goes no further out than the picture")
        step { controller.endCrop(keeping: true) }
        XCTAssertEqual(document.undoManager.undoActionName, "Crop")
        let cropped = try XCTUnwrap(document.pages[0].items.first)
        XCTAssertEqual(cropped.crop?.minX ?? 0, 0.1, accuracy: 0.0001)
        XCTAssertEqual(cropped.crop?.maxX ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(cropped.size.width, 160, accuracy: 0.001)
        XCTAssertEqual(cropped.size.height, 200, accuracy: 0.001)
        assertSamePlace(onPage(CGPoint(x: 0.3, y: 0.7), of: cropped), onPage(CGPoint(x: 0.3, y: 0.7), of: placed), "the kept part didn't move")
        XCTAssertEqual(session.selection?.itemID, placed.id, "still selected")

        document.undoManager.undo()
        XCTAssertEqual(document.pages[0].items, [placed])
        XCTAssertEqual(document.undoManager.redoActionName, "Crop")
        document.undoManager.redo()
        XCTAssertEqual(document.pages[0].items, [cropped])

        controller.beginCrop()
        controller.resetCrop()
        XCTAssertEqual(session.crop, PageItem.wholePicture)
        step { controller.endCrop(keeping: true) }
        let whole = try XCTUnwrap(document.pages[0].items.first)
        XCTAssertNil(whole.crop, "back to the whole picture, as one more step")
        assertSamePlace(whole.center, placed.center)
        XCTAssertEqual(whole.size.width, 400, accuracy: 0.001)
        document.undoManager.undo()
        XCTAssertEqual(document.pages[0].items, [cropped])

        controller.beginCrop()
        try edge("Bottom Edge").accessibilityIncrement()
        step { controller.select(nil) }
        XCTAssertEqual(document.pages[0].items.first?.crop?.maxY ?? 0, 0.95, accuracy: 0.0001, "putting the picture down keeps the crop")
        XCTAssertNil(session.crop)

        controller.select(ItemSelection(pageID: pageID, itemID: placed.id))
        controller.beginCrop()
        try edge("Top Edge").accessibilityIncrement()
        document.undoManager.undo()
        XCTAssertNil(session.crop, "a picture changed under the crop leaves crop mode")
        XCTAssertNil(cropView())
        XCTAssertEqual(document.pages[0].items, [cropped])
    }

    func testADuplicateKeepsItsCropAndAStickerIsPlacedAgainWhole() async throws {
        let document = try await makeDocument()
        let placed = try await placePicture(in: document)
        document.updateItems(onPage: document.pages[0].id, actionName: "Crop") { $0[0] = $0[0].cropped(to: self.rightHalf) }
        let session = EditorSession(document: document)
        session.selection = ItemSelection(pageID: document.pages[0].id, itemID: placed.id)
        session.duplicateSelection()
        XCTAssertEqual(document.pages[0].items.map(\.crop), [rightHalf, rightHalf])
        XCTAssertEqual(document.pages[0].items[1].size, document.pages[0].items[0].size)
        XCTAssertEqual(document.pages[0].items[0].cropped(to: nil).size, CGSize(width: 400, height: 200), "the shape a sticker is placed again in")
    }

    // MARK: Drawing it

    func testEveryDrawingOfThePageShowsOnlyTheCrop() async throws {
        let document = try await makeDocument()
        _ = try await placePicture(in: document)
        let before = document.pages[0].appearanceKey
        document.updateItems(onPage: document.pages[0].id, actionName: "Crop") { $0[0] = $0[0].cropped(to: self.rightHalf) }
        let page = document.pages[0], assets = document.package.assetsDirectory
        XCTAssertNotEqual(page.appearanceKey, before, "a thumbnail or a second screen's slide made before the crop isn't served after it")
        XCTAssertEqual(page.items[0].center, CGPoint(x: 406, y: 396))

        let thumbnail = try XCTUnwrap(PageThumbnailer.render(page: page, ink: PKDrawing(), assets: assets).cgImage)
        assertShowsTheRightHalf(thumbnail, "thumbnail")
        let slide = try XCTUnwrap(PageRenderer.image(of: page, ink: PKDrawing(), assets: assets, width: 1224).cgImage)
        assertShowsTheRightHalf(slide, "second screen and presenter view")
        let strip = try XCTUnwrap(PagePaperView.image(of: page, assets: assets, unit: 1, density: 1, pixels: CGRect(x: 0, y: 0, width: 612, height: 792), items: true))
        assertShowsTheRightHalf(strip, "zoom window")

        let input = NotebookExporter.Input(title: "Whiteboard", pages: [page], inMemoryInk: [:], package: document.package)
        let images = try await NotebookExporter.exportImages(input) { _ in }
        addTeardownBlock { try? FileManager.default.removeItem(at: images[0].deletingLastPathComponent()) }
        assertShowsTheRightHalf(try XCTUnwrap(UIImage(contentsOfFile: images[0].path(percentEncoded: false))?.cgImage), "image export")

        let pdf = try await NotebookExporter.export(input) { _ in }
        addTeardownBlock { try? FileManager.default.removeItem(at: pdf.deletingLastPathComponent()) }
        let exported = try XCTUnwrap(PDFDocument(url: pdf)?.page(at: 0)?.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox).cgImage)
        assertShowsTheRightHalf(exported, "PDF export")
        let reader = try XCTUnwrap(CGPDFDocument(pdf as CFURL))
        let pdfPage = try XCTUnwrap(reader.page(at: 1)?.dictionary)
        XCTAssertEqual(imageWidths(in: pdfPage), [20], "the PDF carries only the kept half of the picture")
    }

    func testTheEditorShowsTheCropFromThePicturesOwnPixels() async throws {
        let assets = temporaryRoot(self).url
        try quarters().write(to: assets.appending(path: "board.png"))
        let item = PageItem(content: .image(file: "board.png"), center: CGPoint(x: 200, y: 200), size: CGSize(width: 200, height: 100)).cropped(to: rightHalf)
        let view = PageItemView(item: item, assets: assets)
        try window().addSubview(view)
        view.layout(scale: 4)
        let picture = try XCTUnwrap(view.layer.sublayers?.first)
        for _ in 0..<100 where picture.contents == nil { await pause(0.05) }
        XCTAssertEqual(picture.contentsRect, rightHalf)
        XCTAssertEqual((picture.contents as! CGImage).width, 40, "the file's own pixels at any zoom, not a smaller copy")
        XCTAssertNil(view.layer.contents)
        XCTAssertEqual(view.bounds.size, CGSize(width: 400, height: 400))

        view.transform = .identity
        let shown = try XCTUnwrap(UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }.cgImage)
        let scale = CGFloat(shown.width) / 400
        XCTAssertEqual(pixel(of: shown, at: CGPoint(x: 100 * scale, y: 100 * scale)), green, "the top of the right half, the right way up")
        XCTAssertEqual(pixel(of: shown, at: CGPoint(x: 300 * scale, y: 300 * scale)), yellow)

        var whole = item
        whole.crop = nil
        view.update(whole)
        view.layout(scale: 4)
        XCTAssertEqual(picture.contentsRect, PageItem.wholePicture, "and all of it once the crop is taken off")
    }

    /// The pixel widths of the pictures a PDF page's resources hold, looking inside any forms.
    private func imageWidths(in dictionary: CGPDFDictionaryRef) -> [Int] {
        var resources: CGPDFDictionaryRef?, objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
              CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return [] }
        var widths: [Int] = []
        CGPDFDictionaryApplyBlock(objects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let info = CGPDFStreamGetDictionary(stream) else { return true }
            var subtype: UnsafePointer<CChar>?, width: CGPDFInteger = 0
            if CGPDFDictionaryGetName(info, "Subtype", &subtype), let subtype, String(cString: subtype) == "Image" {
                if CGPDFDictionaryGetInteger(info, "Width", &width) { widths.append(width) }
            } else {
                widths += self.imageWidths(in: info)
            }
            return true
        }, nil)
        return widths
    }
}
