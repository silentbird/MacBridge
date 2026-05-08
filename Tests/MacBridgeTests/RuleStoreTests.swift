import XCTest
@testable import MacBridge

final class RuleStoreTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "RuleStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    func testEmptyStoreReturnsSeedBook() {
        let store = RuleStore(defaults: defaults)
        XCTAssertEqual(store.book.rules.count, SeedRules.defaultRules.count)
        XCTAssertEqual(store.book.version, RuleBook.currentVersion)
        XCTAssertTrue(store.book.rules.allSatisfy(\.isBuiltIn))
    }

    func testRoundTripPreservesRules() {
        let store = RuleStore(defaults: defaults)
        var book = store.book
        book.rules[0].enabled = false
        book.rules[0].name = "Custom name"
        store.save(book)

        let reopened = RuleStore(defaults: defaults)
        XCTAssertEqual(reopened.book.rules[0].name, "Custom name")
        XCTAssertFalse(reopened.book.rules[0].enabled)
    }

    func testResetToDefaultsRestoresSeed() {
        let store = RuleStore(defaults: defaults)
        var book = store.book
        book.rules.removeAll()
        store.save(book)
        XCTAssertEqual(store.book.rules.count, 0)

        store.resetToDefaults()
        XCTAssertEqual(store.book.rules.count, SeedRules.defaultRules.count)
    }

    func testCorruptPayloadFallsBackToSeed() {
        defaults.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: "remap.rulebook")
        let store = RuleStore(defaults: defaults)
        XCTAssertEqual(store.book.rules.count, SeedRules.defaultRules.count)
    }

    func testFutureVersionFallsBackToSeed() {
        let bogus = RuleBook(rules: [], version: 99)
        let data = try! JSONEncoder().encode(bogus)
        defaults.set(data, forKey: "remap.rulebook")

        let store = RuleStore(defaults: defaults)
        XCTAssertEqual(store.book.version, RuleBook.currentVersion)
        XCTAssertGreaterThan(store.book.rules.count, 0)
    }

    func testBookPublisherEmitsOnSave() {
        let store = RuleStore(defaults: defaults)
        var received: [Int] = []
        let sub = store.bookPublisher.sink { received.append($0.rules.count) }
        defer { sub.cancel() }

        var book = store.book
        book.rules.removeAll()
        store.save(book)

        XCTAssertEqual(received.last, 0)
    }
}
