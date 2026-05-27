import AppKit
import Combine
import Foundation

/// The three macOS permissions MacBridge needs. Each is gated by a separate
/// TCC pane, so the wizard surfaces them as three separate Grant rows.
enum PermissionKind: CaseIterable, Hashable {
    case accessibility
    case inputMonitoring
    case postEvents
}

/// Snapshot of the three permission preflights at a given moment. Refreshed
/// by `OnboardingState`'s polling timer because TCC does not emit any
/// notification when the user toggles a checkbox in System Settings.
struct PermissionSnapshot: Equatable {
    var accessibility: Bool
    var inputMonitoring: Bool
    var postEvents: Bool

    var allGranted: Bool { accessibility && inputMonitoring && postEvents }

    func granted(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility:    return accessibility
        case .inputMonitoring:  return inputMonitoring
        case .postEvents:       return postEvents
        }
    }
}

/// The three closures `OnboardingState` calls to learn the current TCC state.
/// Production wires these to `AccessibilityPermission`; tests inject stubs.
struct PermissionProbe {
    var accessibility: () -> Bool
    var inputMonitoring: () -> Bool
    var postEvents: () -> Bool

    static let live = PermissionProbe(
        accessibility:   { AccessibilityPermission.isTrusted() },
        inputMonitoring: { AccessibilityPermission.canListenToInput() },
        postEvents:      { AccessibilityPermission.canPostEvents() }
    )
}

/// What page the wizard is on. Order is fixed; users move via Back / Next.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case keyboards

    var title: String {
        switch self {
        case .welcome:     return "Welcome"
        case .permissions: return "System permissions"
        case .keyboards:   return "Your keyboards"
        }
    }
}

/// Owns onboarding's runtime state: which step is showing, the latest
/// permission snapshot, and the completion flag in `AppSettings`.
final class OnboardingState: ObservableObject {
    @Published var currentStep: OnboardingStep
    @Published private(set) var permissionStatus: PermissionSnapshot

    private let settings: AppSettings
    private let probe: PermissionProbe
    private var timerCancellable: AnyCancellable?

    init(settings: AppSettings, probe: PermissionProbe = .live) {
        self.settings = settings
        self.probe = probe
        self.permissionStatus = Self.snapshot(probe)
        // Returning users with a missing permission jump straight to the
        // page that can fix it — there is no point making them re-read the
        // welcome blurb every launch.
        self.currentStep = settings.onboardingCompleted ? .permissions : .welcome
    }

    /// True when launching should auto-present the wizard: either the user
    /// has never completed it, or one of the required permissions is gone.
    static func shouldPresent(settings: AppSettings, probe: PermissionProbe = .live) -> Bool {
        if !settings.onboardingCompleted { return true }
        return !snapshot(probe).allGranted
    }

    // MARK: - Polling

    /// Begin re-reading permission preflights every 0.5s. TCC has no change
    /// notification, so polling is the standard pattern. Idempotent — safe
    /// to call again if the wizard window re-appears.
    func startPolling() {
        guard timerCancellable == nil else { return }
        timerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let next = Self.snapshot(self.probe)
                if next != self.permissionStatus {
                    self.permissionStatus = next
                }
            }
    }

    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    /// Force a one-shot refresh — used by the menu bar's Re-check button so
    /// the warning row clears the moment the user grants the last permission.
    func refresh() {
        permissionStatus = Self.snapshot(probe)
    }

    // MARK: - Completion

    /// Marks onboarding done so the wizard does not auto-pop next launch.
    /// Called both from the final-page Done button and the window's close
    /// handler — Skip and close are equivalent per design.
    func markCompleted() {
        if !settings.onboardingCompleted {
            settings.onboardingCompleted = true
        }
    }

    // MARK: - Permission requests

    /// Tries the in-process TCC trigger first (`AXIsProcessTrustedWithOptions`
    /// and friends). After a prior deny those calls become no-ops, so we also
    /// open the relevant System Settings pane as a fallback. The user then
    /// drags MacBridge into the list and toggles its checkbox; our polling
    /// timer flips the row green automatically.
    func requestPermission(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            _ = AccessibilityPermission.request()
        case .inputMonitoring:
            _ = AccessibilityPermission.requestInputMonitoring()
        case .postEvents:
            _ = AccessibilityPermission.requestEventPosting()
        }
        if let url = Self.systemSettingsURL(for: kind) {
            NSWorkspace.shared.open(url)
        }
        refresh()
    }

    private static func systemSettingsURL(for kind: PermissionKind) -> URL? {
        let path: String
        switch kind {
        case .accessibility:
            path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            path = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .postEvents:
            // No dedicated pane — Post Events is granted via the same
            // Accessibility list on current macOS releases.
            path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        return URL(string: path)
    }

    private static func snapshot(_ probe: PermissionProbe) -> PermissionSnapshot {
        PermissionSnapshot(
            accessibility:   probe.accessibility(),
            inputMonitoring: probe.inputMonitoring(),
            postEvents:      probe.postEvents()
        )
    }
}
