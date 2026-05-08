import CoreGraphics
import Foundation

/// The five modifier keys we let rules match and set. `fn` is included for
/// completeness (some external keyboards surface Fn) even though CGEventFlags
/// does not expose a dedicated fn mask — see `cgFlags` for the gotcha.
struct ModifierSet: OptionSet, Codable, Hashable {
    let rawValue: UInt8

    static let ctrl  = ModifierSet(rawValue: 1 << 0)
    static let shift = ModifierSet(rawValue: 1 << 1)
    static let alt   = ModifierSet(rawValue: 1 << 2)
    static let cmd   = ModifierSet(rawValue: 1 << 3)
    static let fn    = ModifierSet(rawValue: 1 << 4)

    var cgFlags: CGEventFlags {
        var out: CGEventFlags = []
        if contains(.ctrl)  { out.insert(.maskControl) }
        if contains(.shift) { out.insert(.maskShift) }
        if contains(.alt)   { out.insert(.maskAlternate) }
        if contains(.cmd)   { out.insert(.maskCommand) }
        if contains(.fn)    { out.insert(.maskSecondaryFn) }
        return out
    }

    static func from(_ flags: CGEventFlags) -> ModifierSet {
        var out: ModifierSet = []
        if flags.contains(.maskControl)      { out.insert(.ctrl) }
        if flags.contains(.maskShift)        { out.insert(.shift) }
        if flags.contains(.maskAlternate)    { out.insert(.alt) }
        if flags.contains(.maskCommand)      { out.insert(.cmd) }
        if flags.contains(.maskSecondaryFn)  { out.insert(.fn) }
        return out
    }
}

/// The left side of a rule. Matches when:
///   - the event's keyCode equals `keyCode`
///   - every modifier in `requiredModifiers` is pressed
///   - no modifier in `forbiddenModifiers` is pressed
/// Modifiers not listed in either set are "don't care" — they pass through
/// so e.g. a Ctrl+T trigger also matches Ctrl+Shift+T with Shift carried
/// onto the output.
struct KeyTrigger: Codable, Equatable, Hashable {
    var keyCode: CGKeyCode
    var requiredModifiers: ModifierSet
    var forbiddenModifiers: ModifierSet
}

/// The right side of a rule. `keyCode == nil` means "keep the trigger's
/// keyCode". `setModifiers` and `clearModifiers` are applied to the original
/// event's flags (clear then set), preserving every other modifier.
struct KeyOutput: Codable, Equatable, Hashable {
    var keyCode: CGKeyCode?
    var setModifiers: ModifierSet
    var clearModifiers: ModifierSet
}

struct RemapRule: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var enabled: Bool
    var trigger: KeyTrigger
    var output: KeyOutput
    /// Bundle identifiers of apps where this rule does NOT fire. Terminals
    /// live here by default so Ctrl+C stays as interrupt-process.
    var excludeBundleIDs: [String]
    /// Seeded at first launch from SeedRules; user-added rules are false.
    /// Used by the "Reset to defaults" flow to know what to regenerate.
    var isBuiltIn: Bool
    /// True when the user has explicitly typed a name. When false, the editor
    /// auto-regenerates `name` as the user changes trigger/output.
    var nameIsCustom: Bool = true
}

struct RuleBook: Codable, Equatable {
    var rules: [RemapRule]
    /// Schema version. Bump whenever Codable shape changes so RuleStore.load
    /// can migrate (or discard to seed) gracefully.
    var version: Int

    static let currentVersion = 2

    /// Placeholder keyCode for newly-added rules that haven't been assigned a
    /// real shortcut yet. Never matches any real event (real virtual keycodes
    /// max out around 0x7F).
    static let unsetKeyCode: CGKeyCode = 0xFFFF
}
