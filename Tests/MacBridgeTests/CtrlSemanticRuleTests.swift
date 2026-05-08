import XCTest
import CoreGraphics
@testable import MacBridge

final class CtrlSemanticRuleTests: XCTestCase {
    private var settings: AppSettings!
    private var frontmost: FrontmostAppTracker!
    private var rule: CtrlSemanticRule!
    private var postedEvents: [CGEvent]!

    override func setUp() {
        super.setUp()
        let suite = "CtrlSemanticRuleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = AppSettings(defaults: defaults)
        settings.ctrlSemanticEnabled = true
        frontmost = FrontmostAppTracker()
        postedEvents = []
        rule = CtrlSemanticRule(
            settings: settings,
            frontmost: frontmost,
            postEvent: { [weak self] event in
                self?.postedEvents.append(event)
            }
        )
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
        let result = rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .suppress)
        XCTAssertFalse(e.flags.contains(.maskControl))
        XCTAssertTrue(e.flags.contains(.maskCommand))
        XCTAssertEqual(postedEvents.count, 1)
        XCTAssertFalse(postedEvents[0].flags.contains(.maskControl))
        XCTAssertTrue(postedEvents[0].flags.contains(.maskCommand))
        XCTAssertEqual(
            postedEvents[0].getIntegerValueField(.eventSourceUserData),
            KeyRemapSyntheticEvent.userData
        )
    }

    func testKeyUpForRemappedShortcutStaysCmdEvenIfControlReleasedFirst() {
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let down = makeEvent(keyCode: 8, flags: .maskControl)
        XCTAssertEqual(rule.apply(to: down, type: .keyDown, context: ctx), .suppress)

        postedEvents.removeAll()
        let up = makeEvent(keyCode: 8, flags: [], keyDown: false)
        let result = rule.apply(to: up, type: .keyUp, context: ctx)

        XCTAssertEqual(result, .suppress)
        XCTAssertFalse(up.flags.contains(.maskControl))
        XCTAssertTrue(up.flags.contains(.maskCommand))
        XCTAssertEqual(postedEvents.count, 1)
        XCTAssertTrue(postedEvents[0].flags.contains(.maskCommand))
    }

    // MARK: Preserves Shift in Ctrl+Shift+T → Cmd+Shift+T

    func testCtrlShiftTPreservesShift() {
        let e = makeEvent(keyCode: 17, flags: [.maskControl, .maskShift])  // T
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .suppress)
        XCTAssertFalse(e.flags.contains(.maskControl))
        XCTAssertTrue(e.flags.contains(.maskCommand))
        XCTAssertTrue(e.flags.contains(.maskShift))
        XCTAssertEqual(postedEvents.count, 1)
    }

    // MARK: Terminal blacklist — no remap in Terminal.app

    func testCtrlCInTerminalIsNotRemapped() {
        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Terminal")
        let result = rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    func testCtrlCInITermIsNotRemapped() {
        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let ctx = KeyRemapContext(frontmostBundleID: "com.googlecode.iterm2")
        let result = rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    // MARK: Non-whitelisted keys — pass through

    func testCtrlHIsNotRemapped() {
        let e = makeEvent(keyCode: 4, flags: .maskControl)  // H key
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    func testCtrlSpaceIsNotRemapped() {
        let e = makeEvent(keyCode: 49, flags: .maskControl)  // Space
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    // MARK: Feature disabled

    func testDisabledSettingLeavesEventAlone() {
        settings.ctrlSemanticEnabled = false
        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = rule.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    // MARK: Cmd already held — don't double-process

    func testCtrlCmdComboIsNotRemapped() {
        let e = makeEvent(keyCode: 8, flags: [.maskControl, .maskCommand])
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = rule.apply(to: e, type: .keyDown, context: ctx)

        // Should be left as-is (both flags still present)
        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertTrue(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    // MARK: Not a key event

    func testNonKeyEventTypeIgnored() {
        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = rule.apply(to: e, type: .flagsChanged, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    func testKeyUpWithoutRemappedKeyDownPassesThrough() {
        let e = makeEvent(keyCode: 8, flags: .maskControl, keyDown: false)
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = rule.apply(to: e, type: .keyUp, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }
}
