import XCTest
import PencilKit
@testable import OwlLuna

/// Replaying a recording with its ink: which strokes belong to it, what is faint at a given moment, and the transport.
@MainActor
final class ReplayTests: XCTestCase {
    private let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func recording(duration: TimeInterval = 20, file: String = "talk.wav") -> RecordingEntry {
        var entry = RecordingEntry(id: UUID(), file: file, createdAt: start.addingTimeInterval(duration), duration: duration)
        entry.startedAt = start
        return entry
    }

    private func stroke(y: CGFloat, at offset: TimeInterval) -> PKStroke {
        ReplaySeed.stroke(y: y, at: start.addingTimeInterval(offset))
    }

    func testOnlyInkWrittenDuringTheRecordingIsOnItsTimeline() {
        let first = UUID(), second = UUID()
        let drawings = [first: PKDrawing(strokes: [stroke(y: 100, at: -60), stroke(y: 200, at: 6), stroke(y: 300, at: 2), stroke(y: 400, at: 900)]),
                        second: PKDrawing(strokes: [stroke(y: 100, at: 14), stroke(y: 200, at: 20.2)])]
        let timeline = ReplayTimeline(recording: recording(), drawings: drawings)
        XCTAssertEqual(timeline.marks.map(\.time), [2, 6, 14, 20], "in the order written; a stroke begun as recording stopped counts at its end")
        XCTAssertEqual(timeline.marks.map(\.stroke), [2, 1, 0, 1])
        XCTAssertTrue(timeline.hasInk(onPage: first))

        XCTAssertEqual(timeline.written(by: 0), 0)
        XCTAssertEqual(timeline.written(by: 6), 2)
        XCTAssertEqual(timeline.written(by: 99), 4)
        XCTAssertEqual(timeline.pending(onPage: first, at: 0), [1, 2], "ink from before or after the recording is never faint")
        XCTAssertEqual(timeline.pending(onPage: first, at: 3), [1])
        XCTAssertEqual(timeline.pending(onPage: first, at: 6), [])
        XCTAssertEqual(timeline.pending(onPage: second, at: 6), [0, 1])
        XCTAssertEqual(timeline.page(at: 0), first, "before any ink, the page the first stroke is on")
        XCTAssertEqual(timeline.page(at: 13.9), first)
        XCTAssertEqual(timeline.page(at: 14), second)
        XCTAssertEqual(timeline.time(ofStroke: 1, onPage: first), 6)
        XCTAssertNil(timeline.time(ofStroke: 0, onPage: first), "a stroke from before the recording has no moment to jump to")
        XCTAssertTrue(ReplayTimeline(recording: recording(), drawings: [first: PKDrawing(strokes: [stroke(y: 100, at: -60)])]).isEmpty)
    }

    func testInkStillToComeIsFaintAndInkUnderATapIsFound() throws {
        let drawing = PKDrawing(strokes: [stroke(y: 100, at: 1), stroke(y: 300, at: 5)])
        let shown = ReplayInk.drawing(drawing, pending: [1])
        XCTAssertEqual(shown.strokes.count, 2, "nothing is removed, so the page keeps its shape")
        XCTAssertEqual(shown.strokes[0].ink.color.cgColor.alpha, 1)
        XCTAssertEqual(Double(shown.strokes[1].ink.color.cgColor.alpha), Double(ReplayInk.faint), accuracy: 0.01)
        XCTAssertEqual(ReplayInk.drawing(drawing, pending: []).strokes.map(\.ink.color), drawing.strokes.map(\.ink.color))

        XCTAssertEqual(ReplayInk.stroke(at: CGPoint(x: 300, y: 304), in: drawing), 1)
        XCTAssertEqual(ReplayInk.stroke(at: CGPoint(x: 300, y: 98), in: drawing), 0)
        XCTAssertNil(ReplayInk.stroke(at: CGPoint(x: 300, y: 200), in: drawing), "a tap between lines of writing finds nothing")
    }

    private func faintness(_ drawing: PKDrawing) -> [Bool] {
        drawing.strokes.map { $0.ink.color.cgColor.alpha < 0.5 }
    }

