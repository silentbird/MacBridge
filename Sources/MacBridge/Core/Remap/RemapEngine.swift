import Combine
import CoreGraphics
import Foundation

/// Data-driven replacement for the old `CtrlSemanticRule`. Walks a user-owned
/// `RuleBook` for every key event and applies the first rule whose trigger
/// matches. The state machine (keyUp pairing, synthetic-event tagging) is
/// unchanged from the hardcoded predecessor — we just swapped the whitelist
/// for a `[RemapRule]` lookup.
final class RemapEngine: KeyRemapRule {
    private let settings: AppSettings
    private let frontmost: FrontmostAppTracker
    private let store: RuleStoring
    private let postEvent: (CGEvent) -> Void

    private var book: RuleBook
    private var ruleIndex: [CGKeyCode: [RemapRule]] = [:]
    private var cancellable: AnyCancellable?

    /// Tracks which rule produced each pending keyDown so the matching keyUp
    /// is rewritten the same way — even if the user released Ctrl before the
    /// letter key (common in fast typing).
    private var remappedKeyDowns: [CGKeyCode: RemapRule.ID] = [:]

    /// Keys whose system behavior depends on the modifier staying held (Cmd+Tab
    /// keeps the app switcher open until Cmd is released). Rewriting only the
    /// keyDown leaves WindowServer with no Cmd press to release, so the
    /// switcher would stay on screen. For these keys we post a real Cmd
    /// `flagsChanged` press and release it when the physical source modifier
    /// (Alt) goes up. Other rules stay momentary: holding Cmd there would turn
    /// a later Ctrl+D into Cmd+Ctrl+D.
    private static let holdModifierKeyCodes: Set<CGKeyCode> = [48]  // Tab

    /// Modifier we pressed on the system's behalf, and the physical modifiers
    /// whose release should let it go.
    private var heldSynthetic: (modifiers: ModifierSet, source: ModifierSet)?

    init(
        settings: AppSettings,
        frontmost: FrontmostAppTracker,
        store: RuleStoring,
        // Production wires this through EventTapController so synthetic
        // events land at the layer the tap actually created at (HID if
        // available, session otherwise). This default is only used by
        // tests that don't care where events "post".
        postEvent: @escaping (CGEvent) -> Void = { event in
            event.post(tap: .cgSessionEventTap)
        }
    ) {
        self.settings = settings
        self.frontmost = frontmost
        self.store = store
        self.postEvent = postEvent
        self.book = store.book
        rebuildIndex()

        cancellable = store.bookPublisher
            .sink { [weak self] newBook in
                self?.book = newBook
                self?.rebuildIndex()
            }
    }

    func apply(to event: CGEvent, type: CGEventType, context: KeyRemapContext) -> KeyRemapResult {
        guard type == .keyDown || type == .keyUp || type == .flagsChanged else { return .pass }

        // Runs even when the engine was just disabled, so a held Cmd is
        // never left behind.
        if type == .flagsChanged {
            releaseHeldIfSourceReleased(by: event)
            return .pass
        }

        guard settings.remapEngineEnabled else { return .pass }

        let rawKey = event.getIntegerValueField(.keyboardEventKeycode)
        let keyCode = CGKeyCode(clamping: rawKey)

        // keyUp side: if we remapped the matching keyDown, rewrite the keyUp
        // with the same rule so the synthetic Cmd+C release pairs with the
        // synthetic Cmd+C press. Fetching the rule by id (not by re-matching)
        // is important because the user may have already released Ctrl.
        if type == .keyUp {
            guard let ruleID = remappedKeyDowns.removeValue(forKey: keyCode),
                  let rule = book.rules.first(where: { $0.id == ruleID }) else {
                return .pass
            }
            return emit(transformed: event, using: rule)
        }

        // keyDown: find the first matching enabled rule.
        // Our own held Cmd shows up in the system flags; it must not count
        // as a user-pressed modifier or the rule's `forbidden: Cmd` would
        // reject the second Tab of Alt+Tab+Tab.
        var physical = event.flags
        if let held = heldSynthetic {
            physical = Self.removing(held.modifiers, from: physical)
        }
        guard let rule = findMatchingRule(keyCode: keyCode, flags: physical, bundleID: context.frontmostBundleID) else {
            return .pass
        }
        if Self.holdModifierKeyCodes.contains(keyCode) {
            holdOutputModifiers(of: rule, physicalFlags: physical)
        }
        remappedKeyDowns[keyCode] = rule.id
        return emit(transformed: event, using: rule)
    }

    // MARK: - Held modifiers

    private func holdOutputModifiers(of rule: RemapRule, physicalFlags: CGEventFlags) {
        guard heldSynthetic == nil else { return }
        let pressed = ModifierSet.from(physicalFlags)
        let source = rule.output.clearModifiers.intersection(pressed)
        let toPress = rule.output.setModifiers.subtracting(pressed)
        guard !source.isEmpty, !toPress.isEmpty else { return }

        var flags = physicalFlags
        flags.formUnion(toPress.cgFlags)
        flags = CGEventFlags(rawValue: flags.rawValue | toPress.deviceFlagsLeftSide)
        postModifierEvents(toPress, flags: flags)
        heldSynthetic = (toPress, source)
    }

