import AppKit
import SwiftUI

@main
struct MacBridgeApp: App {
    @NSApplicationDelegateAdaptor(MacBridgeAppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var eventTap: EventTapController
    @StateObject private var detector: KeyboardDetector
    @StateObject private var profileManager: ProfileManager

    init() {
        let settings = AppSettings()
        let detector = KeyboardDetector()
        let tap = EventTapController(settings: settings)
        let manager = ProfileManager(store: ProfileStore(), detector: detector)
        _settings = StateObject(wrappedValue: settings)
        _detector = StateObject(wrappedValue: detector)
        _eventTap = StateObject(wrappedValue: tap)
        _profileManager = StateObject(wrappedValue: manager)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                settings: settings,
                eventTap: eventTap,
                detector: detector,
                profileManager: profileManager
            )
        } label: {
            Image(systemName: menuIconName)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuIconName: String {
        if settings.ctrlSemanticEnabled || !profileManager.appliedKeyboards.isEmpty {
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
