import Foundation

/// Abstract I/O boundary for the scheme library. The single-file JSON impl
/// is `FileSchemePersistence` below; future iCloud / CloudKit backends
/// implement the same protocol so `SchemeStore` doesn't need to care
/// where the bytes live.
protocol SchemePersistence {
    /// Returns nil when the store is empty (first launch). Throws on
    /// read / decode errors so the caller can distinguish "never written"
    /// from "written but corrupt".
    func load() throws -> SchemeLibrary?
    func save(_ library: SchemeLibrary) throws
}

enum SchemePersistenceError: Error {
    case decodeFailed(underlying: Error)
    case encodeFailed(underlying: Error)
}

/// Stores the library at:
///   ~/Library/Application Support/MacBridge/library.json
/// Writes atomically via a sibling `.tmp` + `FileManager.replaceItemAt`
/// so a crash mid-write can never leave a half-written file on disk.
final class FileSchemePersistence: SchemePersistence {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL(using: fileManager)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() throws -> SchemeLibrary? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        do {
            return try decoder.decode(SchemeLibrary.self, from: data)
        } catch {
            throw SchemePersistenceError.decodeFailed(underlying: error)
        }
    }

    func save(_ library: SchemeLibrary) throws {
        let data: Data
        do {
            data = try encoder.encode(library)
        } catch {
            throw SchemePersistenceError.encodeFailed(underlying: error)
        }
        try ensureContainerExists()
        let tmpURL = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmpURL, options: [.atomic])
        // If the target doesn't exist yet, replaceItemAt returns nil with
        // no error — the tmp is left in place, so rename manually.
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: tmpURL)
        } else {
            try fileManager.moveItem(at: tmpURL, to: fileURL)
        }
    }

    private func ensureContainerExists() throws {
        let dir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func defaultFileURL(using fileManager: FileManager = .default) -> URL {
        let supportDir = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = supportDir ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("MacBridge", isDirectory: true)
            .appendingPathComponent("library.json")
    }
}

/// Pure in-memory persistence. Used by tests and by any future "no-op"
/// path where we want to run the store without touching the filesystem.
final class InMemorySchemePersistence: SchemePersistence {
    private var stored: SchemeLibrary?

    init(initial: SchemeLibrary? = nil) {
        self.stored = initial
    }

    func load() throws -> SchemeLibrary? { stored }
    func save(_ library: SchemeLibrary) throws { stored = library }
}
