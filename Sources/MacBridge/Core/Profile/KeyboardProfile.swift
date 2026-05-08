import Foundation

/// Per-keyboard user preferences. Persisted in UserDefaults keyed by VID-PID.
/// Extend with new fields as features land (F5 Home/End, F8 Ctrl mapping).
struct KeyboardProfile: Codable, Equatable {
    var swapModifiers: Bool   // F2: Win-layout modifier swap (Alt↔Cmd)

    static let windowsDefault = KeyboardProfile(swapModifiers: true)
    static let appleDefault = KeyboardProfile(swapModifiers: false)

    static func `default`(for layout: KeyboardLayout) -> KeyboardProfile {
        switch layout {
        case .windows: return .windowsDefault
        case .apple, .unknown: return .appleDefault
        }
    }
}
