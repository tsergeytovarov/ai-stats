import Foundation
import GRDB

/// Проверка что файл, который пользователь выбрал для импорта, действительно
/// валидный stats.db этого приложения, а не чужой SQLite, что-то побитое, или
/// специально сконструированный файл с подозрительным содержимым.
///
/// Шаги:
/// 1. Magic header `SQLite format 3\0` (16 байт). Отбивает текстовые/JSON-файлы
///    и random binary до того как откроем что-то непредвиденное.
/// 2. Открытие read-only через GRDB.
/// 3. `PRAGMA integrity_check` — sqlite проверяет b-tree integrity, page sums.
/// 4. Проверка что все требуемые app'ом таблицы присутствуют. Иначе после импорта
///    `Database.migrate` упадёт или даст inconsistent state.
enum DatabaseValidator {
    /// Магическое начало SQLite database file — спецификация:
    /// https://www.sqlite.org/fileformat2.html#magic_header_string
    static let sqliteMagicBytes: [UInt8] = Array("SQLite format 3\u{0}".utf8)

    /// Таблицы, которые точно должны быть в валидном stats.db этого app'а.
    /// Минимальный набор из v1 миграции — миграции v2-v7 добавляли таблицы,
    /// но если v1 есть, всё остальное навёрстывает Database.migrate.
    static let requiredTables: [String] = ["ai_usage", "github_activity", "sync_state"]

    static func validate(at url: URL) throws {
        try validateMagicHeader(at: url)
        try validateIntegrityAndSchema(at: url)
    }

    /// Шаг 1: проверка первых 16 байт.
    static func validateMagicHeader(at url: URL) throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw DatabaseValidatorError.openFailed(error.localizedDescription)
        }
        defer { try? handle.close() }

        let read: Data
        do {
            read = try handle.read(upToCount: sqliteMagicBytes.count) ?? Data()
        } catch {
            throw DatabaseValidatorError.openFailed(error.localizedDescription)
        }

        let expected = Data(sqliteMagicBytes)
        guard read == expected else {
            throw DatabaseValidatorError.notSqliteFile
        }
    }

    /// Шаги 2–4: open read-only → integrity_check → required tables present.
    static func validateIntegrityAndSchema(at url: URL) throws {
        var config = Configuration()
        config.readonly = true
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: url.path, configuration: config)
        } catch {
            throw DatabaseValidatorError.openFailed(error.localizedDescription)
        }

        do {
            // PRAGMA integrity_check возвращает single row "ok" или несколько строк с описанием.
            let result = try queue.read { db -> String in
                let rows = try String.fetchAll(db, sql: "PRAGMA integrity_check")
                return rows.joined(separator: "; ")
            }
            guard result == "ok" else {
                throw DatabaseValidatorError.integrityCheckFailed(result)
            }

            let existingTables: [String] = try queue.read { db in
                try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            }
            let missing = Self.requiredTables.filter { !existingTables.contains($0) }
            guard missing.isEmpty else {
                throw DatabaseValidatorError.missingRequiredTables(missing)
            }
        } catch let err as DatabaseValidatorError {
            throw err
        } catch {
            throw DatabaseValidatorError.openFailed(error.localizedDescription)
        }
    }
}

enum DatabaseValidatorError: Error, LocalizedError, Equatable {
    case notSqliteFile
    case integrityCheckFailed(String)
    case missingRequiredTables([String])
    case openFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSqliteFile:
            return "Файл не похож на SQLite database (нет magic header)."
        case .integrityCheckFailed(let detail):
            return "SQLite integrity_check failed: \(detail.prefix(200))"
        case .missingRequiredTables(let tables):
            return "В импортируемой БД нет требуемых таблиц: \(tables.joined(separator: ", ")). " +
                   "Это либо чужая SQLite, либо файл от слишком старой версии Burn."
        case .openFailed(let msg):
            return "Не удалось открыть файл для проверки: \(msg)"
        }
    }
}
