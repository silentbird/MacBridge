import SwiftUI

struct PermissionsStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MacBridge needs three macOS permissions to observe and remap keystrokes. Click Grant to open the matching System Settings pane — the status here updates automatically.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            row(
                kind: .accessibility,
                title: "Accessibility",
                detail: "Lets MacBridge intercept and rewrite keyboard events globally.",
                granted: state.permissionStatus.accessibility
            )
            row(
                kind: .inputMonitoring,
                title: "Input Monitoring",
                detail: "Lets MacBridge see keystrokes before deciding whether to rewrite them.",
                granted: state.permissionStatus.inputMonitoring
            )
            row(
                kind: .postEvents,
                title: "Post Events",
                detail: "Lets MacBridge replace a keystroke with the rewritten one.",
                granted: state.permissionStatus.postEvents
            )

            Spacer()

            if !state.permissionStatus.allGranted {
                Text("You can Skip and grant these later — the menu bar will keep a reminder until they're all enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func row(kind: PermissionKind, title: String, detail: String, granted: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Text("Granted").foregroundStyle(.secondary).font(.callout)
            } else {
                Button("Grant…") { state.requestPermission(kind) }
            }
        }
        .padding(.vertical, 6)
    }
}
