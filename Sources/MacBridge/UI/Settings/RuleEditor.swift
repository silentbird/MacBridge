import SwiftUI

/// Right-pane editor for a single rule. Takes a rule id + store so edits
/// flow through SchemeStore.save() (which fans out to RemapEngine via the
/// bookPublisher).
struct RuleEditor: View {
    let ruleID: RemapRule.ID
    @ObservedObject var ruleStore: SchemeStore
    @ObservedObject var eventTap: EventTapController

    var body: some View {
        if let rule = ruleStore.book.rules.first(where: { $0.id == ruleID }) {
            Form {
                Section("Identity") {
                    TextField("Name", text: nameBinding(for: rule))
                    Toggle("Enabled", isOn: enabledBinding(for: rule))
                    if rule.trigger.keyCode == RuleBook.unsetKeyCode {
                        Text("Capture a trigger and an output below. The rule will enable itself once both are set.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if rule.isBuiltIn {
                        Text("Built-in rule — edits are saved, and \"Reset to defaults\" restores the original.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Trigger") {
                    KeyCaptureField(shortcut: triggerBinding(for: rule), eventTap: eventTap, title: "Trigger")
                }

                Section("Output") {
                    KeyCaptureField(shortcut: outputBinding(for: rule), eventTap: eventTap, title: "Output")
                    Text("Extra modifiers pass through unchanged — e.g. the seed Ctrl+C rule also handles Ctrl+Shift+C.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Exclude in these apps") {
                    BundleIDListView(bundleIDs: excludesBinding(for: rule))
                }
            }
            .formStyle(.grouped)
        } else {
            Text("Rule not found")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private func nameBinding(for rule: RemapRule) -> Binding<String> {
        Binding(
            get: { currentRule(rule.id)?.name ?? "" },
            set: { newValue in
                mutate(rule.id) { current in
                    current.name = newValue
                    // User typed something themselves → stop auto-regenerating.
                    // Flipping to empty also counts as intentional.
                    current.nameIsCustom = true
                }
            }
        )
    }

    private func enabledBinding(for rule: RemapRule) -> Binding<Bool> {
        Binding(
            get: { currentRule(rule.id)?.enabled ?? false },
            set: { new in mutate(rule.id) { $0.enabled = new } }
        )
    }

    private func triggerBinding(for rule: RemapRule) -> Binding<CapturedShortcut> {
        Binding(
            get: {
                guard let r = currentRule(rule.id) else {
                    return CapturedShortcut(keyCode: RuleBook.unsetKeyCode, modifiers: [])
                }
                return CapturedShortcut(keyCode: r.trigger.keyCode, modifiers: r.trigger.requiredModifiers)
            },
            set: { new in
                mutate(rule.id) { current in
                    current.trigger.keyCode = new.keyCode
                    current.trigger.requiredModifiers = new.modifiers
                    // Most common accidental trigger: user actually still holds
                    // Cmd while capturing a Ctrl shortcut. Err toward safety and
                    // forbid Cmd when the captured trigger does not contain Cmd.
                    if !new.modifiers.contains(.cmd) {
                        current.trigger.forbiddenModifiers.insert(.cmd)
                    } else {
                        current.trigger.forbiddenModifiers.remove(.cmd)
                    }
                    refreshDerivedState(&current)
                }
            }
        )
    }

    private func outputBinding(for rule: RemapRule) -> Binding<CapturedShortcut> {
        Binding(
            get: {
                guard let r = currentRule(rule.id) else {
                    return CapturedShortcut(keyCode: RuleBook.unsetKeyCode, modifiers: [])
                }
                if r.trigger.keyCode == RuleBook.unsetKeyCode {
                    // Before a trigger is set we have no anchor to compute the
                    // effective output from. Show unset.
                    return CapturedShortcut(keyCode: RuleBook.unsetKeyCode, modifiers: [])
                }
                let effectiveMods = r.trigger.requiredModifiers
                    .subtracting(r.output.clearModifiers)
                    .union(r.output.setModifiers)
                return CapturedShortcut(
                    keyCode: r.output.keyCode ?? r.trigger.keyCode,
                    modifiers: effectiveMods
                )
            },
            set: { new in
                mutate(rule.id) { current in
                    current.output.keyCode = (new.keyCode == current.trigger.keyCode) ? nil : new.keyCode
                    current.output.setModifiers = new.modifiers.subtracting(current.trigger.requiredModifiers)
                    current.output.clearModifiers = current.trigger.requiredModifiers.subtracting(new.modifiers)
                    refreshDerivedState(&current)
                }
            }
        )
    }

    private func excludesBinding(for rule: RemapRule) -> Binding<[String]> {
        Binding(
            get: { currentRule(rule.id)?.excludeBundleIDs ?? [] },
            set: { new in mutate(rule.id) { $0.excludeBundleIDs = new } }
        )
    }

    // MARK: - Derivation helpers

    /// Called after any trigger/output mutation. Regenerates the default
    /// name (when the user hasn't overridden it) and auto-enables a
    /// previously-disabled fresh rule once both trigger and output are set.
    private func refreshDerivedState(_ rule: inout RemapRule) {
        if !rule.nameIsCustom {
            rule.name = RuleEditor.autoDerivedName(rule)
        }
        if !rule.enabled
            && rule.trigger.keyCode != RuleBook.unsetKeyCode
            && isOutputMeaningful(rule) {
            rule.enabled = true
        }
    }

    /// `true` when the rule's output actually differs from the trigger in
    /// some way — keyCode override, added modifier, or removed modifier.
    private func isOutputMeaningful(_ rule: RemapRule) -> Bool {
        rule.output.keyCode != nil
            || !rule.output.setModifiers.isEmpty
            || !rule.output.clearModifiers.isEmpty
    }

    static func autoDerivedName(_ rule: RemapRule) -> String {
        if rule.trigger.keyCode == RuleBook.unsetKeyCode {
            return "New rule"
        }
        let trigger = shortcutSymbol(
            keyCode: rule.trigger.keyCode,
            modifiers: rule.trigger.requiredModifiers
        )
        let effectiveMods = rule.trigger.requiredModifiers
            .subtracting(rule.output.clearModifiers)
            .union(rule.output.setModifiers)
        let output = shortcutSymbol(
            keyCode: rule.output.keyCode ?? rule.trigger.keyCode,
            modifiers: effectiveMods
        )
        return "\(trigger) → \(output)"
    }

    // MARK: - Store access

    private func currentRule(_ id: RemapRule.ID) -> RemapRule? {
        ruleStore.book.rules.first(where: { $0.id == id })
    }

    private func mutate(_ id: RemapRule.ID, _ transform: (inout RemapRule) -> Void) {
        var book = ruleStore.book
        guard let idx = book.rules.firstIndex(where: { $0.id == id }) else { return }
        transform(&book.rules[idx])
        ruleStore.save(book)
    }
}