    /// The only trustworthy "Alt went up" signal is Alt's own `flagsChanged`.
    /// Once we have posted a Cmd press, the system flags on later events (and
    /// even the hardware key state) stop showing the Alt that is still held,
    /// so keyDown/keyUp flags must not be used to decide.
    private func releaseHeldIfSourceReleased(by event: CGEvent) {
        guard let held = heldSynthetic else { return }
        let keyCode = CGKeyCode(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        guard Self.leftAndRightKeyCodes(of: held.source).contains(keyCode),
              held.source.isDisjoint(with: ModifierSet.from(event.flags)) else { return }
        heldSynthetic = nil
        postModifierEvents(held.modifiers, flags: Self.removing(held.modifiers, from: event.flags))
    }

    private func postModifierEvents(_ modifiers: ModifierSet, flags: CGEventFlags) {
        for keyCode in Self.leftKeyCodes(of: modifiers) {
            guard let event = CGEvent(
                keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                virtualKey: keyCode,
                keyDown: true
            ) else { continue }
            event.type = .flagsChanged
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: KeyRemapSyntheticEvent.userData)
            postEvent(event)
        }
    }

    private static func removing(_ modifiers: ModifierSet, from flags: CGEventFlags) -> CGEventFlags {
        var out = flags
        out.subtract(modifiers.cgFlags)
        return CGEventFlags(rawValue: out.rawValue & ~modifiers.deviceFlagsAnySide)
    }

    private static func leftAndRightKeyCodes(of modifiers: ModifierSet) -> [CGKeyCode] {
        var out: [CGKeyCode] = []
        if modifiers.contains(.cmd)   { out += [55, 54] }
        if modifiers.contains(.shift) { out += [56, 60] }
        if modifiers.contains(.alt)   { out += [58, 61] }
        if modifiers.contains(.ctrl)  { out += [59, 62] }
        return out
    }

    private static func leftKeyCodes(of modifiers: ModifierSet) -> [CGKeyCode] {
        var out: [CGKeyCode] = []
        if modifiers.contains(.cmd)   { out.append(55) }
        if modifiers.contains(.shift) { out.append(56) }
        if modifiers.contains(.alt)   { out.append(58) }
        if modifiers.contains(.ctrl)  { out.append(59) }
        return out
    }

    // MARK: - Matching

    private func findMatchingRule(keyCode: CGKeyCode, flags: CGEventFlags, bundleID: String?) -> RemapRule? {
        guard let candidates = ruleIndex[keyCode] else { return nil }
        let pressed = ModifierSet.from(flags)
        for rule in candidates {
            guard rule.enabled else { continue }
            if !pressed.isSuperset(of: rule.trigger.requiredModifiers) { continue }
            if !rule.trigger.forbiddenModifiers.isDisjoint(with: pressed) { continue }
            if let bundleID, rule.excludeBundleIDs.contains(bundleID) { continue }
            return rule
        }
        return nil
    }

    private func rebuildIndex() {
        var index: [CGKeyCode: [RemapRule]] = [:]
        for rule in book.rules {
            index[rule.trigger.keyCode, default: []].append(rule)
        }
        ruleIndex = index
    }

    // MARK: - Emit

    private func emit(transformed original: CGEvent, using rule: RemapRule) -> KeyRemapResult {
        let newFlags = apply(output: rule.output, to: original.flags)
        original.flags = newFlags
        if let overrideKey = rule.output.keyCode {
            original.setIntegerValueField(.keyboardEventKeycode, value: Int64(overrideKey))
        }

        guard let synthetic = original.copy() else {
            // Copy failure is extraordinarily rare; fall back to pass-through
            // so we don't eat the user's keystroke.
            return .pass
        }
        synthetic.setIntegerValueField(
            .eventSourceUserData,
            value: KeyRemapSyntheticEvent.userData
        )
        postEvent(synthetic)
        return .suppress
    }

    private func apply(output: KeyOutput, to flags: CGEventFlags) -> CGEventFlags {
        var mutable = flags
        mutable.subtract(output.clearModifiers.cgFlags)
        mutable = CGEventFlags(rawValue: mutable.rawValue & ~output.clearModifiers.deviceFlagsAnySide)
        // Only add the left-side bit when the modifier wasn't already held,
        // so a real Right-Cmd stays Right-Cmd.
        let newlySet = output.setModifiers.subtracting(ModifierSet.from(mutable))
        mutable.formUnion(output.setModifiers.cgFlags)
        mutable = CGEventFlags(rawValue: mutable.rawValue | newlySet.deviceFlagsLeftSide)
        return mutable
    }
}
