import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` (macOS 13+) so SwiftUI can
/// bind to a reactive `isEnabled` + `lastError`. The OS owns the actual
/// "login item" state; this class just reflects it and passes through
/// register/unregister calls.
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var lastError: String?

    init() {
        refresh()
    }

    /// Re-read current state from the OS. Useful after the user toggles
    /// login items in System Settings — they may change it behind our back.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            // Common failures: bundle not signed in a way the OS recognizes
            // (ad-hoc with unstable hash), or user blocked login items via
            // MDM. Surface the reason in the menu so it isn't silent.
            lastError = "\(error.localizedDescription)"
            NSLog("MacBridge: launch-at-login toggle failed: %@", String(describing: error))
        }
        refresh()
    }
}
