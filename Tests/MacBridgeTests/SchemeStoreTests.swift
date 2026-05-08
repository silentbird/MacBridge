import XCTest
@testable import MacBridge

final class SchemeStoreTests: XCTestCase {
    private var persistence: InMemorySchemePersistence!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        persistence = InMemorySchemePersistence()
        defaults = UserDefaults(suiteName: "SchemeStoreTests-\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().description)
    }

    // MARK: Seeding & migration

    func testEmptyPersistenceSeedsDefaultLibrary() {
        let store = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        XCTAssertEqual(store.library.schemes.count, 1)
        XCTAssertEqual(store.library.schemes[0].name, "Windows Migration")
        XCTAssertTrue(store.library.schemes[0].isBuiltIn)
        XCTAssertEqual(store.library.activeSchemeID, store.library.schemes[0].id)
        XCTAssertEqual(store.book.rules.count, SeedRules.defaultRules.count)
    }

    func testLegacyUserDefaultsIsMigratedAndCleared() {
        // Simulate the old RuleStore having saved a customized book.
        var legacy = SeedRules.defaultBook
        legacy.rules[0].enabled = false
        legacy.rules[0].name = "Pre-migration Copy"
        let legacyData = try! JSONEncoder().encode(legacy)
        defaults.set(legacyData, forKey: "remap.rulebook")

        let store = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        XCTAssertEqual(store.library.schemes.count, 1)
        XCTAssertTrue(store.library.schemes[0].name.contains("migrated"))
        XCTAssertEqual(store.book.rules[0].name, "Pre-migration Copy")
        XCTAssertFalse(store.book.rules[0].enabled)
        // Old key removed so the migration doesn't run twice on next launch.
        XCTAssertNil(defaults.data(forKey: "remap.rulebook"))
    }

    func testCorruptLibraryOnDiskFallsBackToSeed() throws {
        // Craft an "invalid" library by writing a library whose activeID
        // points at nothing.
        let bogus = SchemeLibrary(
            schemes: [],
            activeSchemeID: UUID(),
            libraryVersion: SchemeLibrary.currentLibraryVersion
        )
        try persistence.save(bogus)

        let store = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        XCTAssertEqual(store.library.schemes.count, 1)
        XCTAssertEqual(store.library.schemes.first?.name, "Windows Migration")
    }

    // MARK: Rule-level writes target the active scheme

    func testSaveUpdatesOnlyActiveScheme() {
        let store = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        let originalID = store.library.activeSchemeID
        let newID = store.addScheme(name: "Gaming")
        XCTAssertEqual(store.library.activeSchemeID, newID)
        // Now save an edit while Gaming is active.
        var edited = store.book
        edited.rules = []
        store.save(edited)

        XCTAssertEqual(store.book.rules.count, 0, "Gaming should be empty")
        store.selectScheme(id: originalID)
        XCTAssertEqual(store.book.rules.count, SeedRules.defaultRules.count, "Original scheme untouched")
    }

    // MARK: Scheme management

    func testAddSchemeActivatesIt() {
        let store = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        let id = store.addScheme(name: "Gaming")
        XCTAssertEqual(store.library.activeSchemeID, id)
        XCTAssertEqual(store.library.schemes.last?.name, "Gaming")
        XCTAssertFalse(store.library.schemes.last?.isBuiltIn ?? true)
    }

    func testDuplicateCopiesBookAndSuffixesName() {
        let store = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        let originalID = store.library.activeSchemeID
        let dupID = store.duplicateScheme(id: originalID)!
        XCTAssertNotEqual(originalID, dupID)
        let dup = store.library.schemes.first(where: { $0.id == dupID })!
        XCTAssertTrue(dup.name.hasSuffix("Copy"))
        XCTAssertFalse(dup.isBuiltIn)
        XCTAssertEqual(dup.book.rules.count, SeedRules.defaultRules.count)
    }

    func testDeleteSchemeCannotEmptyLibrary() {
        let store = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        let onlyID = store.library.activeSchemeID
        store.deleteScheme(id: onlyID)
        XCTAssertEqual(store.library.schemes.count, 1, "Deleting the last scheme is a no-op")
    }

    func testDeleteActiveReassignsActive() {
        let store = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        let originalID = store.library.activeSchemeID
        let secondID = store.addScheme(name: "Gaming")
        store.deleteScheme(id: secondID)
        XCTAssertEqual(store.library.activeSchemeID, originalID)
        XCTAssertEqual(store.library.schemes.count, 1)
    }

    func testRenameUpdatesNameAndModifiedAt() {
        let store = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        let originalID = store.library.activeSchemeID
        let before = store.library.schemes[0].modifiedAt
        Thread.sleep(forTimeInterval: 0.01)
        store.renameScheme(id: originalID, to: "Renamed")
        XCTAssertEqual(store.library.schemes[0].name, "Renamed")
        XCTAssertGreaterThan(store.library.schemes[0].modifiedAt, before)
    }

    func testSelectSchemeSwapsActiveBook() {
        let store = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        let originalID = store.library.activeSchemeID
        let emptyID = store.addScheme(name: "Empty")
        var emptyBook = store.book
        emptyBook.rules = []
        store.save(emptyBook)
        XCTAssertEqual(store.book.rules.count, 0)

        store.selectScheme(id: originalID)
        XCTAssertEqual(store.book.rules.count, SeedRules.defaultRules.count)

        store.selectScheme(id: emptyID)
        XCTAssertEqual(store.book.rules.count, 0)
    }

    // MARK: Persistence

    func testWritesAreRoundTrippedThroughPersistence() {
        let store = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        store.addScheme(name: "Gaming")

        // Simulate a relaunch reading the same persistence backend.
        let reopened = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        XCTAssertEqual(reopened.library.schemes.count, 2)
        XCTAssertEqual(reopened.library.schemes.last?.name, "Gaming")
    }

    func testBookPublisherEmitsOnSchemeSwitch() {
        let store = SchemeStore(persistence: persistence, legacyDefaults: defaults)
        var bookCounts: [Int] = []
        let sub = store.bookPublisher.sink { bookCounts.append($0.rules.count) }
        defer { sub.cancel() }

        // Starting count.
        XCTAssertEqual(bookCounts.first, SeedRules.defaultRules.count)

        let emptyID = store.addScheme(name: "Empty")
        // addScheme implicitly activates the new empty scheme.
        XCTAssertEqual(bookCounts.last, 0)

        // Flip back and we should see the seed count again.
        let originalID = store.library.schemes.first!.id
        store.selectScheme(id: originalID)
        XCTAssertEqual(bookCounts.last, SeedRules.defaultRules.count)

        _ = emptyID
    }
}
