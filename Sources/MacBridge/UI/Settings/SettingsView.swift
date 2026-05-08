import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ruleStore: SchemeStore
    @ObservedObject var eventTap: EventTapController

    @State private var selection: RemapRule.ID?

    var body: some View {
        VStack(spacing: 0) {
            SchemeToolbar(ruleStore: ruleStore)
            Divider()
            NavigationSplitView {
                ruleList
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
            } detail: {
                if let selection {
                    RuleEditor(ruleID: selection, ruleStore: ruleStore, eventTap: eventTap)
                        .id(selection)  // force-refresh editor when selection changes
                } else {
                    Text("Select a rule to edit, or add a new one")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 500)
        .onAppear {
            // LSUIElement=YES means the app is normally .accessory (no Dock icon).
            // While the settings window is visible we flip to .regular so it
            // can gain key-window focus and behave like a normal window.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if selection == nil { selection = ruleStore.book.rules.first?.id }
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
        .onChange(of: ruleStore.library.activeSchemeID) { _ in
            // Switching scheme means the current selection might be a rule
            // from a different scheme; reset so the user lands on something
            // from the new active book.
            selection = ruleStore.book.rules.first?.id
        }
    }

    private var ruleList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(ruleStore.book.rules) { rule in
                    ruleRow(rule)
                        .tag(rule.id)
                }
            }
            Divider()
            HStack(spacing: 8) {
                Button {
                    addRule()
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    deleteSelectedRule()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
                Spacer()
                Button("Reset to defaults") {
                    ruleStore.resetToDefaults()
                    selection = ruleStore.book.rules.first?.id
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: RemapRule) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: enabledBinding(for: rule))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).lineLimit(1)
                Text(triggerSummary(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func triggerSummary(_ rule: RemapRule) -> String {
        if rule.trigger.keyCode == RuleBook.unsetKeyCode {
            return "— not configured yet —"
        }
        let trigger = shortcutSymbol(keyCode: rule.trigger.keyCode, modifiers: rule.trigger.requiredModifiers)
        let outputMods = rule.trigger.requiredModifiers.subtracting(rule.output.clearModifiers).union(rule.output.setModifiers)
        let output = shortcutSymbol(keyCode: rule.output.keyCode ?? rule.trigger.keyCode, modifiers: outputMods)
        return "\(trigger)  →  \(output)"
    }

    // MARK: - Mutations

    private func enabledBinding(for rule: RemapRule) -> Binding<Bool> {
        Binding(
            get: { ruleStore.book.rules.first(where: { $0.id == rule.id })?.enabled ?? false },
            set: { newValue in
                var book = ruleStore.book
                guard let idx = book.rules.firstIndex(where: { $0.id == rule.id }) else { return }
                book.rules[idx].enabled = newValue
                ruleStore.save(book)
            }
        )
    }

    private func addRule() {
        // Rules start unset + disabled so the user is guided to capture the
        // trigger before the rule can fire. `enabled` flips on automatically
        // once they save a real trigger in the editor.
        let newRule = RemapRule(
            id: UUID(),
            name: "New rule",
            enabled: false,
            trigger: KeyTrigger(
                keyCode: RuleBook.unsetKeyCode,
                requiredModifiers: [],
                forbiddenModifiers: []
            ),
            output: KeyOutput(keyCode: nil, setModifiers: [], clearModifiers: []),
            excludeBundleIDs: SeedRules.defaultExcludeBundleIDs,
            isBuiltIn: false,
            nameIsCustom: false
        )
        var book = ruleStore.book
        book.rules.append(newRule)
        ruleStore.save(book)
        selection = newRule.id
    }

    private func deleteSelectedRule() {
        guard let id = selection else { return }
        var book = ruleStore.book
        book.rules.removeAll { $0.id == id }
        ruleStore.save(book)
        selection = ruleStore.book.rules.first?.id
    }
}
