import Foundation

/// Canonical modifier-key mapping presets.
enum ModifierSwapPreset {
    /// Win-layout → Mac: swap Alt ↔ GUI on both sides so the key physically
    /// closest to the spacebar is recognized as Cmd (matches Mac's Cmd position).
    /// - Win keyboards send physical Alt as HID Left-Alt and physical Win as HID Left-GUI
    /// - On Mac, Left-GUI = Cmd, Left-Alt = Option
    /// - Swapping Alt↔GUI therefore makes "key next to space" = Cmd.
    static let winLayoutToMac: [KeyMapping] = [
        KeyMapping(src: HIDKeyUsage.leftAlt,   dst: HIDKeyUsage.leftGUI),
        KeyMapping(src: HIDKeyUsage.leftGUI,   dst: HIDKeyUsage.leftAlt),
        KeyMapping(src: HIDKeyUsage.rightAlt,  dst: HIDKeyUsage.rightGUI),
        KeyMapping(src: HIDKeyUsage.rightGUI,  dst: HIDKeyUsage.rightAlt),
    ]
}
