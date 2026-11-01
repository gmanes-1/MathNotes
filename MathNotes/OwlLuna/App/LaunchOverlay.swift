import SwiftUI

/// Whether the splash plays at launch: never under tests, and only for the first scene of the process.
enum LaunchAnimation {
    @MainActor private static var claimed = false

    #if DEBUG
    static func isEnabled(arguments: [String], underTest: Bool, firstScene: Bool) -> Bool {
        firstScene && !underTest && !arguments.contains("-storageRoot") && !arguments.contains("-skipLaunchAnimation")
    }
    #endif

    /// True once per process; a second window starts with the library as it is.
    @MainActor static var isEnabled: Bool {
        let first = !claimed
        claimed = true
        #if DEBUG
        return isEnabled(arguments: LaunchOptions.arguments, underTest: NSClassFromString("XCTestCase") != nil, firstScene: first)
        #else
        return first
        #endif
    }
}

/// The splash as the library under it knows it. Nothing is shown from under the splash:
/// whatever is waiting asks, which sends the splash away at once.
@MainActor @Observable
final class LaunchCurtain {
    var isUp = false
    private(set) var isHurried = false

    func hurry() { isHurried = true }

    /// Returns whether the splash is still up, and hurries it away if so.
    func holds() -> Bool {
        if isUp { hurry() }
        return isUp
    }
}

/// The MathNotes splash: the mark fades in, is held briefly, then fades away to Home.
struct LaunchOverlay: View {
    let isReady: Bool
    var isHurried = false
    let onHandOver: () -> Void
    let onFinished: () -> Void

    // Constants used by MathNotesApp.swift to settle the library underneath.
    static let libraryStart: CGFloat = 1.05
    static let settle = Animation.timingCurve(0.45, 0, 0.15, 1, duration: 0.5)
    static let stillFade = 0.35

    private static let appearDuration = 0.45
    private static let minimumHold = 0.9
    private static let maximumHold = 2.0

    // Notebook only (transparent PNG).
    private static let icon = UIImage(named: "LaunchIcon")

    // Background color read from the original icon, so the two always match.
    // Sample point as a fraction of the image (0...1). Move it if your artwork has a vignette there.
    private static let background: Color = {
        UIImage(named: "LaunchBackgroundSource")?.pixelColor(atX: 0.04, y: 0.04)
            ?? Color(hex: 0xF1EDE4)
    }()

    @State private var iconShown = false
    @State private var holdElapsed = false
    @State private var holdExpired = false
    @State private var hasStartedExit = false
    @State private var hasFinished = false

    private var shouldExit: Bool {
        isHurried || holdExpired || (holdElapsed && isReady)
    }

    var body: some View {
        ZStack {
            Self.background.ignoresSafeArea()

            if let uiImage = Self.icon {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .opacity(iconShown ? 1 : 0)
                    .scaleEffect(iconShown ? 1 : 0.94)
            } else {
                Text(verbatim: "MathNotes")
                    .displayFont(34, relativeTo: .largeTitle)
                    .foregroundStyle(Color.ink)
                    .opacity(iconShown ? 1 : 0)
            }
        }
        .opacity(hasFinished ? 0 : 1)
        .animation(.easeInOut(duration: Self.stillFade), value: hasFinished)
        .allowsHitTesting(!hasFinished)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MathNotes")
        .accessibilityAddTraits(.isImage)
        .onAppear {
            withAnimation(.easeOut(duration: Self.appearDuration)) {
                iconShown = true
            }
        }
        .task {
            do {
                try await Task.sleep(for: .seconds(Self.minimumHold))
                holdElapsed = true
                try await Task.sleep(for: .seconds(Self.maximumHold - Self.minimumHold))
                holdExpired = true
            } catch {
                // View went away; nothing to do.
            }
        }
        .onChange(of: shouldExit, initial: true) { _, newValue in
            if newValue { beginExit() }
        }
    }

    private func beginExit() {
        guard !hasStartedExit else { return }
        hasStartedExit = true
        hasFinished = true
        onHandOver()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.stillFade))
            onFinished()
        }
    }
}

private extension UIImage {
    /// Color of one pixel, given as a fraction of the image size, converted to sRGB.
    func pixelColor(atX fx: CGFloat, y fy: CGFloat) -> Color? {
        guard let cg = cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let x = min(max(Int(CGFloat(cg.width) * fx), 0), cg.width - 1)
        let y = min(max(Int(CGFloat(cg.height) * fy), 0), cg.height - 1)
        guard let pixel = cg.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }

        var rgba = [UInt8](repeating: 0, count: 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn, rgba[3] > 0 else { return nil }

        return Color(.sRGB,
                     red: Double(rgba[0]) / 255,
                     green: Double(rgba[1]) / 255,
                     blue: Double(rgba[2]) / 255)
    }
}
