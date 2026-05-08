import AppKit
import SwiftUI

/// Top bar of the settings window: scheme picker + add / duplicate /
/// rename / delete. All mutations go through `SchemeStore`, which
/// persists and pushes changes through the engine hot-reload path.
struct SchemeToolbar: View {
    @ObservedObject var ruleStore: SchemeStore

    @State private var renameAlertPresented = false
    @State private var renameText = ""

    @State private var addAlertPresented = false
    @State private var addText = ""

    @State private var deleteAlertPresented = false

    var body: some View {
        HStack(spacing: 8) {
            Text("Scheme")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            schemePicker
                .frame(minWidth: 200, maxWidth: 320)

            Spacer().frame(width: 8)

            Button {
                addText = ""
                addAlertPresented = true
            } label: {
                Image(systemName: "plus")
            }
            .help("New empty scheme")

            Button {
                guard let active = activeScheme else { return }
                ruleStore.duplicateScheme(id: active.id)
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .help("Duplicate current scheme")

            Button {
                guard let active = activeScheme else { return }
                renameText = active.name
                renameAlertPresented = true
            } label: {
                Image(systemName: "pencil")
            }
            .help("Rename current scheme")

            Button {
                deleteAlertPresented = true
            } label: {
                Image(systemName: "minus")
            }
            .disabled(activeScheme?.isBuiltIn == true || ruleStore.library.schemes.count < 2)
            .help(deleteTooltip)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .alert("Rename scheme", isPresented: $renameAlertPresented) {
            TextField("Name", text: $renameText)
            Button("Save") {
                guard let active = activeScheme else { return }
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                ruleStore.renameScheme(id: active.id, to: trimmed)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New scheme", isPresented: $addAlertPresented) {
            TextField("Name", text: $addText)
            Button("Create") {
                let trimmed = addText.trimmingCharacters(in: .whitespacesAndNewlines)
                ruleStore.addScheme(name: trimmed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A fresh scheme starts empty — add rules in the list below.")
        }
        .alert("Delete scheme?", isPresented: $deleteAlertPresented) {
            Button("Delete", role: .destructive) {
                guard let active = activeScheme else { return }
                ruleStore.deleteScheme(id: active.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the scheme and its rules. Built-in schemes can't be deleted.")
        }
    }

    private var schemePicker: some View {
        Picker(
            "Active scheme",
            selection: Binding(
                get: { ruleStore.library.activeSchemeID },
                set: { ruleStore.selectScheme(id: $0) }
            )
        ) {
            ForEach(ruleStore.library.schemes) { scheme in
                Text(scheme.isBuiltIn ? "\(scheme.name) · built-in" : scheme.name)
                    .tag(scheme.id)
            }
        }
        .labelsHidden()
    }

    private var activeScheme: Scheme? {
        ruleStore.library.schemes.first(where: { $0.id == ruleStore.library.activeSchemeID })
    }

    private var deleteTooltip: String {
        if activeScheme?.isBuiltIn == true {
            return "Built-in schemes can't be deleted"
        }
        if ruleStore.library.schemes.count < 2 {
            return "Can't delete the only scheme"
        }
        return "Delete current scheme"
    }
}
