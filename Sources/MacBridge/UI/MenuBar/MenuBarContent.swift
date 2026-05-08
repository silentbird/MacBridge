import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var eventTap: EventTapController
    @ObservedObject var detector: KeyboardDetector
    @ObservedObject var profileManager: ProfileManager
    @ObservedObject var ruleStore: SchemeStore
    @ObservedObject var launchAtLogin: LaunchAtLoginService

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Text("MacBridge").font(.headline)
            Divider()

            globalSection

            Divider()
            schemesSection

            Divider()
            rulesSection

            Divider()
            keyboardsSection

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
            launchAtLogin.refresh()
        }
    }

    @ViewBuilder
    private var schemesSection: some View {
        Menu("Scheme: \(activeSchemeName)") {
            ForEach(ruleStore.library.schemes) { scheme in
                Button {
                    ruleStore.selectScheme(id: scheme.id)
                } label: {
                    // SwiftUI menu Buttons can't prefix an icon view cleanly,
                    // so we embed the check mark directly in the label.
                    Text(scheme.id == ruleStore.library.activeSchemeID
                         ? "✓ \(scheme.name)"
                         : "   \(scheme.name)")
                }
            }
            Divider()
            Button("Manage schemes…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: MacBridgeApp.settingsWindowID)
            }
        }
    }

    private var activeSchemeName: String {
        ruleStore.library.schemes.first(where: { $0.id == ruleStore.library.activeSchemeID })?.name
            ?? "—"
    }

    @ViewBuilder
    private var rulesSection: some View {
        Menu("Shortcut rules (\(enabledRuleCount)/\(ruleStore.book.rules.count))") {
            ForEach(ruleStore.book.rules) { rule in
                Toggle(rule.name, isOn: enabledBinding(for: rule))
            }
            Divider()
            Button("Open settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: MacBridgeApp.settingsWindowID)
            }
            Button("Reset to defaults") {
                ruleStore.resetToDefaults()
            }
        }
    }

    private func enabledBinding(for rule: RemapRule) -> Binding<Bool> {
        Binding(
            get: { ruleStore.book.rules.first(where: { $0.id == rule.id })?.enabled ?? false },
            set: { newValue in
                var book = ruleStore.book
                guard let idx = book.rules.firstIndex(where: { $0.id == rule.id }) else { return }
                book.rules[idx].enabled = newValue
                ruleStore.save(book)
            }
        )
    }

    @ViewBuilder
    private var globalSection: some View {
        Toggle(
            "Enable remap engine",
            isOn: Binding(
                get: { settings.remapEngineEnabled },
                set: {
                    settings.remapEngineEnabled = $0
                    eventTap.refresh()
                }
            )
        )
        Toggle(
            "Launch at login",
            isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            )
        )
        if let err = launchAtLogin.lastError {
            Text("⚠️ \(err)")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var keyboardsSection: some View {
        if detector.devices.isEmpty {
            Text("No physical keyboards detected").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Physical keyboards").font(.caption).foregroundStyle(.secondary)
            ForEach(detector.devices) { device in
                Toggle(isOn: swapBinding(for: device)) {
                    Text("Swap Alt↔Cmd  ·  \(device.productName)")
                }
            }
        }
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

    private var enabledRuleCount: Int {
        ruleStore.book.rules.lazy.filter(\.enabled).count
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
        lines.append("remapEngineEnabled: \(settings.remapEngineEnabled)")
        lines.append("devABTestEnabled:   \(eventTap.devABTestEnabled)")
        lines.append("rules:              \(enabledRuleCount)/\(ruleStore.book.rules.count) enabled (schema v\(ruleStore.book.version))")
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

}
