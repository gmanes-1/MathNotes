import SwiftUI

/// The app's chrome: as the iPad has it, or always light, or always dark. Pages follow it unless paper is kept light.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    static let initial = AppAppearance.system

    static func current(_ defaults: UserDefaults = .standard) -> AppAppearance {
        defaults.string(forKey: SettingsKey.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .initial
    }

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Puts the chosen appearance on every window the app has, each iPad window and what it presents, as each one appears
/// and whenever the setting changes.
@MainActor
final class AppearanceKeeper {
    static let shared = AppearanceKeeper()

    private var observers: [NSObjectProtocol] = []
    private var worn = AppAppearance.initial

    func start() {
        guard observers.isEmpty else { return }
        worn = .current()
        observers.append(NotificationCenter.default.addObserver(forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { AppearanceKeeper.dress(AppearanceKeeper.windows) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            guard Thread.isMainThread else { return DispatchQueue.main.async { self?.settingChanged() } }
            MainActor.assumeIsolated { self?.settingChanged() }
        })
        Self.dress(Self.windows)
    }

    private func settingChanged() {
        let now = AppAppearance.current()
        guard now != worn else { return }
        worn = now
        Self.dress(Self.windows)
    }

    static var windows: [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    }

    static func dress(_ windows: [UIWindow], in appearance: AppAppearance = .current()) {
        for window in windows where window.overrideUserInterfaceStyle != appearance.style {
            window.overrideUserInterfaceStyle = appearance.style
        }
    }
}

extension HorizontalEdge {
    /// The side the page ribbon, the zoom window's buttons and the presenter's panel keep to: the left for a left hand.
    static func editorSide(leftHanded: Bool) -> HorizontalEdge { leftHanded ? .leading : .trailing }

    var edge: Edge { self == .leading ? .leading : .trailing }
    var other: HorizontalEdge { self == .leading ? .trailing : .leading }
    var topCorner: Alignment { self == .leading ? .topLeading : .topTrailing }
    var alignment: HorizontalAlignment { self == .leading ? .leading : .trailing }
}
