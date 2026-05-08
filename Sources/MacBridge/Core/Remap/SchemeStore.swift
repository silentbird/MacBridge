import Combine
import Foundation

protocol RuleStoring: AnyObject {
    // View of the currently active scheme's rule book — unchanged contract
    // so RemapEngine and existing menu code keep working.
    var book: RuleBook { get }
    var bookPublisher: AnyPublisher<RuleBook, Never> { get }
    func save(_ book: RuleBook)            // writes into the active scheme
    func resetToDefaults()                 // resets the active scheme's book to seed

    // Scheme-library management
    var library: SchemeLibrary { get }
    var libraryPublisher: AnyPublisher<SchemeLibrary, Never> { get }
    @discardableResult func addScheme(name: String) -> UUID
    @discardableResult func duplicateScheme(id: UUID) -> UUID?
    func deleteScheme(id: UUID)
    func renameScheme(id: UUID, to name: String)
    func selectScheme(id: UUID)
}

/// Owns the `SchemeLibrary` and wires saves through to `SchemePersistence`.
/// Publishes both `library` (for scheme-management UI) and a derived
/// `book` (for the engine + rule editors). Subscribers don't need to know
/// there are multiple schemes — they still see a single active book.
final class SchemeStore: RuleStoring, ObservableObject {
    @Published private(set) var library: SchemeLibrary

    private let persistence: SchemePersistence
    private let legacyDefaults: UserDefaults?
    /// Legacy key used by the old UserDefaults-backed RuleStore.
    private static let legacyRuleBookKey = "remap.rulebook"

    var book: RuleBook { library.activeBook }

    var bookPublisher: AnyPublisher<RuleBook, Never> {
        $library
            .map { $0.activeBook }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var libraryPublisher: AnyPublisher<SchemeLibrary, Never> {
        $library.eraseToAnyPublisher()
    }

    init(persistence: SchemePersistence, legacyDefaults: UserDefaults? = .standard) {
        self.persistence = persistence
        self.legacyDefaults = legacyDefaults
        self.library = Self.initialLibrary(
            persistence: persistence,
            legacyDefaults: legacyDefaults
        )
        // Make sure whatever we ended up with is written to disk so the next
        // launch doesn't have to re-run migration logic.
        persist()
    }

    // MARK: - Rule-level writes (operate on active scheme)

    func save(_ book: RuleBook) {
        mutateActive { $0.book = book }
    }

    func resetToDefaults() {
        mutateActive { $0.book = SeedRules.defaultBook }
    }

    // MARK: - Scheme-level writes

    @discardableResult
    func addScheme(name: String) -> UUID {
        let now = Date()
        let scheme = Scheme(
            id: UUID(),
            name: name.isEmpty ? "Untitled scheme" : name,
            createdAt: now,
            modifiedAt: now,
            book: RuleBook(rules: [], version: RuleBook.currentVersion),
            isBuiltIn: false
        )
        var lib = library
        lib.schemes.append(scheme)
        lib.activeSchemeID = scheme.id
        library = lib
        persist()
        return scheme.id
    }

    @discardableResult
    func duplicateScheme(id: UUID) -> UUID? {
        guard let source = library.schemes.first(where: { $0.id == id }) else { return nil }
        let now = Date()
        var copy = source
        copy.id = UUID()
        copy.name = "\(source.name) Copy"
        copy.createdAt = now
        copy.modifiedAt = now
        copy.isBuiltIn = false
        var lib = library
        lib.schemes.append(copy)
        lib.activeSchemeID = copy.id
        library = lib
        persist()
        return copy.id
    }

    func deleteScheme(id: UUID) {
        // Never let the library go empty — the engine + UI need at least
        // one scheme at all times.
        guard library.schemes.count > 1 else { return }
        var lib = library
        lib.schemes.removeAll { $0.id == id }
        if lib.activeSchemeID == id {
            lib.activeSchemeID = lib.schemes.first?.id ?? lib.activeSchemeID
        }
        library = lib
        persist()
    }

    func renameScheme(id: UUID, to name: String) {
        mutate(schemeID: id) { $0.name = name }
    }

    func selectScheme(id: UUID) {
        guard library.schemes.contains(where: { $0.id == id }) else { return }
        guard id != library.activeSchemeID else { return }
        var lib = library
        lib.activeSchemeID = id
        library = lib
        persist()
    }

    // MARK: - Mutation helpers

    private func mutateActive(_ transform: (inout Scheme) -> Void) {
        mutate(schemeID: library.activeSchemeID, transform)
    }

    private func mutate(schemeID: UUID, _ transform: (inout Scheme) -> Void) {
        var lib = library
        guard let idx = lib.schemes.firstIndex(where: { $0.id == schemeID }) else { return }
        transform(&lib.schemes[idx])
        lib.schemes[idx].modifiedAt = Date()
        library = lib
        persist()
    }

    private func persist() {
        do {
            try persistence.save(library)
        } catch {
            NSLog("MacBridge: failed to persist scheme library: %@", String(describing: error))
        }
    }

    // MARK: - Initial-load logic

    private static func initialLibrary(
        persistence: SchemePersistence,
        legacyDefaults: UserDefaults?
    ) -> SchemeLibrary {
        // 1. Happy path — file is present and decodes.
        do {
            if let loaded = try persistence.load() {
                if loaded.libraryVersion == SchemeLibrary.currentLibraryVersion
                    && !loaded.schemes.isEmpty
                    && loaded.schemes.contains(where: { $0.id == loaded.activeSchemeID }) {
                    return loaded
                }
                // Library on disk is stale / malformed but non-empty — fall
                // through to migration/seeding which will overwrite it.
                NSLog("MacBridge: scheme library on disk is stale (v%d, %d schemes); reseeding",
                      loaded.libraryVersion, loaded.schemes.count)
            }
        } catch {
            NSLog("MacBridge: scheme library load failed (%@); reseeding", String(describing: error))
        }

        // 2. Migration path — upgrading from the UserDefaults-only era.
        if let defaults = legacyDefaults,
           let legacyData = defaults.data(forKey: legacyRuleBookKey),
           let legacyBook = try? JSONDecoder().decode(RuleBook.self, from: legacyData),
           legacyBook.version == RuleBook.currentVersion {
            defaults.removeObject(forKey: legacyRuleBookKey)
            let now = Date()
            let migrated = Scheme(
                id: UUID(),
                name: "Windows Migration (migrated)",
                createdAt: now,
                modifiedAt: now,
                book: legacyBook,
                isBuiltIn: true
            )
            return SchemeLibrary(
                schemes: [migrated],
                activeSchemeID: migrated.id,
                libraryVersion: SchemeLibrary.currentLibraryVersion
            )
        }

        // 3. Fresh install — just seed.
        return SeedRules.defaultLibrary()
    }
}
