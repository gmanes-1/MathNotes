import XCTest
import PencilKit
@testable import OwlLuna

/// Light, dark or the iPad's own for the chrome, and paper that goes dark with it unless it is kept light.
@MainActor
final class AppearanceTests: XCTestCase {
    private func ownSettings() throws -> UserDefaults {
        let suite = "owlluna-tests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// How light a pixel of an image is, counted from its top left.
    private func luminance(_ image: CGImage, at point: CGPoint) -> CGFloat {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: -point.x.rounded(), y: -(CGFloat(image.height) - 1 - point.y.rounded()))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (0.299 * CGFloat(pixel[0]) + 0.587 * CGFloat(pixel[1]) + 0.114 * CGFloat(pixel[2])) / 255
    }

    private func window() throws -> (UIWindow, UIViewController) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene), host = UIViewController()
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        window.rootViewController = host
        window.isHidden = false
        addTeardownBlock { @MainActor in window.isHidden = true }
        return (window, host)
    }

    func testEachAppearanceIsTheStyleEveryWindowWears() async throws {
        let defaults = try ownSettings()
        XCTAssertEqual(AppAppearance.current(defaults), .system, "the iPad's own until it is changed")
        defaults.set("dark", forKey: SettingsKey.appearance)
        XCTAssertEqual(AppAppearance.current(defaults), .dark)
        defaults.set("sepia", forKey: SettingsKey.appearance)
        XCTAssertEqual(AppAppearance.current(defaults), .system, "a value this build doesn't know is the iPad's own")
        XCTAssertEqual(AppAppearance.allCases.map(\.style), [.unspecified, .light, .dark])

        let (window, host) = try window()
        let scene = try XCTUnwrap(window.windowScene)
        AppearanceKeeper.dress([window], in: .dark)
        await pause(0.1)
        XCTAssertEqual(host.traitCollection.userInterfaceStyle, .dark)
        AppearanceKeeper.dress([window], in: .light)
        await pause(0.1)
        XCTAssertEqual(host.traitCollection.userInterfaceStyle, .light)
        AppearanceKeeper.dress([window], in: .system)
        await pause(0.1)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .unspecified)
        XCTAssertEqual(host.traitCollection.userInterfaceStyle, scene.traitCollection.userInterfaceStyle, "System is what the iPad has")
    }

    func testChangingTheSettingDressesEveryWindowTheAppHas() async throws {
        let saved = UserDefaults.standard.object(forKey: SettingsKey.appearance)
        addTeardownBlock { UserDefaults.standard.set(saved, forKey: SettingsKey.appearance) }
        let (first, _) = try window(), (second, _) = try window()
        UserDefaults.standard.set(AppAppearance.dark.rawValue, forKey: SettingsKey.appearance)
        await pause(0.1)
        XCTAssertEqual([first, second].map(\.overrideUserInterfaceStyle), [.dark, .dark])
        XCTAssertTrue(AppearanceKeeper.windows.allSatisfy { $0.overrideUserInterfaceStyle == .dark })

        let (third, _) = try window()
        XCTAssertEqual(third.overrideUserInterfaceStyle, .dark, "a window that appears afterwards wears it too")
        UserDefaults.standard.set(AppAppearance.system.rawValue, forKey: SettingsKey.appearance)
        await pause(0.1)
        XCTAssertEqual([first, second, third].map(\.overrideUserInterfaceStyle), [.unspecified, .unspecified, .unspecified])
    }

    func testLightPaperGoesDarkWithTheAppUnlessItIsKeptLight() throws {
        let defaults = try ownSettings()
        let dark = UITraitCollection(userInterfaceStyle: .dark), light = UITraitCollection(userInterfaceStyle: .light)
        let page = NotebookPage.template(.narrowRuled, color: .white, size: .letter)
        XCTAssertTrue(PaperNight.isOn(dark, defaults: defaults), "paper goes dark in Dark Mode until it is kept light")
        XCTAssertFalse(PaperNight.isOn(light, defaults: defaults))
        XCTAssertEqual(page.inkAppearance(night: PaperNight.isOn(dark, defaults: defaults)), .dark)

        // Keep Paper Light is the same setting, the other way about.
        defaults.set(false, forKey: SettingsKey.darkPaper)
        let night = PaperNight.isOn(dark, defaults: defaults)
        XCTAssertFalse(night)
        XCTAssertFalse(page.turnsDark(night))
        XCTAssertEqual(page.inkAppearance(night: night), .light, "ink is drawn as it is on light paper")
        XCTAssertEqual(page.paperShown(night: night), PageRenderer.paperColor(.white))
        XCTAssertEqual(TemplateInk.for(page.paperColor, night: page.turnsDark(night)).line, TemplateInk.for(.white).line, "and the template is ruled for it")
        let chalk = NotebookPage.template(.blank, color: .chalkboard, size: .letter)
        XCTAssertEqual(chalk.inkAppearance(night: night), .dark, "dark paper is as it always is")
    }

    func testAnExportIsThePageAsItIsWhateverTheSettings() async throws {
        let saved = [SettingsKey.appearance, SettingsKey.darkPaper].map { ($0, UserDefaults.standard.object(forKey: $0)) }
        addTeardownBlock { for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) } }
        let drawing = PKDrawing(strokes: [stroke(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 400, y: 300), width: 10)])
        let root = temporaryRoot(self), id = UUID()
        let package = NotebookPackage(root: root, id: id)
        let page = NotebookPage.template(.blank, color: .white, size: .letter)
        try await package.create(NotebookManifest(id: id, title: "Night", defaults: PageDefaults(template: .blank, paperColor: .white, pageSize: .letter),
                                                  pages: [page]))
        let input = NotebookExporter.Input(title: "Night", pages: [page], inMemoryInk: [page.id: drawing], package: package)
        var exported: [Data] = []
        for (appearance, darkPaper) in [(AppAppearance.dark, true), (.dark, false), (.light, true)] {
            UserDefaults.standard.set(appearance.rawValue, forKey: SettingsKey.appearance)
            UserDefaults.standard.set(darkPaper, forKey: SettingsKey.darkPaper)
            let urls = try await NotebookExporter.exportImages(input) { _ in }
            let image = try XCTUnwrap(UIImage(contentsOfFile: try XCTUnwrap(urls.first).path(percentEncoded: false))?.cgImage)
            let k = CGFloat(image.width) / page.size.width
            XCTAssertGreaterThan(luminance(image, at: CGPoint(x: 250 * k, y: 610 * k)), 0.9, "\(appearance), dark paper \(darkPaper): white paper is exported white")
            XCTAssertLessThan(luminance(image, at: CGPoint(x: 250 * k, y: 300 * k)), 0.3, "and its ink dark")
            exported.append(try XCTUnwrap(UIImage(cgImage: image).pngData()))
            ExportFolder.discard(urls)
        }
        XCTAssertEqual(Set(exported).count, 1, "the same page every time")
    }
}
