import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var state: OnboardingState
    @ObservedObject var detector: KeyboardDetector
    @ObservedObject var profileManager: ProfileManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            Divider()
            footer
        }
        .frame(width: 560, height: 420)
        .onAppear {
            // LSUIElement=YES → app is .accessory by default; flip to .regular
            // so this window can take key-window focus and respond to clicks.
            // Mirrors `SettingsView`'s pattern.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            state.startPolling()
        }
        .onDisappear {
            state.stopPolling()
            // Skip and close are equivalent per spec — both mark completion
            // so the wizard does not re-pop next launch (it can still re-pop
            // on the missing-permission trigger).
            state.markCompleted()
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var header: some View {
        let total = OnboardingStep.allCases.count
        let n = state.currentStep.rawValue + 1
        HStack {
            Text("Step \(n) of \(total) · \(state.currentStep.title)")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch state.currentStep {
        case .welcome:
            WelcomeStep()
        case .permissions:
            PermissionsStep(state: state)
        case .keyboards:
            KeyboardsStep(detector: detector, profileManager: profileManager)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Button("Back") { goBack() }
                .disabled(state.currentStep == .welcome)

            Spacer()

            // Skip is only shown on Permissions — it's the only step where
            // walking away leaves the app in a degraded state. The menu bar
            // surfaces a warning row to make that recoverable.
            if state.currentStep == .permissions {
                Button("Skip") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Button(state.currentStep == .keyboards ? "Done" : "Next") {
                if state.currentStep == .keyboards {
                    dismiss()
                } else {
                    goNext()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func goBack() {
        guard let prev = OnboardingStep(rawValue: state.currentStep.rawValue - 1) else { return }
        state.currentStep = prev
    }

    private func goNext() {
        guard let next = OnboardingStep(rawValue: state.currentStep.rawValue + 1) else { return }
        state.currentStep = next
    }
}
