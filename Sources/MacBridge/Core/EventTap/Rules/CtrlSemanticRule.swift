import CoreGraphics
import Foundation

/// F8 — Ctrl→Cmd semantic mapping.
/// Rewrites a whitelist of Ctrl-based Windows shortcuts to their Cmd-based
/// Mac equivalents. Blacklists terminal emulators so `Ctrl+C` stays as
/// interrupt-process there.
///
/// Works at the CGEvent layer, so it catches both physical HID key events AND
/// events injected by remote-control software (UU, Moonlight, VNC, etc.) —
/// unlike F2 (hidutil) which only sees physical HID reports.
final class CtrlSemanticRule: KeyRemapRule {
    private let settings: AppSettings
    private let frontmost: FrontmostAppTracker

    /// US-layout virtual keycodes (from `HIToolbox/Events.h`) for keys we remap
    /// when Ctrl is held. Choice follows PRD §4.1 F8:
    ///   C V X Z A F S O N P T W  +  Shift+T, Shift+Z
    /// Excludes H (Mac=hide app), Y (Mac=paste-deleted), and emacs-style
    /// single letters handled natively (A/E/K/etc. handled contextually via
    /// modifier check: we only swap when Ctrl alone is held, without Alt/Cmd).
    private let whitelistKeyCodes: Set<Int64> = [
        0,   // A
        1,   // S
        3,   // F
        6,   // Z
        7,   // X
        8,   // C
        9,   // V
        13,  // W
        17,  // T
        31,  // O
        35,  // P
        45,  // N
    ]

    /// Bundle identifiers of terminal emulators where we do NOT remap.
    /// Keeping `Ctrl+C`=interrupt and `Ctrl+D`=EOF is essential here.
    private let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "org.alacritty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "org.tabby",
    ]

    init(settings: AppSettings, frontmost: FrontmostAppTracker) {
        self.settings = settings
        self.frontmost = frontmost
    }

    func apply(to event: CGEvent, type: CGEventType, context: KeyRemapContext) {
        guard settings.ctrlSemanticEnabled else { return }
        guard type == .keyDown || type == .keyUp else { return }

        let flags = event.flags
        // Only handle "Ctrl held, not Cmd" — if Cmd is already held the user
        // already has the Mac shortcut, don't double-process.
        guard flags.contains(.maskControl), !flags.contains(.maskCommand) else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard whitelistKeyCodes.contains(keyCode) else { return }

        // Terminal blacklist — preserve native Ctrl+C behavior.
        if let bundleID = context.frontmostBundleID,
           terminalBundleIDs.contains(bundleID) {
            return
        }

        var newFlags = flags
        newFlags.remove(.maskControl)
        newFlags.insert(.maskCommand)
        event.flags = newFlags
    }
}
