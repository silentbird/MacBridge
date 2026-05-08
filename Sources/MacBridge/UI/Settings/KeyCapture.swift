import AppKit
import CoreGraphics
import SwiftUI

/// Pure-data capture result. KeyCaptureField and KeyCaptureSheet agree on this
/// shape; binding conversions live in RuleEditor.
struct CapturedShortcut: Equatable {
    var keyCode: CGKeyCode
    var modifiers: ModifierSet
}

/// Render a shortcut as "⌃⇧C" for menu display / captured preview.
func shortcutSymbol(keyCode: CGKeyCode, modifiers: ModifierSet) -> String {
    var out = ""
    if modifiers.contains(.ctrl)  { out += "⌃" }
    if modifiers.contains(.alt)   { out += "⌥" }
    if modifiers.contains(.shift) { out += "⇧" }
    if modifiers.contains(.cmd)   { out += "⌘" }
    if modifiers.contains(.fn)    { out += "fn " }
    out += keyLabel(keyCode)
    return out
}

/// Human-readable label for a virtual keyCode. Covers the keys the seed
/// rules use plus common navigation keys; anything else renders as hex.
func keyLabel(_ code: CGKeyCode) -> String {
    switch code {
    case 0:  return "A"
    case 1:  return "S"
    case 2:  return "D"
    case 3:  return "F"
    case 4:  return "H"
    case 5:  return "G"
    case 6:  return "Z"
    case 7:  return "X"
    case 8:  return "C"
    case 9:  return "V"
    case 11: return "B"
    case 12: return "Q"
    case 13: return "W"
    case 14: return "E"
    case 15: return "R"
    case 16: return "Y"
    case 17: return "T"
    case 31: return "O"
    case 32: return "U"
    case 34: return "I"
    case 35: return "P"
    case 37: return "L"
    case 38: return "J"
    case 40: return "K"
    case 45: return "N"
    case 46: return "M"
    case 36: return "⏎"
    case 48: return "⇥"
    case 49: return "Space"
    case 51: return "⌫"
    case 53: return "⎋"
    case 117: return "⌦"
    case 115: return "Home"
    case 119: return "End"
    case 116: return "PageUp"
    case 121: return "PageDn"
    case 123: return "←"
    case 124: return "→"
    case 125: return "↓"
    case 126: return "↑"
    case 122: return "F1"
    case 120: return "F2"
    case 99:  return "F3"
    case 118: return "F4"
    case 96:  return "F5"
    case 97:  return "F6"
    case 98:  return "F7"
    case 100: return "F8"
    case 101: return "F9"
    case 109: return "F10"
    case 103: return "F11"
    case 111: return "F12"
    default:  return String(format: "0x%02X", code)
    }
}

/// Click the field to open a dedicated capture sheet. We deliberately do NOT
/// start capturing inline — putting it in a sheet clarifies "you're in input
/// mode right now" vs. "this is just a label you can click".
struct KeyCaptureField: View {
    @Binding var shortcut: CapturedShortcut
    @ObservedObject var eventTap: EventTapController
    var title: String = "Shortcut"

    @State private var sheetPresented = false

    var body: some View {
        Button {
            sheetPresented = true
        } label: {
            HStack {
                mainLabel
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $sheetPresented) {
            KeyCaptureSheet(
                title: title,
                initial: shortcut,
                eventTap: eventTap,
                onCommit: { shortcut = $0 }
            )
        }
    }

    @ViewBuilder
    private var mainLabel: some View {
        if shortcut.keyCode == RuleBook.unsetKeyCode {
            Text("Click to set a shortcut…").foregroundStyle(.secondary)
        } else {
            Text(shortcutSymbol(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers))
        }
    }
}

/// Click-based shortcut picker. Uses a virtual keyboard so the user can pick
/// combos that the physical press-based capture couldn't (e.g. Cmd+Tab is
/// eaten by the system and never reaches our NSEvent monitor). Also safer
/// in general — no risk of recording the wrong combo because a modifier key
/// was still being held from the previous action.
struct KeyCaptureSheet: View {
    let title: String
    let initial: CapturedShortcut
    @ObservedObject var eventTap: EventTapController
    let onCommit: (CapturedShortcut) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedKey: CGKeyCode?
    @State private var selectedModifiers: ModifierSet
    @State private var monitor: Any?

