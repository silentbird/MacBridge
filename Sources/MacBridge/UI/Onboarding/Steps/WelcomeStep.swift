import SwiftUI

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "keyboard")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.tint)

            Text("Welcome to MacBridge")
                .font(.title2.bold())

            Text("MacBridge remaps the few Windows keyboard habits that hurt the most on Mac — Ctrl+C, Ctrl+V, and friends — so the muscle memory you already have keeps working.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)

            Text("The next two steps grant the macOS permissions MacBridge needs and let you pick which external keyboards get the Windows-style modifier layout.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)

            Spacer()
        }
    }
}
