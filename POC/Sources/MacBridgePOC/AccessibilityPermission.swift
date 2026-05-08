import ApplicationServices
import Foundation

enum AccessibilityPermission {
    /// Returns true if the process is trusted for AX.
    /// Pass `prompt: true` to show the system permission dialog when not trusted.
    @discardableResult
    static func check(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
