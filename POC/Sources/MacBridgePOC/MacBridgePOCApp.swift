import SwiftUI

@main
struct MacBridgePOCApp: App {
    @StateObject private var tap = EventTapController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(tap: tap)
        } label: {
            Image(systemName: tap.enabled ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var tap: EventTapController

    var body: some View {
        Toggle("Enable A → B test", isOn: $tap.enabled)
        Divider()
        Text(tap.statusText)
        Button("Check Accessibility permission") {
            _ = AccessibilityPermission.check(prompt: true)
        }
        Divider()
        Button("Quit MacBridge POC") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
