import XCTest
import CoreGraphics
@testable import MacBridge

final class CtrlSemanticRuleTests: XCTestCase {
    private var settings: AppSettings!
    private var frontmost: FrontmostAppTracker!
    private var rule: CtrlSemanticRule!

    override func setUp() {
        super.setUp()
        let suite = "CtrlSemanticRuleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = AppSettings(defaults: defaults)
        settings.ctrlSemanticEnabled = true
        frontmost = FrontmostAppTracker()
        rule = CtrlSemanticRule(settings: settings, frontmost: frontmost)
    }

    // MARK: Helpers

    private func makeEvent(
        keyCode: Int64,
        flags: CGEventFlags,
        keyDown: Bool = true
    ) -> CGEvent {
        let src = CGEventSource(stateID: .privateState)
        let e = CGEvent(
            keyboardEventSource: src,
            virtualKey: CGKeyCode(keyCode),
            keyDown: keyDown
        )!
        e.flags = flags
        return e
    }

    // MARK: Ctrl+C in a normal app → becomes Cmd+C

    func testCtrlCInNormalAppBecomesCmdC() {
        let e = makeEvent(keyCode: 8, flags: .maskControl)  // C key
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertFalse(e.flags.contains(.maskControl))
        XCTAssertTrue(e.flags.contains(.maskCommand))
    }

    // MARK: Preserves Shift in Ctrl+Shift+T → Cmd+Shift+T

    func testCtrlShiftTPreservesShift() {
        let e = makeEvent(keyCode: 17, flags: [.maskControl, .maskShift])  // T
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertFalse(e.flags.contains(.maskControl))
        XCTAssertTrue(e.flags.contains(.maskCommand))
        XCTAssertTrue(e.flags.contains(.maskShift))
    }

    // MARK: Terminal blacklist — no remap in Terminal.app

    func testCtrlCInTerminalIsNotRemapped() {
        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Terminal")
        rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
    }

    func testCtrlCInITermIsNotRemapped() {
        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let ctx = KeyRemapContext(frontmostBundleID: "com.googlecode.iterm2")
        rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
    }

    // MARK: Non-whitelisted keys — pass through

    func testCtrlHIsNotRemapped() {
        let e = makeEvent(keyCode: 4, flags: .maskControl)  // H key
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
    }

    func testCtrlSpaceIsNotRemapped() {
        let e = makeEvent(keyCode: 49, flags: .maskControl)  // Space
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
    }

    // MARK: Feature disabled

    func testDisabledSettingLeavesEventAlone() {
        settings.ctrlSemanticEnabled = false
        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
    }

    // MARK: Cmd already held — don't double-process

    func testCtrlCmdComboIsNotRemapped() {
        let e = makeEvent(keyCode: 8, flags: [.maskControl, .maskCommand])
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        rule.apply(to: e, type: .keyDown, context: ctx)

        // Should be left as-is (both flags still present)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertTrue(e.flags.contains(.maskCommand))
    }

    // MARK: Not a key event

    func testNonKeyEventTypeIgnored() {
        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        rule.apply(to: e, type: .flagsChanged, context: ctx)

        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
    }
}
