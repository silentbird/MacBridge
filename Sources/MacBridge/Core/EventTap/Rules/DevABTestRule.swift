import CoreGraphics
import Foundation

/// Dev-only sanity check carried from the POC: press A, get B. Kept so we
/// can verify the tap is actually intercepting events when real rules fall
/// silent (e.g. in terminal, where the CtrlSemanticRule opts out).
final class DevABTestRule: KeyRemapRule {
    private let isEnabled: () -> Bool

    init(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
    }

    func apply(to event: CGEvent, type: CGEventType, context: KeyRemapContext) -> KeyRemapResult {
        guard isEnabled() else { return .pass }
        guard type == .keyDown || type == .keyUp else { return .pass }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 0 {  // A
            event.setIntegerValueField(.keyboardEventKeycode, value: 11)  // B
        }
        return .pass
    }
}
