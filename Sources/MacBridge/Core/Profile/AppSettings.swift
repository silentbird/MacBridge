import Combine
import Foundation

/// Global (non-per-keyboard) feature flags, persisted in UserDefaults.
/// Per-keyboard state lives in `ProfileStore`; per-rule state lives in `RuleStore`.
final class AppSettings: ObservableObject {
    /// Master kill switch for the remap engine. When off, no user-defined
    /// rule fires regardless of its own `enabled` flag.
    @Published var remapEngineEnabled: Bool {
        didSet { defaults.set(remapEngineEnabled, forKey: Self.engineKey) }
    }

    /// Set to `true` once the first-run onboarding wizard has been shown
    /// (whether the user clicked through or Skipped). The wizard checks this
    /// to decide whether the launch is a fresh install or a returning user.
    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Self.onboardingKey) }
    }

    private let defaults: UserDefaults
    private static let engineKey = "feature.remapEngine.enabled"
    private static let onboardingKey = "onboarding.completed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default ON: MacBridge targets Windows migrants, for whom Ctrl+C=Copy
        // is the single biggest pain. Remote-control users (UU/Moonlight/etc.)
        // also rely on this since `hidutil` can't touch injected CGEvents.
        self.remapEngineEnabled = defaults.object(forKey: Self.engineKey) as? Bool ?? true
        self.onboardingCompleted = defaults.object(forKey: Self.onboardingKey) as? Bool ?? false
    }
}
