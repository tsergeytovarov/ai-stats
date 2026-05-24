import Foundation
import os.log

/// Категоризированные os.Logger'ы. Заменяют разбросанные NSLog'и — выигрыш:
///
/// 1. **Privacy-маркеры.** В `os.Logger` интерполяции по умолчанию `.private`
///    в release-сборках (видны как `<private>` без debugger'а). NSLog писал всё
///    plain-text в unified log → потенциальная утечка response-body / paths
///    в системные логи (Console.app, sysdiagnose, crash reports).
/// 2. **Фильтрация по категории.** `log show --predicate 'category=="aiuse"'`.
/// 3. **Дешевле в проде.** os_log skip'ает форматирование если уровень дизаблен.
///
/// **Правила использования:**
/// - Идентификаторы (period, source, model name) → `.public`.
/// - friend_code / repo nameWithOwner → `.private` (приватные репы, friend ID).
/// - error.localizedDescription / response body → `.private`.
/// - Если в строке нет приватных данных, и нужна видимость в Console.app
///   без debugger'а — взять `.public` явно.
enum AppLogger {
    private static let subsystem = "tech.popovs.aistats"

    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let github = Logger(subsystem: subsystem, category: "github")
    static let aiuse = Logger(subsystem: subsystem, category: "aiuse")
    static let ccusage = Logger(subsystem: subsystem, category: "ccusage")
    static let db = Logger(subsystem: subsystem, category: "db")
    static let pricing = Logger(subsystem: subsystem, category: "pricing")
    static let widget = Logger(subsystem: subsystem, category: "widget")
}
