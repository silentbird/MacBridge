import Combine
import Foundation

protocol RuleStoring: AnyObject {
    var book: RuleBook { get }
    var bookPublisher: AnyPublisher<RuleBook, Never> { get }
    func save(_ book: RuleBook)
    func resetToDefaults()
}

/// UserDefaults-backed rulebook store. Publishes `book` updates so the engine
/// and UI can hot-react to user edits without restarting the event tap.
final class RuleStore: RuleStoring, ObservableObject {
    @Published private(set) var book: RuleBook

    var bookPublisher: AnyPublisher<RuleBook, Never> {
        $book.eraseToAnyPublisher()
    }

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "remap.rulebook") {
        self.defaults = defaults
        self.key = key
        self.book = Self.loadBook(from: defaults, key: key)
    }

    func save(_ book: RuleBook) {
        self.book = book
        guard let data = try? JSONEncoder().encode(book) else { return }
        defaults.set(data, forKey: key)
    }

    func resetToDefaults() {
        defaults.removeObject(forKey: key)
        book = SeedRules.defaultBook
    }

    private static func loadBook(from defaults: UserDefaults, key: String) -> RuleBook {
        guard let data = defaults.data(forKey: key) else {
            return SeedRules.defaultBook
        }
        guard let decoded = try? JSONDecoder().decode(RuleBook.self, from: data) else {
            // Corrupted / incompatible payload — fall back to seed rather than
            // wedge the app. Future: migration branch on decoded.version.
            return SeedRules.defaultBook
        }
        if decoded.version != RuleBook.currentVersion {
            // Version drift — seed for now. When a real migration lands this
            // is where it'd run.
            return SeedRules.defaultBook
        }
        return decoded
    }
}
