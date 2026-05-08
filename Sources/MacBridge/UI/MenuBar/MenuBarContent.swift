import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var eventTap: EventTapController
    @ObservedObject var detector: KeyboardDetector
    @ObservedObject var profileManager: ProfileManager

    var body: some View {
        Group {
            Text("MacBridge").font(.headline)
            Divider()

            globalSection

            Divider()
            keyboardsSection

            Divider()
            devSection

            Divider()
            Button("Re-check permissions") {
                AccessibilityPermission.checkAndPromptIfNeeded()
                eventTap.retryStart()
            }
            Button("Copy diagnostic log") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(diagnosticReport(), forType: .string)
            }

            Divider()
            Button("Quit MacBridge") {
                profileManager.cleanupAll()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .onAppear {
            eventTap.refresh()
        }
    }

    @ViewBuilder
    private var globalSection: some View {
        Text("Global mapping").font(.caption).foregroundStyle(.secondary)
        Toggle(
            "Ctrl → Cmd for C/V/X/Z/A/F/S/O/N/P/T/W",
            isOn: Binding(
                get: { settings.ctrlSemanticEnabled },
                set: {
                    settings.ctrlSemanticEnabled = $0
                    eventTap.refresh()
                }
            )
        )
        Text("Works for physical + remote (UU/VNC/Moonlight); terminals excluded")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        Text("mapping: \(settings.ctrlSemanticEnabled ? "on" : "off")")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        Text("permissions: ax \(permissionMark(AccessibilityPermission.isTrusted())) · input \(permissionMark(AccessibilityPermission.canListenToInput())) · post \(permissionMark(AccessibilityPermission.canPostEvents()))")
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

    private func permissionMark(_ allowed: Bool) -> String {
        allowed ? "yes" : "no"
    }

    private func diagnosticReport() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let bundle = Bundle.main.bundleIdentifier ?? "-"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"

        var lines: [String] = []
        lines.append("=== MacBridge diagnostic ===")
        lines.append("time:     \(fmt.string(from: Date()))")
        lines.append("bundle:   \(bundle) v\(version) (\(build))")
        lines.append("os:       \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")
        lines.append("--- settings ---")
        lines.append("ctrlSemanticEnabled: \(settings.ctrlSemanticEnabled)")
        lines.append("devABTestEnabled:    \(eventTap.devABTestEnabled)")
        lines.append("")
        lines.append("--- permissions (preflight) ---")
        lines.append("accessibility:    \(permissionMark(AccessibilityPermission.isTrusted()))")
        lines.append("input monitoring: \(permissionMark(AccessibilityPermission.canListenToInput()))")
        lines.append("post events:      \(permissionMark(AccessibilityPermission.canPostEvents()))")
        lines.append("")
        lines.append("--- event tap ---")
        lines.append("status:    \(eventTap.statusText)")
        lines.append("seen:      \(eventTap.eventsSeen)")
        lines.append("remapped:  \(eventTap.eventsRemapped)")
        lines.append("frontmost: \(eventTap.lastFrontmost)")
        lines.append("")
        lines.append("--- keyboards (HID) ---")
        lines.append(String(format: "open=0x%X init=%d cb+=%d cb-=%d permissionDenied=%@",
                            detector.openResult,
                            detector.initialEnumerationCount,
                            detector.callbackConnects,
                            detector.callbackRemoves,
                            detector.permissionDenied ? "yes" : "no"))
        if detector.devices.isEmpty {
            lines.append("devices: (none detected)")
        } else {
            lines.append("devices:")
            for device in detector.devices {
                let profile = profileManager.profile(for: device)
                lines.append("  - \(device.debugLabel) swap=\(profile.swapModifiers) applied=\(profileManager.isApplied(device))")
            }
        }
        if let err = profileManager.lastError {
            lines.append("")
            lines.append("profileManager.lastError: \(err)")
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private var devSection: some View {
        Text("Dev sanity checks").font(.caption).foregroundStyle(.secondary)
        Toggle("A → B event-tap test", isOn: $eventTap.devABTestEnabled)
    }
}
