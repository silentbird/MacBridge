import XCTest
import CoreGraphics
@testable import MacBridge

/// Exercises the engine with non-seed rules — the scenarios P3 unlocks once
/// users can author their own shortcuts.
final class RuleEngineCustomRuleTests: XCTestCase {
    private var settings: AppSettings!
    private var frontmost: FrontmostAppTracker!
    private var store: SchemeStore!
    private var engine: RemapEngine!
    private var postedEvents: [CGEvent]!

    override func setUp() {
        super.setUp()
        let suite = "RuleEngineCustomRuleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = AppSettings(defaults: defaults)
        settings.remapEngineEnabled = true
        frontmost = FrontmostAppTracker()
        store = SchemeStore(persistence: InMemorySchemePersistence(), legacyDefaults: defaults)
        postedEvents = []
    }

    private func installRules(_ rules: [RemapRule]) {
        store.save(RuleBook(rules: rules, version: RuleBook.currentVersion))
        engine = RemapEngine(
            settings: settings,
            frontmost: frontmost,
            store: store,
            postEvent: { [weak self] event in
                self?.postedEvents.append(event)
            }
        )
    }

    private func makeEvent(keyCode: Int64, flags: CGEventFlags, keyDown: Bool = true) -> CGEvent {
        let src = CGEventSource(stateID: .privateState)
        let e = CGEvent(
            keyboardEventSource: src,
            virtualKey: CGKeyCode(keyCode),
            keyDown: keyDown
        )!
        e.flags = flags
        return e
    }

    // MARK: Custom key-to-key remap (output keyCode != trigger keyCode)

    func testAltQToCmdWClosesTab() {
        // Alt+Q → Cmd+W  (made-up rule: close the current tab via the old Win shortcut)
        let rule = RemapRule(
            id: UUID(),
            name: "Alt+Q → Cmd+W",
            enabled: true,
            trigger: KeyTrigger(
                keyCode: 12,  // Q
                requiredModifiers: [.alt],
                forbiddenModifiers: [.cmd]
            ),
            output: KeyOutput(
                keyCode: 13,  // W
                setModifiers: [.cmd],
                clearModifiers: [.alt]
            ),
            excludeBundleIDs: [],
            isBuiltIn: false
        )
        installRules([rule])

        let e = makeEvent(keyCode: 12, flags: .maskAlternate)
        let result = engine.apply(to: e, type: .keyDown, context: KeyRemapContext(frontmostBundleID: "com.apple.Safari"))

        XCTAssertEqual(result, .suppress)
        XCTAssertEqual(e.getIntegerValueField(.keyboardEventKeycode), 13)
        XCTAssertTrue(e.flags.contains(.maskCommand))
        XCTAssertFalse(e.flags.contains(.maskAlternate))
        XCTAssertEqual(postedEvents.count, 1)
    }

    // MARK: Ordering — first enabled rule wins

    func testFirstMatchingRuleWins() {
        let first = RemapRule(
            id: UUID(),
            name: "First",
            enabled: true,
            trigger: KeyTrigger(keyCode: 8, requiredModifiers: [.ctrl], forbiddenModifiers: [.cmd]),
            output: KeyOutput(keyCode: nil, setModifiers: [.cmd], clearModifiers: [.ctrl]),
            excludeBundleIDs: [],
            isBuiltIn: false
        )
        let second = RemapRule(
            id: UUID(),
            name: "Second",
            enabled: true,
            trigger: KeyTrigger(keyCode: 8, requiredModifiers: [.ctrl], forbiddenModifiers: [.cmd]),
            output: KeyOutput(keyCode: nil, setModifiers: [.alt], clearModifiers: [.ctrl]),
            excludeBundleIDs: [],
            isBuiltIn: false
        )
        installRules([first, second])

        let e = makeEvent(keyCode: 8, flags: .maskControl)
        let result = engine.apply(to: e, type: .keyDown, context: KeyRemapContext(frontmostBundleID: "com.apple.Safari"))

        XCTAssertEqual(result, .suppress)
        XCTAssertTrue(e.flags.contains(.maskCommand))
        XCTAssertFalse(e.flags.contains(.maskAlternate))
    }

    // MARK: Store change hot-reloads the engine

    func testStoreMutationRebuildsIndex() {
        installRules([])  // start empty, engine sees no rules

        let ctx = KeyRemapContext(frontmostBundleID: "com.apple.Safari")
        let before = makeEvent(keyCode: 8, flags: .maskControl)
        XCTAssertEqual(engine.apply(to: before, type: .keyDown, context: ctx), .pass)

        // Install a rule after the engine is alive.
        let added = RemapRule(
            id: UUID(),
            name: "Late Copy",
            enabled: true,
            trigger: KeyTrigger(keyCode: 8, requiredModifiers: [.ctrl], forbiddenModifiers: [.cmd]),
            output: KeyOutput(keyCode: nil, setModifiers: [.cmd], clearModifiers: [.ctrl]),
            excludeBundleIDs: [],
            isBuiltIn: false
        )
        store.save(RuleBook(rules: [added], version: RuleBook.currentVersion))

        let after = makeEvent(keyCode: 8, flags: .maskControl)
        XCTAssertEqual(engine.apply(to: after, type: .keyDown, context: ctx), .suppress)
    }
}
