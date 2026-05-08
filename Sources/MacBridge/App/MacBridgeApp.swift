import AppKit
import SwiftUI

@main
struct MacBridgeApp: App {
    @NSApplicationDelegateAdaptor(MacBridgeAppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var eventTap: EventTapController
    @StateObject private var detector: KeyboardDetector
    @StateObject private var profileManager: ProfileManager
    @StateObject private var ruleStore: RuleStore

    init() {
        let settings = AppSettings()
        let detector = KeyboardDetector()
        let ruleStore = RuleStore()
        let tap = EventTapController(settings: settings, ruleStore: ruleStore)
        let manager = ProfileManager(store: ProfileStore(), detector: detector)
        _settings = StateObject(wrappedValue: settings)
        _detector = StateObject(wrappedValue: detector)
        _eventTap = StateObject(wrappedValue: tap)
        _profileManager = StateObject(wrappedValue: manager)
        _ruleStore = StateObject(wrappedValue: ruleStore)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                settings: settings,
                eventTap: eventTap,
                detector: detector,
                profileManager: profileManager,
                ruleStore: ruleStore
            )
        } label: {
            Image(systemName: menuIconName)
        }
        .menuBarExtraStyle(.menu)

        Window("MacBridge Settings", id: Self.settingsWindowID) {
            SettingsView(settings: settings, ruleStore: ruleStore, eventTap: eventTap)
        }
        .windowResizability(.contentMinSize)
    }

    static let settingsWindowID = "macbridge.settings"

    private var menuIconName: String {
        if settings.remapEngineEnabled || !profileManager.appliedKeyboards.isEmpty {
            return "keyboard.fill"
        }
        return "keyboard"
    }
}

final class MacBridgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AccessibilityPermission.checkAndPromptIfNeeded()
    }
}
