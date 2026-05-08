import Foundation

/// USB HID Usage IDs for keyboard modifier keys, as `hidutil` expects them.
/// Format: (usage page 0x07 << 32) | usage ID.
/// Reference: USB HID Usage Tables v1.12 §10 Keyboard/Keypad Page.
enum HIDKeyUsage {
    static let leftControl: UInt64  = 0x7_0000_00E0
    static let leftShift: UInt64    = 0x7_0000_00E1
    static let leftAlt: UInt64      = 0x7_0000_00E2
    static let leftGUI: UInt64      = 0x7_0000_00E3  // Win key on Win, Cmd on Mac
    static let rightControl: UInt64 = 0x7_0000_00E4
    static let rightShift: UInt64   = 0x7_0000_00E5
    static let rightAlt: UInt64     = 0x7_0000_00E6
    static let rightGUI: UInt64     = 0x7_0000_00E7
}