    init(title: String, initial: CapturedShortcut, eventTap: EventTapController, onCommit: @escaping (CapturedShortcut) -> Void) {
        self.title = title
        self.initial = initial
        self.eventTap = eventTap
        self.onCommit = onCommit
        let initialKey: CGKeyCode? = initial.keyCode == RuleBook.unsetKeyCode ? nil : initial.keyCode
        _selectedKey = State(initialValue: initialKey)
        _selectedModifiers = State(initialValue: initial.modifiers)
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("Pick \(title.lowercased())")
                .font(.headline)

            Text("Press a combo on your keyboard, or click the chips and keys below. System shortcuts like Cmd+Tab are unreachable by physical press — click them instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            previewBox
            modifierChips
            keyboardRows

            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Clear") {
                    onCommit(CapturedShortcut(keyCode: RuleBook.unsetKeyCode, modifiers: []))
                    dismiss()
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    guard let key = selectedKey else { return }
                    onCommit(CapturedShortcut(keyCode: key, modifiers: selectedModifiers))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedKey == nil)
            }
        }
        .padding(20)
        .frame(width: 780)
        .onAppear {
            // Bypass the remap engine so Ctrl+C etc. aren't rewritten before
            // this monitor sees them, and attach a local keyDown/flagsChanged
            // watcher so physical presses populate the picker too.
            eventTap.isBypassed = true
            attachMonitor()
        }
        .onDisappear {
            eventTap.isBypassed = false
            detachMonitor()
        }
    }

    private func attachMonitor() {
        // Only .keyDown. We used to also listen for .flagsChanged to paint a
        // live modifier preview, but that event fires on sheet open with the
        // current (empty) physical state and wiped the pre-populated
        // selection. Reading modifiers off the keyDown event is enough.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {  // Esc — dismiss without committing
                dismiss()
                return nil
            }
            selectedKey = CGKeyCode(event.keyCode)
            let physical = modifiers(fromNSEvent: event.modifierFlags)
            // If the user pressed a real combo (physical modifiers present),
            // replace selection. If the press carries NO modifiers, preserve
            // whatever the user built via chip clicks — otherwise "click Cmd,
            // press Tab" would collapse back to bare Tab.
            if !physical.isEmpty {
                selectedModifiers = physical
            }
            return nil
        }
    }

    private func detachMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func modifiers(fromNSEvent flags: NSEvent.ModifierFlags) -> ModifierSet {
        var out: ModifierSet = []
        if flags.contains(.control)  { out.insert(.ctrl) }
        if flags.contains(.shift)    { out.insert(.shift) }
        if flags.contains(.option)   { out.insert(.alt) }
        if flags.contains(.command)  { out.insert(.cmd) }
        if flags.contains(.function) { out.insert(.fn) }
        return out
    }

    // MARK: - Subviews

    private var previewBox: some View {
        Text(previewText)
            .font(.system(size: 32, weight: .medium, design: .monospaced))
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedKey == nil ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(selectedKey == nil ? 0 : 1), lineWidth: 1)
            )
    }

    private var previewText: String {
        var mods = ""
        if selectedModifiers.contains(.ctrl)  { mods += "⌃" }
        if selectedModifiers.contains(.alt)   { mods += "⌥" }
        if selectedModifiers.contains(.shift) { mods += "⇧" }
        if selectedModifiers.contains(.cmd)   { mods += "⌘" }
        if selectedModifiers.contains(.fn)    { mods += "fn " }
        if let key = selectedKey {
            return mods + keyLabel(key)
        }
        if mods.isEmpty { return "…" }
        return mods + "·"
    }

    private var modifierChips: some View {
        HStack(spacing: 8) {
            Text("Modifiers:").font(.caption).foregroundStyle(.secondary)
            modChip("⌃ Ctrl",  .ctrl)
            modChip("⌥ Option", .alt)
            modChip("⇧ Shift",  .shift)
            modChip("⌘ Cmd",    .cmd)
            Spacer()
        }
    }

    private func modChip(_ label: String, _ mod: ModifierSet) -> some View {
        let on = selectedModifiers.contains(mod)
        return Button {
            if on { selectedModifiers.remove(mod) }
            else  { selectedModifiers.insert(mod) }
        } label: {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(on ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                )
                .foregroundStyle(on ? Color.white : Color.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Keyboard layout

    private var keyboardRows: some View {
        VStack(spacing: 4) {
            keyRow(VirtualKeyboard.functionRow)
            keyRow(VirtualKeyboard.numberRow)
            keyRow(VirtualKeyboard.qwertyRow)
            keyRow(VirtualKeyboard.asdfRow)
            keyRow(VirtualKeyboard.zxcvRow)
            keyRow(VirtualKeyboard.specialRow)
            keyRow(VirtualKeyboard.arrowRow)
        }
    }

    private func keyRow(_ keys: [VirtualKey]) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.code) { key in
                KeyCell(
                    def: key,
                    selected: selectedKey == key.code
                ) {
                    selectedKey = key.code
                }
            }
        }
    }

    // MARK: - Validation

    private var warning: String? {
        if selectedKey == nil && !selectedModifiers.isEmpty {
            return "Rules need a character key. For modifier-only swaps like Cmd↔Alt, use 'Swap Alt↔Cmd' in the Physical keyboards menu (it works at the kernel HID layer)."
        }
        if selectedKey != nil && selectedModifiers.isEmpty {
            return "No modifier selected. This will rebind the bare key — usually not what you want."
        }
        return nil
    }
}