    func testAPageShowsTheSameInkWhicheverWayTheReplayMoves() {
        let ink = PKDrawing(strokes: (0..<8).map { stroke(y: 60 + CGFloat($0) * 40, at: Double($0)) })
        let order = [2, 0, 5, 1, 7, 3]
        var page = ReplayInk.Page(ink, order: order)
        XCTAssertEqual(page.written, order.count, "it starts from the page as it is")
        var faint: [Int: PKStroke] = [:]
        for written in [0, 3, 6, 2, 2, 5, 0, 4, 1, 6] {
            let shown = page.drawing(written: written)
            XCTAssertEqual(page.written, written)
            XCTAssertEqual(faintness(shown), faintness(ReplayInk.drawing(ink, pending: Set(order.dropFirst(written)))), "\(written) written")
            XCTAssertEqual(shown.strokes.map(\.path.creationDate), ink.strokes.map(\.path.creationDate), "every stroke stays in its place")
            guard #available(iOS 27.0, *) else { continue }
            for (index, stroke) in shown.strokes.enumerated() {
                if order.dropFirst(written).contains(index) {
                    XCTAssertEqual(stroke.id, faint[index]?.id ?? stroke.id, "a stroke still to come is shown by the same faint copy each time")
                    faint[index] = stroke
                } else {
                    XCTAssertEqual(stroke.id, ink.strokes[index].id, "a stroke written is the page's own")
                }
            }
        }
        XCTAssertEqual(page.drawing(written: 99).strokes.count, 8, "a count past the end shows everything written")
        XCTAssertEqual(faintness(page.drawing(written: -1)), faintness(ReplayInk.drawing(ink, pending: Set(order))))
    }

    func testTheCanvasShowsTheSameInkAtEveryMomentScrubbingBackwardsToo() async throws {
        let root = temporaryRoot(self)
        var manifest = NotebookManifest(title: "Talk", defaults: paper, pages: [paper.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        try FileManager.default.createDirectory(at: package.assetsDirectory, withIntermediateDirectories: true)
        try ReplaySeed.silence(seconds: 20).write(to: package.assetURL("talk.wav"))
        var entry = recording()
        entry.inkedPages = manifest.pages.map(\.id)
        manifest.recordings = [entry]
        let ink = PKDrawing(strokes: [stroke(y: 60, at: -30), stroke(y: 100, at: 2), stroke(y: 140, at: 9), stroke(y: 180, at: 4), stroke(y: 220, at: 4),
                                      stroke(y: 260, at: 15), stroke(y: 300, at: 900)])
        _ = try await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: ink]))
        let document = try await NotebookDocument.open(manifest.id, root: root)
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
        for _ in 0..<100 where !(controller.canvas(forPage: 0)?.isLoaded ?? false) { try await Task.sleep(for: .milliseconds(50)) }

