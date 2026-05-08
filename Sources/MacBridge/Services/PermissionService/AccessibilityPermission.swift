import ApplicationServices
import AppKit
import Foundation

enum AccessibilityPermission {
    enum PrivacyPane {
        case accessibility
        case inputMonitoring

        var url: URL? {
            switch self {
            case .accessibility:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            case .inputMonitoring:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
            }
        }
    }

    /// Silent check — never shows a dialog. Use on every tap start.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system permission prompt (and directs user to System Settings
    /// if not already granted). Call only from an explicit user action —
    /// calling this in an auto-run path will annoy users whose TCC state is
    /// stale (e.g., after an ad-hoc rebuild invalidates the grant).
    @discardableResult
    static func request() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Input Monitoring permission gates observing keyboard events on modern
    /// macOS. Without it, `CGEvent.tapCreate` can return nil even when
    /// Accessibility is already trusted.
    static func canListenToInput() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        if #available(macOS 10.15, *) {
            return CGRequestListenEventAccess()
        }
        return true
    }

    /// Synthetic shortcut events need posting permission as well.
    static func canPostEvents() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightPostEventAccess()
        }
        return true
    }

    @discardableResult
    static func requestEventPosting() -> Bool {
        if #available(macOS 10.15, *) {
            return CGRequestPostEventAccess()
        }
        return true
    }

    static func openSettings(_ pane: PrivacyPane) {
        guard let url = pane.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Run at app launch (and from the menu's "Re-check permissions"). Fires
    /// the native TCC prompts for each missing permission in turn. On first
    /// launch macOS shows its own permission dialog / notification for each;
    /// after a prior deny the call is a no-op and the user must grant access
    /// manually in System Settings → Privacy & Security.
    static func checkAndPromptIfNeeded() {
        if !isTrusted() { _ = request() }
        if !canListenToInput() { _ = requestInputMonitoring() }
        if !canPostEvents() { _ = requestEventPosting() }
    }
}
