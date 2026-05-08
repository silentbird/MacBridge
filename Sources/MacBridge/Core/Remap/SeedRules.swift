import CoreGraphics
import Foundation

/// Default rulebook shipped at first launch. Mirrors the old
/// `CtrlSemanticRule`'s behavior 1:1 so the refactor is user-invisible:
/// 12 single-key Ctrl→Cmd rules + Shift variants for T and Z, all excluded
/// from the usual terminal emulators.
enum SeedRules {
    /// US-layout virtual keycodes (HIToolbox `Events.h`).
    static let keyA: CGKeyCode = 0
    static let keyS: CGKeyCode = 1
    static let keyF: CGKeyCode = 3
    static let keyZ: CGKeyCode = 6
    static let keyX: CGKeyCode = 7
    static let keyC: CGKeyCode = 8
    static let keyV: CGKeyCode = 9
    static let keyW: CGKeyCode = 13
    static let keyT: CGKeyCode = 17
    static let keyO: CGKeyCode = 31
    static let keyP: CGKeyCode = 35
    static let keyN: CGKeyCode = 45

    static let defaultExcludeBundleIDs: [String] = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "org.alacritty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "org.tabby",
    ]

    static var defaultBook: RuleBook {
        RuleBook(rules: defaultRules, version: RuleBook.currentVersion)
    }

    /// The built-in "Windows Migration" scheme every fresh install starts
    /// with. Gets re-created if the library is empty or corrupt.
    static func defaultScheme() -> Scheme {
        let now = Date()
        return Scheme(
            id: UUID(),
            name: "Windows Migration",
            createdAt: now,
            modifiedAt: now,
            book: defaultBook,
            isBuiltIn: true
        )
    }

    /// Used by `SchemeStore` when nothing is on disk and there's no legacy
    /// data to migrate — produces a library with a single built-in scheme.
    static func defaultLibrary() -> SchemeLibrary {
        let scheme = defaultScheme()
        return SchemeLibrary(
            schemes: [scheme],
            activeSchemeID: scheme.id,
            libraryVersion: SchemeLibrary.currentLibraryVersion
        )
    }

    static var defaultRules: [RemapRule] {
        var out: [RemapRule] = []

        // Single-key Ctrl+X → Cmd+X for the 12 whitelisted letters.
        let singles: [(name: String, code: CGKeyCode)] = [
            ("Copy",              keyC),
            ("Paste",             keyV),
            ("Cut",               keyX),
            ("Undo",              keyZ),
            ("Select All",        keyA),
            ("Find",              keyF),
            ("Save",              keyS),
            ("Open",              keyO),
            ("New",               keyN),
            ("Print",             keyP),
            ("New Tab",           keyT),
            ("Close Tab/Window",  keyW),
        ]
        for single in singles {
            out.append(
                RemapRule(
                    id: UUID(),
                    name: "\(single.name) (Ctrl+\(label(single.code)) → Cmd+\(label(single.code)))",
                    enabled: true,
                    trigger: KeyTrigger(
                        keyCode: single.code,
                        requiredModifiers: [.ctrl],
                        forbiddenModifiers: [.cmd]
                    ),
                    output: KeyOutput(
                        keyCode: nil,
                        setModifiers: [.cmd],
                        clearModifiers: [.ctrl]
                    ),
                    excludeBundleIDs: defaultExcludeBundleIDs,
                    isBuiltIn: true,
                    nameIsCustom: true
                )
            )
        }

        // Shift variants — explicit rules so UI can surface them as separate
        // toggles. The engine's "extra modifiers pass through" behavior
        // would actually make these redundant, but users expect to see them
        // in the list as distinct Copy-style shortcuts.
        //
        // Ctrl+Shift+T = reopen closed tab / Ctrl+Shift+Z = redo.
        out.append(shiftVariant(name: "Reopen Closed Tab", code: keyT))
        out.append(shiftVariant(name: "Redo", code: keyZ))

        return out
    }

    private static func shiftVariant(name: String, code: CGKeyCode) -> RemapRule {
        RemapRule(
            id: UUID(),
            name: "\(name) (Ctrl+Shift+\(label(code)) → Cmd+Shift+\(label(code)))",
            enabled: true,
            trigger: KeyTrigger(
                keyCode: code,
                requiredModifiers: [.ctrl, .shift],
                forbiddenModifiers: [.cmd]
            ),
            output: KeyOutput(
                keyCode: nil,
                setModifiers: [.cmd],
                clearModifiers: [.ctrl]
            ),
            excludeBundleIDs: defaultExcludeBundleIDs,
            isBuiltIn: true,
            nameIsCustom: true
        )
    }

    /// Just enough to render seed-rule names; full symbol mapping lives in
    /// the P3 UI layer's key-formatting helpers.
    private static func label(_ code: CGKeyCode) -> String {
        switch code {
        case keyA: return "A"; case keyS: return "S"; case keyF: return "F"
        case keyZ: return "Z"; case keyX: return "X"; case keyC: return "C"
        case keyV: return "V"; case keyW: return "W"; case keyT: return "T"
        case keyO: return "O"; case keyP: return "P"; case keyN: return "N"
        default: return String(format: "0x%02X", code)
        }
    }
}
