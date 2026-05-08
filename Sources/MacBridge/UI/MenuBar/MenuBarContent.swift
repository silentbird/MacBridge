import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var eventTap: EventTapController
    @ObservedObject var detector: KeyboardDetector
    @ObservedObject var profileManager: ProfileManager

    var body: some View {
        Text("MacBridge").font(.headline)
        Divider()

        globalSection

        Divider()
        keyboardsSection

        Divider()
        devSection

        Divider()
        Button("Request Accessibility permission") {
            _ = AccessibilityPermission.request()
        }
        Button("Retry event-tap activation") {
            eventTap.retryStart()
        }

        Divider()
        Button("Quit MacBridge") {
            profileManager.cleanupAll()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var globalSection: some View {
        Text("Global mapping").font(.caption).foregroundStyle(.secondary)
        Toggle("Ctrl → Cmd for C/V/X/Z/A/F/S/O/N/P/T/W", isOn: $settings.ctrlSemanticEnabled)
        Text("Works for physical + remote (UU/VNC/Moonlight); terminals excluded")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        Text("tap: \(eventTap.statusText) · seen: \(eventTap.eventsSeen) · remapped: \(eventTap.eventsRemapped)")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        Text("frontmost: \(eventTap.lastFrontmost)")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var keyboardsSection: some View {
        if detector.devices.isEmpty {
            Text("No physical keyboards detected").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Physical keyboards (hidutil modifier swap)").font(.caption).foregroundStyle(.secondary)
            ForEach(detector.devices) { device in
                Toggle(isOn: swapBinding(for: device)) {
                    Text("Swap Alt↔Cmd  ·  \(device.productName)")
                }
            }
        }

        if detector.permissionDenied {
            Text("ℹ️ Hot-plug may require Input Monitoring permission")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        Text(String(format: "HID open: 0x%X · init: %d · cb+: %d · cb-: %d",
                    detector.openResult,
                    detector.initialEnumerationCount,
                    detector.callbackConnects,
                    detector.callbackRemoves))
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        if let err = profileManager.lastError {
            Text("⚠️ \(err)").font(.system(size: 10)).foregroundStyle(.red)
        }
    }

    private func swapBinding(for device: KeyboardDevice) -> Binding<Bool> {
        Binding(
            get: { profileManager.profile(for: device).swapModifiers },
            set: { profileManager.setSwapEnabled($0, for: device) }
        )
    }

    @ViewBuilder
    private var devSection: some View {
        Text("Dev sanity checks").font(.caption).foregroundStyle(.secondary)
        Toggle("A → B event-tap test", isOn: $eventTap.devABTestEnabled)
        Text(eventTap.statusText).font(.caption)
    }
}
