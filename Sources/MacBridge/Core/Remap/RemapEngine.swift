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
        guard type == .keyDown || type == .keyUp else { return .pass }
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
        guard let rule = findMatchingRule(keyCode: keyCode, flags: event.flags, bundleID: context.frontmostBundleID) else {
            return .pass
        }
        remappedKeyDowns[keyCode] = rule.id
        return emit(transformed: event, using: rule)
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
        mutable.formUnion(output.setModifiers.cgFlags)
        return mutable
    }
}
