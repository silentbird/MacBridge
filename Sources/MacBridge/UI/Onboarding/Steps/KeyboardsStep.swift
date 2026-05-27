import SwiftUI

struct KeyboardsStep: View {
    @ObservedObject var detector: KeyboardDetector
    @ObservedObject var profileManager: ProfileManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MacBridge detected the following keyboards. Enable Swap Alt↔Cmd on any external Windows-layout keyboard so the bottom-row modifiers match what's printed on the keycaps.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if detector.devices.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(detector.devices) { device in
                        row(for: device)
                    }
                }
                .listStyle(.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let err = profileManager.lastError {
                Text("⚠️ \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("You can change these later from the menu bar at any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No external keyboards detected")
                .font(.body)
            Text("Plug in a keyboard now to configure it, or do this later from the menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func row(for device: KeyboardDevice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.productName).font(.body.weight(.medium))
                Text(String(format: "Vendor 0x%04X · Product 0x%04X", device.vendorID, device.productID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Swap Alt↔Cmd", isOn: swapBinding(for: device))
                .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }

    private func swapBinding(for device: KeyboardDevice) -> Binding<Bool> {
        Binding(
            get: { profileManager.profile(for: device).swapModifiers },
            set: { profileManager.setSwapEnabled($0, for: device) }
        )
    }
}
