import XCTest
import CoreGraphics
@testable import MacBridge

/// Verifies that the data-driven `RemapEngine`, seeded with `SeedRules.defaultBook`,
/// reproduces the behavior the old hardcoded `CtrlSemanticRule` was verified against.
/// Every test here mirrors a corresponding case from the pre-refactor test file.
final class RemapEngineTests: XCTestCase {
    private var settings: AppSettings!
    private var frontmost: FrontmostAppTracker!
    private var store: SchemeStore!
    private var engine: RemapEngine!
    private var postedEvents: [CGEvent]!

    override func setUp() {
        super.setUp()
        let suite = "RemapEngineTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = AppSettings(defaults: defaults)
        settings.remapEngineEnabled = true
        frontmost = FrontmostAppTracker()
        store = SchemeStore(persistence: InMemorySchemePersistence(), legacyDefaults: defaults)
        postedEvents = []
        engine = RemapEngine(
            settings: settings,
            frontmost: frontmost,
            store: store,
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
        let result = engine.apply(to: e, type: .keyDown, context: ctx)

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
        XCTAssertEqual(engine.apply(to: down, type: .keyDown, context: ctx), .suppress)

        postedEvents.removeAll()
        let up = makeEvent(keyCode: 8, flags: [], keyDown: false)
        let result = engine.apply(to: up, type: .keyUp, context: ctx)

        XCTAssertEqual(result, .suppress)
        XCTAssertFalse(up.flags.contains(.maskControl))
        XCTAssertTrue(up.flags.contains(.maskCommand))
        XCTAssertEqual(postedEvents.count, 1)
        XCTAssertTrue(postedEvents[0].flags.contains(.maskCommand))
    }

    // MARK: Preserves Shift — Ctrl+Shift+T → Cmd+Shift+T

    func testCtrlShiftTPreservesShift() {
        let e = makeEvent(keyCode: 17, flags: [.maskControl, .maskShift])  // T
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = engine.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .suppress)
        XCTAssertFalse(e.flags.contains(.maskControl))
        XCTAssertTrue(e.flags.contains(.maskCommand))
        XCTAssertTrue(e.flags.contains(.maskShift))
        XCTAssertEqual(postedEvents.count, 1)
    }

    // MARK: Terminal exclude list

    func testCtrlCInTerminalIsNotRemapped() {
        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Terminal")
        let result = engine.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    func testCtrlCInITermIsNotRemapped() {
        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let ctx = KeyRemapContext(frontmostBundleID: "com.googlecode.iterm2")
        let result = engine.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    // MARK: Non-whitelisted keys pass through

    func testCtrlHIsNotRemapped() {
        let e = makeEvent(keyCode: 4, flags: .maskControl)  // H key
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = engine.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    func testCtrlSpaceIsNotRemapped() {
        let e = makeEvent(keyCode: 49, flags: .maskControl)  // Space
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = engine.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    // MARK: Master kill switch

    func testDisabledSettingLeavesEventAlone() {
        settings.remapEngineEnabled = false
        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = engine.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    // MARK: Cmd already held — forbiddenModifiers keeps us out

    func testCtrlCmdComboIsNotRemapped() {
        let e = makeEvent(keyCode: 8, flags: [.maskControl, .maskCommand])
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = engine.apply(to: e, type: .keyDown, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertTrue(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    // MARK: Event type filter

    func testNonKeyEventTypeIgnored() {
        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = engine.apply(to: e, type: .flagsChanged, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    func testKeyUpWithoutRemappedKeyDownPassesThrough() {
        let e = makeEvent(keyCode: 8, flags: .maskControl, keyDown: false)
        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let result = engine.apply(to: e, type: .keyUp, context: ctx)

        XCTAssertEqual(result, .pass)
        XCTAssertTrue(e.flags.contains(.maskControl))
        XCTAssertFalse(e.flags.contains(.maskCommand))
        XCTAssertTrue(postedEvents.isEmpty)
    }

    // MARK: Disabling a single rule still leaves others intact

    func testDisablingOneRuleOnlySkipsThatTrigger() {
        // Disable "Copy" (Ctrl+C) — Paste (Ctrl+V) must still remap.
        var book = store.book
        if let idx = book.rules.firstIndex(where: { $0.trigger.keyCode == SeedRules.keyC
            && $0.trigger.requiredModifiers == [.ctrl] }) {
            book.rules[idx].enabled = false
        }
        store.save(book)

        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let ctrlC = makeEvent(keyCode: 8, flags: .maskControl)
        XCTAssertEqual(engine.apply(to: ctrlC, type: .keyDown, context: ctx), .pass)

        let ctrlV = makeEvent(keyCode: 9, flags: .maskControl)
        XCTAssertEqual(engine.apply(to: ctrlV, type: .keyDown, context: ctx), .suppress)
        XCTAssertTrue(ctrlV.flags.contains(.maskCommand))
    }
}
