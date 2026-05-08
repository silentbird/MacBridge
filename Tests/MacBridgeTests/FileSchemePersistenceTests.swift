import XCTest
@testable import MacBridge

final class FileSchemePersistenceTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FileSchemePersistenceTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func makePersistence() -> FileSchemePersistence {
        let fileURL = tmpDir.appendingPathComponent("library.json")
        return FileSchemePersistence(fileURL: fileURL)
    }

    func testLoadWhenMissingReturnsNil() throws {
        let p = makePersistence()
        XCTAssertNil(try p.load())
    }

    func testSaveThenLoadRoundTrips() throws {
        let p = makePersistence()
        let lib = SeedRules.defaultLibrary()
        try p.save(lib)

        let loaded = try p.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.schemes.count, lib.schemes.count)
        XCTAssertEqual(loaded?.activeSchemeID, lib.activeSchemeID)
        XCTAssertEqual(loaded?.libraryVersion, lib.libraryVersion)
        XCTAssertEqual(loaded?.schemes.first?.name, "Windows Migration")
    }

    func testSaveCreatesMissingDirectory() throws {
        let p = makePersistence()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir.path))
        try p.save(SeedRules.defaultLibrary())
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpDir.path))
    }

    func testSaveIsAtomicOverwrite() throws {
        let p = makePersistence()
        try p.save(SeedRules.defaultLibrary())

        var edited = SeedRules.defaultLibrary()
        edited.schemes[0].name = "Renamed"
        try p.save(edited)

        let reloaded = try p.load()
        XCTAssertEqual(reloaded?.schemes.first?.name, "Renamed")

        // And there should be no leftover tmp file.
        let tmp = tmpDir.appendingPathComponent("library.json.tmp")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
    }

    func testCorruptFileThrowsDecodeFailed() throws {
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let fileURL = tmpDir.appendingPathComponent("library.json")
        try "not actually json".write(to: fileURL, atomically: true, encoding: .utf8)

        let p = FileSchemePersistence(fileURL: fileURL)
        XCTAssertThrowsError(try p.load()) { error in
            guard case SchemePersistenceError.decodeFailed = error else {
                return XCTFail("Expected decodeFailed, got \(error)")
            }
        }
    }
}
