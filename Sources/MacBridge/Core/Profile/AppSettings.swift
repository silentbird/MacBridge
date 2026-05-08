import Combine
import Foundation

/// Global (non-per-keyboard) feature flags, persisted in UserDefaults.
/// Per-keyboard state lives in `ProfileStore`.
final class AppSettings: ObservableObject {
    @Published var ctrlSemanticEnabled: Bool {
        didSet { defaults.set(ctrlSemanticEnabled, forKey: Self.ctrlKey) }
    }

    private let defaults: UserDefaults
    private static let ctrlKey = "feature.ctrlSemantic.enabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default ON: MacBridge targets Windows migrants, for whom Ctrl+C=Copy
        // is the single biggest pain. Remote-control users (UU/Moonlight/etc.)
        // also rely on this since `hidutil` can't touch injected CGEvents.
        self.ctrlSemanticEnabled = defaults.object(forKey: Self.ctrlKey) as? Bool ?? true
    }
}
