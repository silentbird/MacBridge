import ApplicationServices
import CoreGraphics
import Foundation

enum AccessibilityPermission {
    /// Silent check — never shows a dialog. Use on every tap start.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the native TCC prompt if not yet trusted; no-op if already
    /// trusted or if the user has previously denied (macOS then requires
    /// manually toggling the app in System Settings → Privacy & Security).
    @discardableResult
    static func request() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Input Monitoring permission gates observing keyboard events.
    /// Without it, `CGEvent.tapCreate` can return nil even when
    /// Accessibility is already trusted.
    static func canListenToInput() -> Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        CGRequestListenEventAccess()
    }

    /// Synthetic shortcut events need posting permission as well.
    static func canPostEvents() -> Bool {
        CGPreflightPostEventAccess()
    }

    @discardableResult
    static func requestEventPosting() -> Bool {
        CGRequestPostEventAccess()
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
