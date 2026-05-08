import ApplicationServices
import Foundation

enum AccessibilityPermission {
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
}