        let began = await session.beginReplay(entry)
        XCTAssertTrue(began)
        session.recorder.pause()
        let timeline = try XCTUnwrap(session.replay), page = manifest.pages[0].id
        let canvas = try XCTUnwrap(controller.canvas(forPage: 0))
        for time in [0, 3, 4, 8.9, 20, 16, 9, 4.5, 1, 0, 15, 2] as [TimeInterval] {
            session.showReplay(at: time)
            XCTAssertEqual(faintness(canvas.drawing), faintness(ReplayInk.drawing(ink, pending: timeline.pending(onPage: page, at: time))), "at \(time) s")
            XCTAssertEqual(canvas.drawing.strokes.map(\.path.creationDate), ink.strokes.map(\.path.creationDate))
        }
        session.enter(.writing)
        XCTAssertEqual(faintness(canvas.drawing), Array(repeating: false, count: 7), "the replay over, the page is as it was")
    }

    func testThePageFollowsThePositionSliderWhileTheSoundPlaysOn() async throws {
        let root = temporaryRoot(self)
        var manifest = NotebookManifest(title: "Talk", defaults: paper, pages: [paper.newPage(), paper.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        try FileManager.default.createDirectory(at: package.assetsDirectory, withIntermediateDirectories: true)
        try ReplaySeed.silence(seconds: 20).write(to: package.assetURL("talk.wav"))
        var entry = recording()
        entry.inkedPages = manifest.pages.map(\.id)
        manifest.recordings = [entry]
        let ink = PKDrawing(strokes: [stroke(y: 100, at: 2), stroke(y: 200, at: 6), stroke(y: 300, at: 10)])
        _ = try await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: ink,
                                                                           manifest.pages[1].id: PKDrawing(strokes: [stroke(y: 100, at: 14)])]))
        let document = try await NotebookDocument.open(manifest.id, root: root)
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
        for _ in 0..<100 where !(controller.canvas(forPage: 0)?.isLoaded ?? false) { try await Task.sleep(for: .milliseconds(50)) }

        let began = await session.beginReplay(entry)
        XCTAssertTrue(began)
        XCTAssertFalse(session.recorder.isPaused)
        let timeline = try XCTUnwrap(session.replay), page = manifest.pages[0].id
        let canvas = try XCTUnwrap(controller.canvas(forPage: 0))
        func shows(_ time: TimeInterval) -> Bool {
            faintness(canvas.drawing) == faintness(ReplayInk.drawing(ink, pending: timeline.pending(onPage: page, at: time)))
        }

        session.scrubReplay(to: 7)
        XCTAssertEqual(session.scrubbing, 7)
        XCTAssertTrue(shows(7))
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(shows(7), "the sound's own ticks leave the page where the slider is held")
        session.recorder.onPlaybackTime?(11)
        XCTAssertTrue(shows(7))
        session.recorder.onPlaybackTime?(15)
        XCTAssertEqual(session.currentPage, 0, "nor turn it to where the sound has got to")
        session.scrubReplay(to: 3)
        XCTAssertTrue(shows(3))

        session.seekReplay(to: 3)
        XCTAssertNil(session.scrubbing, "let go, the slider shows the sound again")
        XCTAssertEqual(session.recorder.currentTime, 3, accuracy: 0.01)
        XCTAssertTrue(shows(3))
        session.recorder.onPlaybackTime?(11)
        XCTAssertTrue(shows(11), "and the page follows it")

        session.scrubReplay(to: 5)
        session.enter(.writing)
        XCTAssertNil(session.scrubbing)
        XCTAssertEqual(faintness(canvas.drawing), [false, false, false])
    }

    func testARecordingRemembersWhenItBeganAndWhereItWasWrittenOn() throws {
        let page = UUID()
        var entry = recording(duration: 30)
        entry.inkedPages = [page]
        let decoded = try XCTUnwrap(ManifestCodec.decodeRecording(ManifestCodec.encodeRecording(entry)))
        XCTAssertEqual(decoded.startedAt.timeIntervalSince(start), 0, accuracy: 0.01)
        XCTAssertEqual(decoded.inkedPages, [page])

        let old = RecordingEntry(id: UUID(), file: "old.m4a", createdAt: start.addingTimeInterval(30), duration: 30)
        XCTAssertEqual(old.startedAt, start, "an older entry is taken to have begun its length before it was saved")
        XCTAssertNil(old.inkedPages)
    }

    func testReplayingFollowsTheWritingAndEndsCleanly() async throws {
        let root = temporaryRoot(self)
        var manifest = NotebookManifest(title: "Talk", defaults: paper, pages: [paper.newPage(), paper.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        try FileManager.default.createDirectory(at: package.assetsDirectory, withIntermediateDirectories: true)
        try ReplaySeed.silence(seconds: 20).write(to: package.assetURL("talk.wav"))
        var entry = recording()
        entry.inkedPages = manifest.pages.map(\.id)
        manifest.recordings = [entry]
        _ = try await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: PKDrawing(strokes: [stroke(y: 100, at: 2), stroke(y: 200, at: 6)]),
                                                                           manifest.pages[1].id: PKDrawing(strokes: [stroke(y: 100, at: 14)])]))
        let document = try await NotebookDocument.open(manifest.id, root: root)
        let session = EditorSession(document: document)

        let began = await session.beginReplay(entry)
        XCTAssertTrue(began)
        XCTAssertEqual(session.mode, .replaying)
        XCTAssertEqual(session.replay?.marks.count, 3)
        XCTAssertEqual(session.recorder.playingID, entry.id)
        XCTAssertEqual(session.currentPage, 0)

        session.recorder.pause()
        XCTAssertTrue(session.recorder.isPaused)
        session.seekReplay(to: 15)
        XCTAssertEqual(session.recorder.currentTime, 15, accuracy: 0.01)
        XCTAssertEqual(session.currentPage, 1, "the replay turns to the page being written on")
        session.go(to: 0)
        session.seekReplay(to: 16)
        XCTAssertEqual(session.currentPage, 0, "but leaves you where you went until the writing moves to another page")
        session.seekReplay(to: 3)
        XCTAssertEqual(session.currentPage, 0)
        session.seekReplay(to: 500)
        XCTAssertEqual(session.recorder.currentTime, 20, accuracy: 0.01, "a jump past the end stops at the end")

        session.enter(.writing)
        XCTAssertNil(session.replay)
        XCTAssertNil(session.recorder.playingID, "leaving the replay stops the sound")
        XCTAssertFalse(document.undoManager.canUndo, "replaying changes nothing on the pages")
        XCTAssertEqual(document.loadedInk(manifest.pages[0].id)?.strokes.map(\.ink.color.cgColor.alpha), [1, 1])
    }
}