// MARK: - Virtual keyboard model

private struct VirtualKey {
    let code: CGKeyCode
    let label: String
    var width: CGFloat = 1  // multiples of the base unit
}

private enum VirtualKeyboard {
    static let functionRow: [VirtualKey] = [
        VirtualKey(code: 53,  label: "Esc"),
        VirtualKey(code: 122, label: "F1"),
        VirtualKey(code: 120, label: "F2"),
        VirtualKey(code: 99,  label: "F3"),
        VirtualKey(code: 118, label: "F4"),
        VirtualKey(code: 96,  label: "F5"),
        VirtualKey(code: 97,  label: "F6"),
        VirtualKey(code: 98,  label: "F7"),
        VirtualKey(code: 100, label: "F8"),
        VirtualKey(code: 101, label: "F9"),
        VirtualKey(code: 109, label: "F10"),
        VirtualKey(code: 103, label: "F11"),
        VirtualKey(code: 111, label: "F12"),
    ]
    static let numberRow: [VirtualKey] = [
        VirtualKey(code: 50,  label: "`"),
        VirtualKey(code: 18,  label: "1"),
        VirtualKey(code: 19,  label: "2"),
        VirtualKey(code: 20,  label: "3"),
        VirtualKey(code: 21,  label: "4"),
        VirtualKey(code: 23,  label: "5"),
        VirtualKey(code: 22,  label: "6"),
        VirtualKey(code: 26,  label: "7"),
        VirtualKey(code: 28,  label: "8"),
        VirtualKey(code: 25,  label: "9"),
        VirtualKey(code: 29,  label: "0"),
        VirtualKey(code: 27,  label: "-"),
        VirtualKey(code: 24,  label: "="),
    ]
    static let qwertyRow: [VirtualKey] = [
        VirtualKey(code: 12, label: "Q"),
        VirtualKey(code: 13, label: "W"),
        VirtualKey(code: 14, label: "E"),
        VirtualKey(code: 15, label: "R"),
        VirtualKey(code: 17, label: "T"),
        VirtualKey(code: 16, label: "Y"),
        VirtualKey(code: 32, label: "U"),
        VirtualKey(code: 34, label: "I"),
        VirtualKey(code: 31, label: "O"),
        VirtualKey(code: 35, label: "P"),
        VirtualKey(code: 33, label: "["),
        VirtualKey(code: 30, label: "]"),
        VirtualKey(code: 42, label: "\\"),
    ]
    static let asdfRow: [VirtualKey] = [
        VirtualKey(code: 0,  label: "A"),
        VirtualKey(code: 1,  label: "S"),
        VirtualKey(code: 2,  label: "D"),
        VirtualKey(code: 3,  label: "F"),
        VirtualKey(code: 5,  label: "G"),
        VirtualKey(code: 4,  label: "H"),
        VirtualKey(code: 38, label: "J"),
        VirtualKey(code: 40, label: "K"),
        VirtualKey(code: 37, label: "L"),
        VirtualKey(code: 41, label: ";"),
        VirtualKey(code: 39, label: "'"),
    ]
    static let zxcvRow: [VirtualKey] = [
        VirtualKey(code: 6,  label: "Z"),
        VirtualKey(code: 7,  label: "X"),
        VirtualKey(code: 8,  label: "C"),
        VirtualKey(code: 9,  label: "V"),
        VirtualKey(code: 11, label: "B"),
        VirtualKey(code: 45, label: "N"),
        VirtualKey(code: 46, label: "M"),
        VirtualKey(code: 43, label: ","),
        VirtualKey(code: 47, label: "."),
        VirtualKey(code: 44, label: "/"),
    ]
    static let specialRow: [VirtualKey] = [
        VirtualKey(code: 48,  label: "Tab",     width: 1.4),
        VirtualKey(code: 49,  label: "Space",   width: 4),
        VirtualKey(code: 36,  label: "Return",  width: 1.7),
        VirtualKey(code: 51,  label: "⌫",       width: 1.4),
        VirtualKey(code: 117, label: "⌦",       width: 1.2),
    ]
    static let arrowRow: [VirtualKey] = [
        VirtualKey(code: 123, label: "←"),
        VirtualKey(code: 125, label: "↓"),
        VirtualKey(code: 126, label: "↑"),
        VirtualKey(code: 124, label: "→"),
        VirtualKey(code: 115, label: "Home"),
        VirtualKey(code: 119, label: "End"),
        VirtualKey(code: 116, label: "PgUp"),
        VirtualKey(code: 121, label: "PgDn"),
    ]
}

private struct KeyCell: View {
    let def: VirtualKey
    let selected: Bool
    let onTap: () -> Void

    private static let unit: CGFloat = 40

    var body: some View {
        Button(action: onTap) {
            Text(def.label)
                .font(.system(.footnote, design: .monospaced))
                .frame(width: Self.unit * def.width, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
    }
}
