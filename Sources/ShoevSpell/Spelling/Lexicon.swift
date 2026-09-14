import Foundation
import SQLite3

protocol WordScoring: AnyObject {
    func score(for word: String, language: SpellLanguage) -> Int?
}

final class Lexicon: WordScoring {
    static let shared = Lexicon()

    private var database: OpaquePointer?
    private var query: OpaquePointer?
    private let lock = NSLock()
    private let cache = NSCache<NSString, NSNumber>()

    private init() {
        cache.countLimit = 50_000
        guard let url = Bundle.module.url(forResource: "lexicon", withExtension: "sqlite3") else { return }
        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let opened { sqlite3_close(opened) }
            return
        }
        database = opened
        sqlite3_exec(opened, "PRAGMA query_only=ON", nil, nil, nil)
        sqlite3_exec(opened, "PRAGMA cache_size=-4096", nil, nil, nil)
        sqlite3_exec(opened, "PRAGMA mmap_size=33554432", nil, nil, nil)
        sqlite3_prepare_v2(opened, "SELECT score FROM words WHERE language=?1 AND word=?2", -1, &query, nil)
    }

    deinit {
        if let query { sqlite3_finalize(query) }
        if let database { sqlite3_close(database) }
    }

    func score(for original: String, language: SpellLanguage) -> Int? {
        let word = original.lowercased(with: Locale(identifier: "en_US_POSIX"))
        let key = "\(language.rawValue):\(word)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached.intValue < 0 ? nil : cached.intValue
        }
        lock.lock()
        defer { lock.unlock() }
        guard let query else { return nil }
        sqlite3_reset(query)
        sqlite3_clear_bindings(query)
        sqlite3_bind_int(query, 1, language.rawValue)
        sqlite3_bind_text(query, 2, word, -1, Self.transient)
        let result = sqlite3_step(query) == SQLITE_ROW ? Int(sqlite3_column_int(query, 0)) : nil
        cache.setObject(NSNumber(value: result ?? -1), forKey: key)
        return result
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
