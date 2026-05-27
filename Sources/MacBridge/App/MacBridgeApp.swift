import AppKit
import SwiftUI

@main
struct MacBridgeApp: App {
    @NSApplicationDelegateAdaptor(MacBridgeAppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var eventTap: EventTapController
    @StateObject private var detector: KeyboardDetector
    @StateObject private var profileManager: ProfileManager
    @StateObject private var ruleStore: SchemeStore
    @StateObject private var launchAtLogin: LaunchAtLoginService
    @StateObject private var onboarding: OnboardingState

    init() {
        let settings = AppSettings()
        let detector = KeyboardDetector()
        let ruleStore = SchemeStore(persistence: FileSchemePersistence())
        let tap = EventTapController(settings: settings, ruleStore: ruleStore)
        let manager = ProfileManager(store: ProfileStore(), detector: detector)
        let launch = LaunchAtLoginService()
        let onboarding = OnboardingState(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _detector = StateObject(wrappedValue: detector)
        _eventTap = StateObject(wrappedValue: tap)
        _profileManager = StateObject(wrappedValue: manager)
        _ruleStore = StateObject(wrappedValue: ruleStore)
        _launchAtLogin = StateObject(wrappedValue: launch)
        _onboarding = StateObject(wrappedValue: onboarding)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                settings: settings,
                eventTap: eventTap,
                detector: detector,
                profileManager: profileManager,
                ruleStore: ruleStore,
                launchAtLogin: launchAtLogin,
                onboarding: onboarding
            )
        } label: {
            MenuBarLabelIcon(iconName: menuIconName)
        }
        .menuBarExtraStyle(.menu)

        Window("MacBridge Settings", id: Self.settingsWindowID) {
            SettingsView(settings: settings, ruleStore: ruleStore, eventTap: eventTap)
        }
        .windowResizability(.contentMinSize)

        Window("MacBridge Setup", id: Self.onboardingWindowID) {
            OnboardingView(
                state: onboarding,
                detector: detector,
                profileManager: profileManager
            )
            .onAppear {
                // The wizard is the source of truth for prompting permissions
                // — refresh the tap status whenever it opens, so any newly
                // granted permission flips the engine on without a relaunch.
                eventTap.refresh()
            }
            .onDisappear {
                // After Skip / Done, give the tap one more shot. If the user
                // granted everything the engine starts; if not, the menu's
                // warning row will lead them back here.
                eventTap.retryStart()
            }
        }
        .windowResizability(.contentSize)
    }

    static let settingsWindowID = "macbridge.settings"
    static let onboardingWindowID = "macbridge.onboarding"

    private var menuIconName: String {
        if !onboarding.permissionStatus.allGranted {
            return "keyboard.badge.exclamationmark"
        }
        if settings.remapEngineEnabled || !profileManager.appliedKeyboards.isEmpty {
            return "keyboard.fill"
        }
        return "keyboard"
    }
}

final class MacBridgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Onboarding owns the permission-prompt flow now. We do NOT call
        // `AccessibilityPermission.checkAndPromptIfNeeded()` here — that
        // would fire three TCC dialogs on cold launch before the user has
        // any context for what MacBridge is. The wizard, when it opens,
        // surfaces a Grant button per permission so prompts are user-driven.
        //
        // Auto-presenting the wizard is handled by the SwiftUI side via the
        // `onboarding-autopresent` notification posted below — AppDelegate
        // can't reach `EnvironmentValues.openWindow` directly.
        if OnboardingState.shouldPresentInitially() {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .macbridgeRequestOnboarding,
                    object: nil
                )
            }
        }
    }
}

extension Notification.Name {
    /// Posted from `applicationDidFinishLaunching` when the wizard should
    /// auto-pop. The SwiftUI `App` listens for it and calls `openWindow(...)`.
    static let macbridgeRequestOnboarding = Notification.Name("macbridge.request-onboarding")
}

/// Wraps the menu-bar icon so we can attach an `.onReceive` that fires when
/// `applicationDidFinishLaunching` requests onboarding. The label closure of
/// `MenuBarExtra` is the only consistently-mounted SwiftUI view in this app
/// (the menu content is built lazily on each open), so it's where we listen
/// for the notification — and where we have access to `EnvironmentValues.openWindow`.
private struct MenuBarLabelIcon: View {
    let iconName: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: iconName)
            .onReceive(NotificationCenter.default.publisher(for: .macbridgeRequestOnboarding)) { _ in
                openWindow(id: MacBridgeApp.onboardingWindowID)
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

extension OnboardingState {
    /// AppDelegate-side variant that reads `UserDefaults` directly. We can't
    /// reach the SwiftUI-owned `AppSettings` from `applicationDidFinishLaunching`
    /// because the `@StateObject` is constructed by SwiftUI after the delegate
    /// runs.
    static func shouldPresentInitially(defaults: UserDefaults = .standard) -> Bool {
        let completed = defaults.object(forKey: "onboarding.completed") as? Bool ?? false
        if !completed { return true }
        return !PermissionProbe.live.accessibility()
            || !PermissionProbe.live.inputMonitoring()
            || !PermissionProbe.live.postEvents()
    }
}
