# Мониторинг лимитов — план реализации

> **Для агентов:** ОБЯЗАТЕЛЬНЫЙ САБ-СКИЛЛ: используй superpowers:subagent-driven-development (рекомендуется) или superpowers:executing-plans, чтобы исполнять план задача за задачей. Шаги размечены чекбоксами (`- [ ]`).

**Цель:** показать остаток лимитов Claude, Codex и OpenCode тремя кольцами в капсуле меню-бара и разбором по окнам на вкладке «Расходы».

**Архитектура:** три независимых фетчера за общим протоколом отдают нормализованный `ProviderLimits` с набором самоописывающихся окон. Координатор опрашивает их по разным расписаниям, пишет ступенчатую историю в SQLite и держит статус каждого источника. Интерфейс читает только последнее состояние и никогда не показывает выдуманных чисел.

**Стек:** Swift, SwiftUI, GRDB, XCTest, xcodegen. Цель сборки — macOS 26.0.

**Спека:** [2026-07-31-limits-monitor-design.md](../04-specs/2026-07-31-limits-monitor-design.md)

## Глобальные ограничения

- Приложение **не** в сэндбоксе (`com.apple.security.app-sandbox: false`) — спавн процессов и чтение чужих записей Keychain разрешены. Виджет в сэндбоксе, его не трогаем.
- `WidgetSnapshot` в этой фиче **не меняется**. Схема снапшота остаётся версии 2.
- Комментарии в коде — по-русски, как во всём проекте. Объясняют «почему», а не «что».
- Коммиты — Conventional Commits, описание по-русски, повелительное наклонение, с маленькой буквы, без точки.
- Секреты (cookie OpenCode, токен Claude) никогда не попадают в логи, в том числе в текст ошибки. Логи — через `AppLogger`, приватные значения с `privacy: .private`.
- Ни одно состояние интерфейса не показывает число, которого не было в ответе источника. Нет данных — плашка, а не ноль.
- Сетевые вызовы инжектируются через `URLSession` в инициализаторе, как в `AiuseAPIClient`. В тестах — `URLProtocol`-стаб, живой сети в тестах нет.
- Прогон тестов: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/<Suite>`
- Новые файлы попадают в таргет автоматически (xcodegen собирает по путям), но `xcodegen generate` после создания файлов обязателен.

---

### Задача 1: Модель лимитов и миграция базы

Фундамент: типы, которыми говорят все остальные задачи, правило выбора окна для кольца и две таблицы.

**Файлы:**
- Создать: `Shared/Limits/LimitModels.swift`
- Изменить: `Shared/Storage/Database.swift` (добавить миграцию `v10_limits` после `v9_analytics`, строка 189+)
- Изменить: `Shared/Storage/Models.swift` (добавить строки таблиц в конец файла)
- Изменить: `Tests/StatsAppTests/DatabaseTests.swift:11` (список таблиц)
- Тест: `Tests/StatsAppTests/Limits/LimitModelsTests.swift`

**Интерфейсы:**
- Использует: ничего из предыдущих задач.
- Отдаёт: `LimitProvider`, `LimitWindow`, `LimitStatus`, `ProviderLimits`, `ProviderLimits.ringWindow`, `ProviderLimits.worstPercent`, `LimitSeverity`, `LimitThresholds.severity(worstPercent:)`, `LimitSnapshotRow`, `LimitFetchStateRow`. На это опираются все задачи 2–9.

- [ ] **Шаг 1: Написать падающий тест на выбор окна для кольца**

Создай `Tests/StatsAppTests/Limits/LimitModelsTests.swift`:

```swift
import XCTest
@testable import StatsApp

final class LimitModelsTests: XCTestCase {

    private func limits(_ windows: [LimitWindow]) -> ProviderLimits {
        ProviderLimits(provider: .claude, windows: windows, status: .ok,
                       fetchedAt: Date(timeIntervalSince1970: 1_785_000_000), error: nil)
    }

    // Кольцо заполняется по окну с самым ранним сбросом — это ответ на вопрос
    // «сколько осталось в ближайшее время», а не «где я вообще».
    func test_ring_window_is_the_one_resetting_soonest() {
        let five = LimitWindow(windowMinutes: 300, usedPercent: 12,
                               resetsAt: Date(timeIntervalSince1970: 1_785_010_000))
        let week = LimitWindow(windowMinutes: 10080, usedPercent: 95,
                               resetsAt: Date(timeIntervalSince1970: 1_785_900_000))
        XCTAssertEqual(limits([week, five]).ringWindow, five)
    }

    // Времени сброса нет ни у одного окна — берём самое короткое по длительности.
    func test_ring_window_falls_back_to_shortest_when_no_reset_times() {
        let week = LimitWindow(windowMinutes: 10080, usedPercent: 40, resetsAt: nil)
        let month = LimitWindow(windowMinutes: 43200, usedPercent: 80, resetsAt: nil)
        XCTAssertEqual(limits([month, week]).ringWindow, week)
    }

    func test_ring_window_is_nil_without_windows() {
        XCTAssertNil(limits([]).ringWindow)
    }

    // Цвет берётся из худшего окна, а не из того, по которому рисуется заливка:
    // «5ч на нуле, неделя на 95%» обязано гореть красным.
    func test_worst_percent_ignores_which_window_fills_the_ring() {
        let five = LimitWindow(windowMinutes: 300, usedPercent: 0,
                               resetsAt: Date(timeIntervalSince1970: 1_785_010_000))
        let week = LimitWindow(windowMinutes: 10080, usedPercent: 95,
                               resetsAt: Date(timeIntervalSince1970: 1_785_900_000))
        let l = limits([five, week])
        XCTAssertEqual(l.ringWindow, five)
        XCTAssertEqual(l.worstPercent, 95)
        XCTAssertEqual(LimitThresholds.severity(worstPercent: l.worstPercent!), .critical)
    }

    func test_severity_thresholds() {
        XCTAssertEqual(LimitThresholds.severity(worstPercent: 0), .calm)
        XCTAssertEqual(LimitThresholds.severity(worstPercent: 69.9), .calm)
        XCTAssertEqual(LimitThresholds.severity(worstPercent: 70), .warning)
        XCTAssertEqual(LimitThresholds.severity(worstPercent: 89.9), .warning)
        XCTAssertEqual(LimitThresholds.severity(worstPercent: 90), .critical)
        XCTAssertEqual(LimitThresholds.severity(worstPercent: 100), .critical)
    }
}
```

- [ ] **Шаг 2: Прогнать тест — должен не собраться**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/LimitModelsTests`
Ожидание: провал компиляции, `cannot find 'LimitWindow' in scope`.

- [ ] **Шаг 3: Написать модель**

Создай `Shared/Limits/LimitModels.swift`:

```swift
import Foundation

/// Провайдер подписки, у которого есть свой лимит.
enum LimitProvider: String, Codable, CaseIterable, Sendable {
    case claude, codex, opencode

    /// Короткая подпись под кольцом в капсуле.
    var shortTitle: String {
        switch self {
        case .claude:   return "cl"
        case .codex:    return "cx"
        case .opencode: return "oc"
        }
    }

    var displayTitle: String {
        switch self {
        case .claude:   return "Claude"
        case .codex:    return "Codex"
        case .opencode: return "OpenCode"
        }
    }
}

/// Окно лимита. Длительность приходит от источника — по позиции в ответе окна
/// не раскладываем: у Codex `primary` уже переехал с 5 часов на неделю.
struct LimitWindow: Codable, Equatable, Sendable {
    let windowMinutes: Int
    let usedPercent: Double
    let resetsAt: Date?
}

enum LimitStatus: String, Codable, Sendable {
    case ok            // цифры свежие
    case stale         // последний опрос не удался, показываем прошлые
    case throttled     // 429, ждём Retry-After
    case unauthorized  // токен/cookie протухли — нужно действие пользователя
    case unconfigured  // cookie не введена
    case unavailable   // источника нет (не установлен codex)
}

struct ProviderLimits: Codable, Equatable, Sendable {
    let provider: LimitProvider
    let windows: [LimitWindow]
    let status: LimitStatus
    let fetchedAt: Date?
    let error: String?
    /// Заполняется только при статусе throttled: до этого момента провайдера
    /// трогать нельзя. Живёт в результате, а не в изменяемом поле фетчера —
    /// иначе фетчер перестаёт быть Sendable.
    let retryAfter: Date?

    init(provider: LimitProvider, windows: [LimitWindow], status: LimitStatus,
         fetchedAt: Date?, error: String?, retryAfter: Date? = nil) {
        self.provider = provider
        self.windows = windows
        self.status = status
        self.fetchedAt = fetchedAt
        self.error = error
        self.retryAfter = retryAfter
    }
}

extension ProviderLimits {
    /// Окно, по которому заполняется кольцо: с самым ранним сбросом. Если времени
    /// сброса нет ни у одного окна — самое короткое по длительности.
    var ringWindow: LimitWindow? {
        let dated = windows.compactMap { w -> (Date, LimitWindow)? in
            guard let r = w.resetsAt else { return nil }
            return (r, w)
        }
        if let soonest = dated.min(by: { $0.0 < $1.0 })?.1 { return soonest }
        return windows.min(by: { $0.windowMinutes < $1.windowMinutes })
    }

    /// Худший процент по всем окнам — им определяется цвет кольца. Заливка идёт
    /// по ближайшему окну, цвет по худшему: короткое окно почти всегда у нуля и
    /// само по себе спрятало бы упёршийся недельный лимит.
    var worstPercent: Double? {
        windows.map(\.usedPercent).max()
    }
}

enum LimitSeverity: Sendable {
    case calm, warning, critical
}

enum LimitThresholds {
    static let warning = 70.0
    static let critical = 90.0

    static func severity(worstPercent: Double) -> LimitSeverity {
        if worstPercent >= critical { return .critical }
        if worstPercent >= warning { return .warning }
        return .calm
    }
}
```

- [ ] **Шаг 4: Прогнать тест — должен пройти**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/LimitModelsTests`
Ожидание: PASS, 5 тестов.

- [ ] **Шаг 5: Написать падающий тест на миграцию**

Добавь в `Tests/StatsAppTests/Limits/LimitModelsTests.swift` новый класс. Импорт
`GRDB` поставь наверх файла, к остальным импортам, а не перед классом:

```swift
// наверху файла, рядом с import XCTest:
// import GRDB

final class LimitsMigrationTests: XCTestCase {

    func test_migration_creates_limit_tables() throws {
        let queue = try DatabaseQueue()
        try Database.migrate(queue)

        let tables = try queue.read { db in
            try String.fetchAll(db, sql:
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        }
        XCTAssertTrue(tables.contains("limit_snapshots"))
        XCTAssertTrue(tables.contains("limit_fetch_state"))
    }

    func test_snapshot_row_roundtrip() throws {
        let queue = try DatabaseQueue()
        try Database.migrate(queue)

        try queue.write { db in
            var row = LimitSnapshotRow(id: nil, provider: "codex", windowMinutes: 10080,
                                       usedPercent: 78, resetsAt: 1_785_905_362,
                                       observedAt: 1_785_000_000)
            try row.insert(db)
        }
        let fetched = try queue.read { db in try LimitSnapshotRow.fetchAll(db) }
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].provider, "codex")
        XCTAssertEqual(fetched[0].windowMinutes, 10080)
        XCTAssertEqual(fetched[0].usedPercent, 78)
        XCTAssertEqual(fetched[0].resetsAt, 1_785_905_362)
    }

    func test_fetch_state_row_roundtrip() throws {
        let queue = try DatabaseQueue()
        try Database.migrate(queue)

        try queue.write { db in
            try LimitFetchStateRow(provider: "claude", lastAttemptAt: 100, lastSuccessAt: 90,
                                   status: "throttled", error: nil, retryAfterAt: 3682)
                .insert(db, onConflict: .replace)
        }
        let fetched = try queue.read { db in try LimitFetchStateRow.fetchAll(db) }
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].status, "throttled")
        XCTAssertEqual(fetched[0].retryAfterAt, 3682)
    }
}
```

- [ ] **Шаг 6: Прогнать — должен упасть**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/LimitsMigrationTests`
Ожидание: провал компиляции, `cannot find 'LimitSnapshotRow' in scope`.

- [ ] **Шаг 7: Добавить миграцию**

В `Shared/Storage/Database.swift` после блока `migrator.registerMigration("v9_analytics")` (заканчивается на строке 253 закрывающей скобкой перед `try migrator.migrate(writer)`) добавь:

```swift
        migrator.registerMigration("v10_limits") { db in
            // Ступенчатая история лимитов. Пишем только изменения — ровный опрос
            // раз в 5 минут иначе даст 100k строк в год ни о чём, а второму этапу
            // (прогноз по темпу расхода) нужны именно ступени.
            try db.execute(sql: """
                CREATE TABLE limit_snapshots (
                    id             INTEGER PRIMARY KEY AUTOINCREMENT,
                    provider       TEXT NOT NULL,
                    window_minutes INTEGER NOT NULL,
                    used_percent   REAL NOT NULL,
                    resets_at      INTEGER,
                    observed_at    INTEGER NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX idx_limit_snapshots_lookup
                    ON limit_snapshots(provider, window_minutes, observed_at DESC)
            """)

            // Статус последнего опроса на провайдера. retry_after_at нужен, чтобы
            // после 429 не долбиться в эндпоинт Claude до истечения Retry-After.
            try db.execute(sql: """
                CREATE TABLE limit_fetch_state (
                    provider        TEXT PRIMARY KEY,
                    last_attempt_at INTEGER,
                    last_success_at INTEGER,
                    status          TEXT NOT NULL,
                    error           TEXT,
                    retry_after_at  INTEGER
                )
            """)
        }
```

- [ ] **Шаг 8: Добавить строки таблиц**

В конец `Shared/Storage/Models.swift`:

```swift
/// Наблюдение лимита провайдера. Пишется только при изменении пары
/// (used_percent, resets_at) — см. LimitsRepository.
struct LimitSnapshotRow: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    static let databaseTableName = "limit_snapshots"

    var id: Int64?
    var provider: String
    var windowMinutes: Int
    var usedPercent: Double
    var resetsAt: Int64?
    var observedAt: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column("id")
        static let provider = Column("provider")
        static let windowMinutes = Column("window_minutes")
        static let usedPercent = Column("used_percent")
        static let resetsAt = Column("resets_at")
        static let observedAt = Column("observed_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case windowMinutes = "window_minutes"
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
        case observedAt = "observed_at"
    }
}

/// Статус последнего опроса провайдера. Upsert по provider.
struct LimitFetchStateRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "limit_fetch_state"

    var provider: String
    var lastAttemptAt: Int64?
    var lastSuccessAt: Int64?
    var status: String
    var error: String?
    var retryAfterAt: Int64?

    enum Columns {
        static let provider = Column("provider")
        static let lastAttemptAt = Column("last_attempt_at")
        static let lastSuccessAt = Column("last_success_at")
        static let status = Column("status")
        static let error = Column("error")
        static let retryAfterAt = Column("retry_after_at")
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case lastAttemptAt = "last_attempt_at"
        case lastSuccessAt = "last_success_at"
        case status
        case error
        case retryAfterAt = "retry_after_at"
    }
}
```

- [ ] **Шаг 9: Обновить список таблиц в DatabaseTests**

В `Tests/StatsAppTests/DatabaseTests.swift:11` добавь в отсортированный `Set` две новые таблицы: `"limit_fetch_state"` и `"limit_snapshots"`.

- [ ] **Шаг 10: Прогнать оба набора — должны пройти**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/LimitsMigrationTests -only-testing:StatsAppTests/LimitModelsTests -only-testing:StatsAppTests/DatabaseTests`
Ожидание: PASS.

- [ ] **Шаг 11: Коммит**

```bash
git add Shared/Limits/LimitModels.swift Shared/Storage/Database.swift Shared/Storage/Models.swift Tests/StatsAppTests/Limits/LimitModelsTests.swift Tests/StatsAppTests/DatabaseTests.swift
git commit -m "feat(limits): добавить модель лимитов и таблицы истории"
```

---

### Задача 2: Фетчер Codex

Самый простой и полностью локальный источник. Даёт работающую фичу в одиночку.

**Файлы:**
- Создать: `Shared/Limits/CodexLimitsParser.swift`
- Создать: `StatsApp/Limits/LimitsFetching.swift` (протокол, общий для задач 2–4)
- Создать: `StatsApp/Limits/CodexLimitsFetcher.swift`
- Тест: `Tests/StatsAppTests/Limits/CodexLimitsParserTests.swift`

**Интерфейсы:**
- Использует: `LimitWindow`, `LimitProvider`, `LimitStatus`, `ProviderLimits` (задача 1).
- Отдаёт: протокол `LimitsFetching` с `var provider: LimitProvider { get }` и `func fetch() async -> ProviderLimits`; `CodexLimitsParser.parseRPC(_:) -> [LimitWindow]`; `CodexLimitsParser.parseRolloutLine(_:) -> [LimitWindow]?`; класс `CodexLimitsFetcher`. Протокол используют задачи 3, 4, 6.

- [ ] **Шаг 1: Написать падающий тест парсера**

Создай `Tests/StatsAppTests/Limits/CodexLimitsParserTests.swift`:

```swift
import XCTest
@testable import StatsApp

final class CodexLimitsParserTests: XCTestCase {

    // Живой ответ app-server от 2026-07-31. Обрати внимание: primary — НЕДЕЛЬНОЕ
    // окно (10080), а secondary пустой. Раскладывать окна по позиции нельзя.
    func test_parses_rpc_result_with_weekly_primary() throws {
        let json = Data(#"""
        {"jsonrpc":"2.0","id":2,"result":{"rateLimits":{
          "primary":{"usedPercent":78,"resetsAt":1785905362,"windowDurationMins":10080},
          "secondary":null}}}
        """#.utf8)

        let windows = CodexLimitsParser.parseRPC(json)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].windowMinutes, 10080)
        XCTAssertEqual(windows[0].usedPercent, 78)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 1_785_905_362))
    }

    func test_parses_both_windows_when_present() throws {
        let json = Data(#"""
        {"jsonrpc":"2.0","id":2,"result":{"rateLimits":{
          "primary":{"usedPercent":12.5,"resetsAt":1785000000,"windowDurationMins":300},
          "secondary":{"usedPercent":40,"resetsAt":1785900000,"windowDurationMins":10080}}}}
        """#.utf8)

        let windows = CodexLimitsParser.parseRPC(json)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(Set(windows.map(\.windowMinutes)), [300, 10080])
    }

    // Без длительности окно бессмысленно — не гадаем, а выбрасываем.
    func test_drops_window_without_duration() throws {
        let json = Data(#"""
        {"result":{"rateLimits":{"primary":{"usedPercent":50,"resetsAt":1785000000}}}}
        """#.utf8)
        XCTAssertTrue(CodexLimitsParser.parseRPC(json).isEmpty)
    }

    func test_returns_empty_on_garbage() {
        XCTAssertTrue(CodexLimitsParser.parseRPC(Data("не json".utf8)).isEmpty)
        XCTAssertTrue(CodexLimitsParser.parseRPC(Data("{}".utf8)).isEmpty)
    }

    // Фолбэк: строка token_count из rollout-лога. Формат другой — snake_case и
    // limit_id, который надо проверить.
    func test_parses_rollout_line() throws {
        let line = #"{"type":"event_msg","timestamp":"2026-07-31T00:35:21Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":74.0,"window_minutes":10080,"resets_at":1785905362},"secondary":null}}}"#
        let windows = try XCTUnwrap(CodexLimitsParser.parseRolloutLine(line))
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].windowMinutes, 10080)
        XCTAssertEqual(windows[0].usedPercent, 74)
    }

    func test_ignores_rollout_line_of_other_limit_id() {
        let line = #"{"payload":{"type":"token_count","rate_limits":{"limit_id":"other","primary":{"used_percent":99.0,"window_minutes":300}}}}"#
        XCTAssertNil(CodexLimitsParser.parseRolloutLine(line))
    }

    func test_ignores_line_without_rate_limits() {
        XCTAssertNil(CodexLimitsParser.parseRolloutLine(#"{"payload":{"type":"other"}}"#))
    }
}
```

- [ ] **Шаг 2: Прогнать — должен не собраться**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/CodexLimitsParserTests`
Ожидание: провал компиляции, `cannot find 'CodexLimitsParser' in scope`.

- [ ] **Шаг 3: Написать парсер**

Создай `Shared/Limits/CodexLimitsParser.swift`:

```swift
import Foundation

/// Разбор лимитов Codex из двух форматов: JSON-RPC ответа app-server (живой) и
/// строки rollout-лога (фолбэк). Чистые функции, тестируются без процессов.
enum CodexLimitsParser {

    /// Ответ `account/rateLimits/read`. Окно берём из `windowDurationMins`, а не
    /// из имени ключа: на Pro `primary` сейчас недельный, `secondary` пустой.
    static func parseRPC(_ data: Data) -> [LimitWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let rateLimits = result["rateLimits"] as? [String: Any] else { return [] }
        return ["primary", "secondary"].compactMap { key in
            guard let part = rateLimits[key] as? [String: Any] else { return nil }
            return window(usedPercent: part["usedPercent"],
                          windowMinutes: part["windowDurationMins"],
                          resetsAt: part["resetsAt"])
        }
    }

    /// Строка rollout-лога. nil — в строке нет лимитов Codex (другой тип события,
    /// чужой limit_id или битый JSON).
    static func parseRolloutLine(_ line: String) -> [LimitWindow]? {
        guard line.contains("\"rate_limits\""),
              let data = line.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = root["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any],
              rateLimits["limit_id"] as? String == "codex" else { return nil }
        let windows = ["primary", "secondary"].compactMap { key -> LimitWindow? in
            guard let part = rateLimits[key] as? [String: Any] else { return nil }
            return window(usedPercent: part["used_percent"],
                          windowMinutes: part["window_minutes"],
                          resetsAt: part["resets_at"])
        }
        return windows.isEmpty ? nil : windows
    }

    private static func window(usedPercent: Any?, windowMinutes: Any?, resetsAt: Any?) -> LimitWindow? {
        guard let pct = (usedPercent as? NSNumber)?.doubleValue,
              let minutes = (windowMinutes as? NSNumber)?.intValue else { return nil }
        let reset = (resetsAt as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return LimitWindow(windowMinutes: minutes,
                           usedPercent: min(max(pct, 0), 100),
                           resetsAt: reset)
    }
}
```

- [ ] **Шаг 4: Прогнать — должен пройти**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/CodexLimitsParserTests`
Ожидание: PASS, 7 тестов.

- [ ] **Шаг 5: Коммит парсера**

```bash
git add Shared/Limits/CodexLimitsParser.swift Tests/StatsAppTests/Limits/CodexLimitsParserTests.swift
git commit -m "feat(limits): разобрать лимиты codex из rpc и rollout-логов"
```

- [ ] **Шаг 6: Написать протокол и фетчер**

Создай `StatsApp/Limits/LimitsFetching.swift`:

```swift
import Foundation

/// Источник лимитов одного провайдера. Реализации никогда не бросают — любая
/// беда превращается в ProviderLimits со статусом и пустыми окнами, чтобы
/// координатор не разбирал ошибки, а интерфейс показал честную плашку.
protocol LimitsFetching: Sendable {
    var provider: LimitProvider { get }
    func fetch() async -> ProviderLimits
}

extension ProviderLimits {
    /// Неудачный опрос без данных.
    static func failure(_ provider: LimitProvider, status: LimitStatus, error: String?,
                        retryAfter: Date? = nil) -> ProviderLimits {
        ProviderLimits(provider: provider, windows: [], status: status,
                       fetchedAt: nil, error: error, retryAfter: retryAfter)
    }
}
```

Создай `StatsApp/Limits/CodexLimitsFetcher.swift`:

```swift
import Foundation

/// Живые лимиты Codex через `codex app-server`: JSON-RPC по stdin/stdout,
/// initialize → initialized → account/rateLimits/read. Если бинаря нет или RPC
/// молчит — последний снапшот из свежих rollout-логов.
final class CodexLimitsFetcher: LimitsFetching {
    let provider: LimitProvider = .codex

    private let sessionsDir: URL
    private let rpcTimeout: TimeInterval
    private let now: @Sendable () -> Date

    init(sessionsDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".codex/sessions"),
         rpcTimeout: TimeInterval = 12,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.sessionsDir = sessionsDir
        self.rpcTimeout = rpcTimeout
        self.now = now
    }

    func fetch() async -> ProviderLimits {
        if let windows = rpcWindows(), !windows.isEmpty {
            return ProviderLimits(provider: .codex, windows: windows, status: .ok,
                                  fetchedAt: now(), error: nil)
        }
        if let windows = rolloutWindows(), !windows.isEmpty {
            // Данные из лога могут отставать — честно помечаем как несвежие.
            return ProviderLimits(provider: .codex, windows: windows, status: .stale,
                                  fetchedAt: now(), error: nil)
        }
        return .failure(.codex, status: .unavailable, error: "codex недоступен")
    }

    // MARK: - RPC

    private func rpcWindows() -> [LimitWindow]? {
        guard let executable = Self.locateCodex() else { return nil }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server"]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }
        defer {
            process.terminate()
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }

        func send(_ object: [String: Any]) {
            guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
            data.append(0x0A)
            try? stdin.fileHandleForWriting.write(contentsOf: data)
        }

        send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": ["clientInfo": ["name": "burn", "version": "1.0.0"]]])

        // Ответы построчные. Читаем до дедлайна: сперва ответ на initialize,
        // потом — на запрос лимитов. Пайп тут безопасен: трафик крошечный.
        let deadline = Date().addingTimeInterval(rpcTimeout)
        var buffer = Data()
        var initialized = false
        while Date() < deadline {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty { continue }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<nl]
                buffer = buffer[buffer.index(after: nl)...]
                guard let object = (try? JSONSerialization.jsonObject(with: Data(lineData)))
                        as? [String: Any] else { continue }
                let id = (object["id"] as? NSNumber)?.intValue
                if id == 1, object["result"] != nil, !initialized {
                    initialized = true
                    send(["jsonrpc": "2.0", "method": "initialized", "params": [:]])
                    send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read",
                          "params": [:]])
                } else if id == 2 {
                    return CodexLimitsParser.parseRPC(Data(lineData))
                }
            }
        }
        return nil
    }

    /// Ищем codex в системных дир'ах и в ~/.local/bin.
    ///
    /// Домашний путь тут включён сознательно, в отличие от
    /// CcusageFetcher.extraSearchPaths: ~/.local/bin — штатное место официального
    /// установщика codex, и без него живой RPC оказывается мёртвым кодом почти
    /// у всех. Размен принят явно: тот, кто может писать в домашнюю папку,
    /// уже правит shell-профиль и конфиги агентов, так что подложенный сюда
    /// бинарь не расширяет его возможности.
    static func locateCodex(fileManager: FileManager = .default,
                            home: String = NSHomeDirectory()) -> URL? {
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex",
                          "\(home)/.local/bin/codex"]
        return candidates.map(URL.init(fileURLWithPath:))
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - Фолбэк на rollout-логи

    private func rolloutWindows() -> [LimitWindow]? {
        let fm = FileManager.default
        guard let files = try? recentRolloutFiles(fm: fm) else { return nil }
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            // Снапшот аккаунт-глобальный: берём последний в файле.
            var last: [LimitWindow]?
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if let windows = CodexLimitsParser.parseRolloutLine(String(line)) { last = windows }
            }
            if let last { return last }
        }
        return nil
    }

    private func recentRolloutFiles(fm: FileManager) throws -> [URL] {
        guard let walker = fm.enumerator(at: sessionsDir,
                                         includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }
        var found: [(Date, URL)] = []
        for case let url as URL in walker where url.lastPathComponent.hasPrefix("rollout-")
            && url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            found.append((date, url))
        }
        return found.sorted { $0.0 > $1.0 }.prefix(30).map(\.1)
    }
}
```

- [ ] **Шаг 7: Написать тест на фолбэк по реальным файлам**

Добавь в `Tests/StatsAppTests/Limits/CodexLimitsParserTests.swift`:

```swift
final class CodexLimitsFetcherTests: XCTestCase {

    // Фолбэк на rollout-логи: кладём во временную дир'ю два файла, свежий должен
    // выиграть, а внутри файла — последний снапшот.
    func test_falls_back_to_newest_rollout_snapshot() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "codex-limits-\(UUID().uuidString)/2026/07/31")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let old = dir.appending(path: "rollout-old.jsonl")
        try #"{"payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":10.0,"window_minutes":10080}}}}"#
            .write(to: old, atomically: true, encoding: .utf8)

        let fresh = dir.appending(path: "rollout-fresh.jsonl")
        try [
            #"{"payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":50.0,"window_minutes":10080}}}}"#,
            #"{"payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":74.0,"window_minutes":10080,"resets_at":1785905362}}}}"#,
        ].joined(separator: "\n").write(to: fresh, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)],
                                              ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)],
                                              ofItemAtPath: fresh.path)

        // Пустая PATH-подстановка недоступна, поэтому проверяем ровно фолбэк:
        // если codex в системе есть, тест всё равно осмысленный — окна не пустые.
        let fetcher = CodexLimitsFetcher(sessionsDir: dir.deletingLastPathComponent()
                                            .deletingLastPathComponent().deletingLastPathComponent(),
                                         rpcTimeout: 0.1,
                                         now: { Date(timeIntervalSince1970: 5_000) })
        let limits = await fetcher.fetch()
        XCTAssertEqual(limits.provider, .codex)
        XCTAssertFalse(limits.windows.isEmpty)
        XCTAssertEqual(limits.windows[0].windowMinutes, 10080)
    }

    func test_reports_unavailable_when_nothing_found() async {
        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "codex-empty-\(UUID().uuidString)")
        let fetcher = CodexLimitsFetcher(sessionsDir: empty, rpcTimeout: 0.1)
        let limits = await fetcher.fetch()
        if limits.status == .unavailable {
            XCTAssertTrue(limits.windows.isEmpty)
        } else {
            // На машине с рабочим codex RPC отвечает — тогда данные обязаны быть.
            XCTAssertEqual(limits.status, .ok)
            XCTAssertFalse(limits.windows.isEmpty)
        }
    }
}
```

- [ ] **Шаг 8: Прогнать — должен пройти**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/CodexLimitsFetcherTests -only-testing:StatsAppTests/CodexLimitsParserTests`
Ожидание: PASS.

- [ ] **Шаг 4: Коммит**

```bash
git add StatsApp/Limits/LimitsFetching.swift StatsApp/Limits/CodexLimitsFetcher.swift Tests/StatsAppTests/Limits/CodexLimitsParserTests.swift
git commit -m "feat(limits): получать лимиты codex через app-server"
```

---

### Задача 3: Фетчер Claude

**Файлы:**
- Создать: `Shared/Limits/ClaudeUsageParser.swift`
- Создать: `StatsApp/Limits/ClaudeLimitsFetcher.swift`
- Тест: `Tests/StatsAppTests/Limits/ClaudeLimitsTests.swift`

**Интерфейсы:**
- Использует: `LimitsFetching`, `ProviderLimits.failure(_:status:error:)` (задача 2), модель (задача 1), `KeychainStore` из `StatsApp/Network/KeychainStore.swift`.
- Отдаёт: `ClaudeUsageParser.parse(_:) -> [LimitWindow]`, `ClaudeUsageParser.tokenFromKeychainBlob(_:) -> String?`, класс `ClaudeLimitsFetcher(keychain:session:now:)`, `ClaudeLimitsFetcher.retryAfterDate(from:now:)`.

- [ ] **Шаг 1: Написать падающий тест парсера и разбора Retry-After**

Создай `Tests/StatsAppTests/Limits/ClaudeLimitsTests.swift`:

```swift
import XCTest
@testable import StatsApp

final class ClaudeUsageParserTests: XCTestCase {

    // Форма ответа /api/oauth/usage, проверена живьём 2026-07-31.
    func test_parses_five_hour_and_seven_day() {
        let data = Data(#"""
        {"five_hour":{"utilization":75,"resets_at":"2026-07-31T15:30:00Z"},
         "seven_day":{"utilization":51.4,"resets_at":"2026-08-04T02:00:00Z"}}
        """#.utf8)

        let windows = ClaudeUsageParser.parse(data).sorted { $0.windowMinutes < $1.windowMinutes }
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].windowMinutes, 300)
        XCTAssertEqual(windows[0].usedPercent, 75)
        XCTAssertEqual(windows[1].windowMinutes, 10080)
        XCTAssertEqual(windows[1].usedPercent, 51.4)
        XCTAssertNotNil(windows[0].resetsAt)
    }

    func test_skips_window_without_utilization() {
        let data = Data(#"{"five_hour":{"resets_at":"2026-07-31T15:30:00Z"},"seven_day":null}"#.utf8)
        XCTAssertTrue(ClaudeUsageParser.parse(data).isEmpty)
    }

    func test_keeps_window_without_reset_time() {
        let data = Data(#"{"seven_day":{"utilization":10}}"#.utf8)
        let windows = ClaudeUsageParser.parse(data)
        XCTAssertEqual(windows.count, 1)
        XCTAssertNil(windows[0].resetsAt)
    }

    func test_returns_empty_on_garbage() {
        XCTAssertTrue(ClaudeUsageParser.parse(Data("не json".utf8)).isEmpty)
    }

    func test_extracts_token_from_keychain_blob() {
        let blob = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat-XXX","expiresAt":123}}"#
        XCTAssertEqual(ClaudeUsageParser.tokenFromKeychainBlob(blob), "sk-ant-oat-XXX")
    }

    func test_token_nil_when_blob_has_no_oauth() {
        XCTAssertNil(ClaudeUsageParser.tokenFromKeychainBlob(#"{"mcpOAuth":{}}"#))
        XCTAssertNil(ClaudeUsageParser.tokenFromKeychainBlob("мусор"))
        XCTAssertNil(ClaudeUsageParser.tokenFromKeychainBlob(#"{"claudeAiOauth":{"accessToken":""}}"#))
    }

    // Живой 429 отдал Retry-After: 3582 — почти час. Секунды, не дата.
    func test_retry_after_seconds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let at = ClaudeLimitsFetcher.retryAfterDate(from: "3582", now: now)
        XCTAssertEqual(at, Date(timeIntervalSince1970: 1_003_582))
    }

    func test_retry_after_missing_defaults_to_an_hour() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ClaudeLimitsFetcher.retryAfterDate(from: nil, now: now),
                       Date(timeIntervalSince1970: 1_003_600))
    }
}
```

- [ ] **Шаг 2: Прогнать — должен не собраться**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/ClaudeUsageParserTests`
Ожидание: провал компиляции, `cannot find 'ClaudeUsageParser' in scope`.

- [ ] **Шаг 3: Написать парсер**

Создай `Shared/Limits/ClaudeUsageParser.swift`:

```swift
import Foundation

/// Разбор ответа недокументированного эндпоинта `/api/oauth/usage` и вытаскивание
/// OAuth-токена из блоба Keychain, который пишет Claude Code.
enum ClaudeUsageParser {

    /// Имена окон в ответе фиксированы, поэтому раскладка по ключу здесь законна
    /// (в отличие от Codex, где длительность приезжает полем).
    private static let windowMinutes: [(key: String, minutes: Int)] = [
        ("five_hour", 300),
        ("seven_day", 10080),
    ]

    static func parse(_ data: Data) -> [LimitWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }
        return windowMinutes.compactMap { entry in
            guard let raw = root[entry.key] as? [String: Any],
                  let pct = (raw["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let reset = (raw["resets_at"] as? String).flatMap {
                ISO8601DateFormatter().date(from: $0)
            }
            return LimitWindow(windowMinutes: entry.minutes,
                               usedPercent: min(max(pct, 0), 100),
                               resetsAt: reset)
        }
    }

    /// Значение записи Keychain `Claude Code-credentials` — JSON, токен лежит в
    /// claudeAiOauth.accessToken.
    static func tokenFromKeychainBlob(_ blob: String) -> String? {
        guard let data = blob.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else { return nil }
        return token
    }
}
```

- [ ] **Шаг 4: Написать фетчер**

Создай `StatsApp/Limits/ClaudeLimitsFetcher.swift`:

```swift
import Foundation

/// Лимиты Claude через недокументированный OAuth-эндпоинт. Токен читаем из чужой
/// записи Keychain (её пишет Claude Code) и нигде не сохраняем: взяли, сходили,
/// забыли. Эндпоинт жёстко троттлится — живой ответ отдал Retry-After 3582,
/// поэтому расписание опроса часовое, а 429 обязан уважаться.
final class ClaudeLimitsFetcher: LimitsFetching {
    let provider: LimitProvider = .claude

    static let keychainService = "Claude Code-credentials"
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let betaHeader = "oauth-2025-04-20"
    private static let userAgent = "claude-code/2.1.0"

    private let keychain: KeychainStore
    private let account: String
    private let session: URLSession
    private let now: @Sendable () -> Date

    init(keychain: KeychainStore = MacOSKeychainStore(),
         account: String = NSUserName(),
         session: URLSession = .shared,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.keychain = keychain
        self.account = account
        self.session = session
        self.now = now
    }

    func fetch() async -> ProviderLimits {
        guard let blob = keychain.get(account: account, service: Self.keychainService),
              let token = ClaudeUsageParser.tokenFromKeychainBlob(blob) else {
            return .failure(.claude, status: .unauthorized, error: "нет токена Claude Code")
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.claude, status: .stale, error: "неожиданный ответ")
            }
            switch http.statusCode {
            case 200:
                let windows = ClaudeUsageParser.parse(data)
                guard !windows.isEmpty else {
                    // 200 без окон — эндпоинт сменил форму, а не лимиты кончились.
                    return .failure(.claude, status: .unavailable, error: "не разобрал ответ")
                }
                return ProviderLimits(provider: .claude, windows: windows, status: .ok,
                                      fetchedAt: now(), error: nil)
            case 401, 403:
                return .failure(.claude, status: .unauthorized, error: "нужен вход заново")
            case 429:
                return .failure(.claude, status: .throttled, error: "лимит запросов, ждём",
                                retryAfter: Self.retryAfterDate(
                                    from: http.value(forHTTPHeaderField: "Retry-After"),
                                    now: now()))
            default:
                return .failure(.claude, status: .stale, error: "HTTP \(http.statusCode)")
            }
        } catch {
            return .failure(.claude, status: .stale, error: error.localizedDescription)
        }
    }

    /// Retry-After приходит в секундах. Нет заголовка — считаем час: наблюдаемое
    /// окно троттлинга примерно такое.
    static func retryAfterDate(from header: String?, now: Date) -> Date {
        let seconds = header.flatMap(TimeInterval.init) ?? 3600
        return now.addingTimeInterval(seconds)
    }
}
```

- [ ] **Шаг 5: Прогнать тесты парсера — должны пройти**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/ClaudeUsageParserTests`
Ожидание: PASS, 8 тестов.

- [ ] **Шаг 6: Написать тест фетчера на стабе сети**

Добавь в `Tests/StatsAppTests/Limits/ClaudeLimitsTests.swift`:

```swift
/// URLProtocol-стаб: живой сети в тестах нет.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class ClaudeLimitsFetcherTests: XCTestCase {

    private let blob = #"{"claudeAiOauth":{"accessToken":"tok"}}"#

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func fetcher(keychainValue: String?) -> ClaudeLimitsFetcher {
        let store = MemoryKeychainStore()
        if let keychainValue {
            try? store.set(keychainValue, account: "tester",
                           service: ClaudeLimitsFetcher.keychainService)
        }
        return ClaudeLimitsFetcher(keychain: store, account: "tester",
                                   session: StubURLProtocol.session(),
                                   now: { Date(timeIntervalSince1970: 1_000_000) })
    }

    private func response(_ code: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                        statusCode: code, httpVersion: nil, headerFields: headers)!
    }

    func test_ok_returns_windows() async {
        StubURLProtocol.handler = { _ in
            (self.response(200), Data(#"{"five_hour":{"utilization":75},"seven_day":{"utilization":51}}"#.utf8))
        }
        let limits = await fetcher(keychainValue: blob).fetch()
        XCTAssertEqual(limits.status, .ok)
        XCTAssertEqual(limits.windows.count, 2)
        XCTAssertEqual(limits.fetchedAt, Date(timeIntervalSince1970: 1_000_000))
    }

    func test_missing_token_is_unauthorized_and_never_hits_network() async {
        StubURLProtocol.handler = { _ in XCTFail("сети быть не должно"); return (self.response(200), Data()) }
        let limits = await fetcher(keychainValue: nil).fetch()
        XCTAssertEqual(limits.status, .unauthorized)
        XCTAssertTrue(limits.windows.isEmpty)
    }

    func test_401_is_unauthorized() async {
        StubURLProtocol.handler = { _ in (self.response(401), Data()) }
        let limits = await fetcher(keychainValue: blob).fetch()
        XCTAssertEqual(limits.status, .unauthorized)
    }

    func test_429_sets_retry_after_and_reports_throttled() async {
        StubURLProtocol.handler = { _ in
            (self.response(429, headers: ["Retry-After": "3582"]),
             Data(#"{"error":{"type":"rate_limit_error"}}"#.utf8))
        }
        let limits = await fetcher(keychainValue: blob).fetch()
        XCTAssertEqual(limits.status, .throttled)
        XCTAssertEqual(limits.retryAfter, Date(timeIntervalSince1970: 1_003_582))
    }

    // 200 с неизвестной формой — это «эндпоинт поменялся», а не «лимитов ноль».
    func test_200_with_unknown_shape_is_unavailable_not_zero() async {
        StubURLProtocol.handler = { _ in (self.response(200), Data(#"{"foo":1}"#.utf8)) }
        let limits = await fetcher(keychainValue: blob).fetch()
        XCTAssertEqual(limits.status, .unavailable)
        XCTAssertTrue(limits.windows.isEmpty)
    }
}
```

- [ ] **Шаг 7: Прогнать — должен пройти**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/ClaudeLimitsFetcherTests -only-testing:StatsAppTests/ClaudeUsageParserTests`
Ожидание: PASS.

Если `MemoryKeychainStore` окажется недоступен из тестов — он объявлен в `StatsApp/Network/KeychainStore.swift` и используется в существующих тестах Settings; смотри там пример подключения.

- [ ] **Шаг 8: Коммит**

```bash
git add Shared/Limits/ClaudeUsageParser.swift StatsApp/Limits/ClaudeLimitsFetcher.swift Tests/StatsAppTests/Limits/ClaudeLimitsTests.swift
git commit -m "feat(limits): получать лимиты claude через oauth-эндпоинт"
```

---

### Задача 4: Фетчер OpenCode

Самый хрупкий источник: сессионная cookie руками плюс скрейп страницы.

**Файлы:**
- Создать: `Shared/Limits/OpenCodeUsageParser.swift`
- Создать: `StatsApp/Limits/OpenCodeLimitsFetcher.swift`
- Тест: `Tests/StatsAppTests/Limits/OpenCodeLimitsTests.swift`

**Интерфейсы:**
- Использует: `LimitsFetching`, модель (задачи 1–2), `KeychainStore`.
- Отдаёт: `OpenCodeUsageParser.normalizeCookie(_:)`, `OpenCodeUsageParser.filterAuthCookie(_:)`, `OpenCodeUsageParser.parseWorkspaceIDs(_:)`, `OpenCodeUsageParser.parseLimits(_:now:) -> [LimitWindow]?`, класс `OpenCodeLimitsFetcher(keychain:account:session:now:)`, константа `OpenCodeLimitsFetcher.keychainService = "ai-stats.opencode"`.

- [ ] **Шаг 1: Написать падающий тест парсера**

Создай `Tests/StatsAppTests/Limits/OpenCodeLimitsTests.swift`:

```swift
import XCTest
@testable import StatsApp

final class OpenCodeUsageParserTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_785_000_000)

    // Страница приходит в формате React Flight — не HTML и не JSON, поэтому
    // достаём брейс-сбалансированные блоки, а не парсим целиком.
    private let page = """
    $R[3]={rollingUsage:{usagePercent:0,resetInSec:1200,limit:{usagePercent:99}},\
    weeklyUsage:{usagePercent:2.5,resetInSec:200000},\
    monthlyUsage:{usagePercent:31,resetInSec:2000000}}
    """

    func test_parses_three_windows() throws {
        let windows = try XCTUnwrap(OpenCodeUsageParser.parseLimits(page, now: now))
            .sorted { $0.windowMinutes < $1.windowMinutes }
        XCTAssertEqual(windows.map(\.windowMinutes), [300, 10080, 43200])
        XCTAssertEqual(windows[0].usedPercent, 0)
        XCTAssertEqual(windows[1].usedPercent, 2.5)
        XCTAssertEqual(windows[2].usedPercent, 31)
        XCTAssertEqual(windows[0].resetsAt, now.addingTimeInterval(1200))
    }

    // Вложенный usagePercent внутри limit:{...} не должен победить внешний.
    func test_ignores_nested_usage_percent() throws {
        let windows = try XCTUnwrap(OpenCodeUsageParser.parseLimits(page, now: now))
        let rolling = try XCTUnwrap(windows.first { $0.windowMinutes == 300 })
        XCTAssertEqual(rolling.usedPercent, 0)
    }

    // Месячного окна может не быть — это не повод терять два остальных.
    func test_monthly_null_still_returns_two_windows() throws {
        let text = "rollingUsage:{usagePercent:1,resetInSec:10},weeklyUsage:{usagePercent:2,resetInSec:20},monthlyUsage:null"
        let windows = try XCTUnwrap(OpenCodeUsageParser.parseLimits(text, now: now))
        XCTAssertEqual(windows.count, 2)
    }

    // Без rolling и weekly считаем, что вёрстка поменялась — отдаём nil, а не пусто.
    func test_nil_when_required_windows_missing() {
        XCTAssertNil(OpenCodeUsageParser.parseLimits("совсем не та страница", now: now))
        XCTAssertNil(OpenCodeUsageParser.parseLimits("rollingUsage:{usagePercent:1,resetInSec:10}", now: now))
    }

    func test_parses_workspace_ids_in_order_without_duplicates() {
        let text = #"{id:"wrk_AAA",name:"x"},{id:"wrk_BBB"},{id:"wrk_AAA"}"#
        XCTAssertEqual(OpenCodeUsageParser.parseWorkspaceIDs(text), ["wrk_AAA", "wrk_BBB"])
    }

    func test_normalizes_bare_cookie_token() {
        XCTAssertEqual(OpenCodeUsageParser.normalizeCookie("Fe26.2**abc"), "auth=Fe26.2**abc")
        XCTAssertEqual(OpenCodeUsageParser.normalizeCookie("auth=Fe26.2**abc"), "auth=Fe26.2**abc")
        XCTAssertEqual(OpenCodeUsageParser.normalizeCookie("  "), "")
    }

    // На opencode.ai уходит только auth-кука: чужие сессии из вставленной строки
    // отправлять нельзя.
    func test_filters_out_foreign_cookies() {
        let raw = "ga=123; auth=Fe26.2**abc; __Host-auth=zzz; tracker=nope"
        XCTAssertEqual(OpenCodeUsageParser.filterAuthCookie(raw),
                       "auth=Fe26.2**abc; __Host-auth=zzz")
    }
}
```

- [ ] **Шаг 2: Прогнать — должен не собраться**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/OpenCodeUsageParserTests`
Ожидание: провал компиляции, `cannot find 'OpenCodeUsageParser' in scope`.

- [ ] **Шаг 3: Написать парсер**

Создай `Shared/Limits/OpenCodeUsageParser.swift`:

```swift
import Foundation

/// Разбор страницы `/workspace/<id>/go` opencode.ai. Страница отдаётся в формате
/// React Flight — не HTML-дерево и не валидный JSON, поэтому вырезаем
/// брейс-сбалансированные блоки и читаем числа только на первом уровне: внутри
/// блока встречаются вложенные объекты с теми же именами полей.
enum OpenCodeUsageParser {

    private static let authCookieNames: Set<String> = ["auth", "__Host-auth"]

    private static let windows: [(key: String, minutes: Int, required: Bool)] = [
        ("rollingUsage", 300, true),
        ("weeklyUsage", 10080, true),
        ("monthlyUsage", 43200, false),
    ]

    /// Голый токен оборачиваем в `auth=`; готовый заголовок не трогаем.
    static func normalizeCookie(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains(";") { return trimmed }
        if trimmed.lowercased().hasPrefix("auth=") || trimmed.hasPrefix("__Host-auth=") {
            return trimmed
        }
        return "auth=\(trimmed)"
    }

    /// Оставляем только auth-куки — чужие сессии на opencode.ai не отправляем.
    static func filterAuthCookie(_ raw: String) -> String {
        raw.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { pair in
                guard let eq = pair.firstIndex(of: "=") else { return false }
                return authCookieNames.contains(String(pair[..<eq]))
            }
            .joined(separator: "; ")
    }

    static func parseWorkspaceIDs(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\bid\s*:\s*["']((?:wrk|wk)_[a-zA-Z0-9]+)["']"#) else { return [] }
        let ns = text as NSString
        var ids: [String] = []
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, let range = Range(m.range(at: 1), in: text) else { return }
            let id = String(text[range])
            if !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    /// nil — обязательных окон нет, то есть вёрстка поменялась. Пустой массив
    /// не отдаём: он читался бы как «лимитов нет», а это враньё.
    static func parseLimits(_ text: String, now: Date) -> [LimitWindow]? {
        var result: [LimitWindow] = []
        for spec in windows {
            guard let block = usageBlock(in: text, key: spec.key),
                  let pct = topLevelNumber(block, field: "usagePercent"),
                  let resetIn = topLevelNumber(block, field: "resetInSec") else {
                if spec.required { return nil }
                continue
            }
            result.append(LimitWindow(windowMinutes: spec.minutes,
                                      usedPercent: min(max(pct, 0), 100),
                                      resetsAt: now.addingTimeInterval(resetIn)))
        }
        return result.isEmpty ? nil : result
    }

    /// Первый брейс-сбалансированный блок у `key:`, в котором usagePercent и
    /// resetInSec лежат прямыми полями. Вхождения вида `monthlyUsage:null`
    /// пропускаем.
    private static func usageBlock(in text: String, key: String) -> String? {
        let chars = Array(text)
        let pattern = Array("\(key):")
        var index = 0
        while index + pattern.count <= chars.count {
            guard Array(chars[index..<(index + pattern.count)]) == pattern else {
                index += 1
                continue
            }
            var cursor = index + pattern.count
            while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
            guard cursor < chars.count, chars[cursor] == "{" else {
                index += 1
                continue
            }
            var depth = 0
            var end: Int?
            for i in cursor..<chars.count {
                if chars[i] == "{" { depth += 1 }
                else if chars[i] == "}" {
                    depth -= 1
                    if depth == 0 { end = i; break }
                }
            }
            if let end {
                let block = String(chars[cursor...end])
                if topLevelNumber(block, field: "usagePercent") != nil,
                   topLevelNumber(block, field: "resetInSec") != nil {
                    return block
                }
            }
            index += 1
        }
        return nil
    }

    /// Число у поля на глубине 1 объекта. Вложенные одноимённые игнорируем —
    /// внутри блока лежит `limit:{usagePercent:…}`, который к делу не относится.
    private static func topLevelNumber(_ block: String, field: String) -> Double? {
        let chars = Array(block)
        let needle = Array(field)
        var depth = 0
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "{" { depth += 1; i += 1; continue }
            if ch == "}" { depth -= 1; i += 1; continue }
            guard depth == 1, i + needle.count < chars.count,
                  Array(chars[i..<(i + needle.count)]) == needle else {
                i += 1
                continue
            }
            var cursor = i + needle.count
            while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
            guard cursor < chars.count, chars[cursor] == ":" else { i += 1; continue }
            cursor += 1
            while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
            var number = ""
            if cursor < chars.count, chars[cursor] == "-" { number.append("-"); cursor += 1 }
            while cursor < chars.count, chars[cursor].isNumber || chars[cursor] == "." {
                number.append(chars[cursor])
                cursor += 1
            }
            if let value = Double(number) { return value }
            i += 1
        }
        return nil
    }
}
```

- [ ] **Шаг 4: Прогнать — должен пройти**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/OpenCodeUsageParserTests`
Ожидание: PASS, 7 тестов.

- [ ] **Шаг 5: Коммит парсера**

```bash
git add Shared/Limits/OpenCodeUsageParser.swift Tests/StatsAppTests/Limits/OpenCodeLimitsTests.swift
git commit -m "feat(limits): разобрать страницу лимитов opencode"
```

- [ ] **Шаг 6: Написать фетчер**

Создай `StatsApp/Limits/OpenCodeLimitsFetcher.swift`:

```swift
import Foundation

/// Лимиты подписки OpenCode Go. API-ключи из ~/.local/share/opencode/auth.json не
/// подходят — они дают модели, а не квоту. Нужна сессионная cookie сайта, её
/// пользователь вставляет в настройках, лежит в Keychain.
final class OpenCodeLimitsFetcher: LimitsFetching {
    let provider: LimitProvider = .opencode

    static let keychainService = "ai-stats.opencode"

    private static let base = "https://opencode.ai"
    private static let workspacesServerID =
        "def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f"
    // Cloudflare рубит дефолтный UA URLSession — ходим браузерным.
    private static let userAgent = """
    Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 \
    (KHTML, like Gecko) Chrome/124.0 Safari/537.36
    """

    private let keychain: KeychainStore
    private let account: String
    private let session: URLSession
    private let now: @Sendable () -> Date

    init(keychain: KeychainStore = MacOSKeychainStore(),
         account: String = NSUserName(),
         session: URLSession = .shared,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.keychain = keychain
        self.account = account
        self.session = session
        self.now = now
    }

    func fetch() async -> ProviderLimits {
        let stored = keychain.get(account: account, service: Self.keychainService) ?? ""
        let cookie = OpenCodeUsageParser.filterAuthCookie(
            OpenCodeUsageParser.normalizeCookie(stored))
        guard !cookie.isEmpty else {
            return .failure(.opencode, status: .unconfigured, error: "нет cookie opencode.ai")
        }

        do {
            let discovery = try await get(
                url: URL(string: "\(Self.base)/_server?id=\(Self.workspacesServerID)")!,
                cookie: cookie,
                accept: "text/javascript, application/json;q=0.9, */*;q=0.8",
                extra: ["X-Server-Id": Self.workspacesServerID,
                        "X-Server-Instance": "server-fn:\(UUID().uuidString)"])
            let ids = OpenCodeUsageParser.parseWorkspaceIDs(discovery)
            guard !ids.isEmpty else {
                // Пустой список воркспейсов — почти всегда протухшая cookie.
                return .failure(.opencode, status: .unauthorized, error: "не нашёл воркспейс")
            }

            for id in ids {
                let page = try await get(url: URL(string: "\(Self.base)/workspace/\(id)/go")!,
                                         cookie: cookie,
                                         accept: "text/html,application/xhtml+xml,*/*;q=0.8",
                                         extra: [:])
                if let windows = OpenCodeUsageParser.parseLimits(page, now: now()) {
                    return ProviderLimits(provider: .opencode, windows: windows, status: .ok,
                                          fetchedAt: now(), error: nil)
                }
            }
            return .failure(.opencode, status: .unavailable, error: "не разобрал страницу")
        } catch let error as HTTPStatusError where error.code == 401 || error.code == 403 {
            return .failure(.opencode, status: .unauthorized, error: "cookie протухла")
        } catch {
            return .failure(.opencode, status: .stale, error: error.localizedDescription)
        }
    }

    private struct HTTPStatusError: Error { let code: Int }

    private func get(url: URL, cookie: String, accept: String,
                     extra: [String: String]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.base, forHTTPHeaderField: "Origin")
        request.setValue(Self.base, forHTTPHeaderField: "Referer")
        for (key, value) in extra { request.setValue(value, forHTTPHeaderField: key) }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPStatusError(code: http.statusCode)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Шаг 7: Написать тест фетчера**

Добавь в `Tests/StatsAppTests/Limits/OpenCodeLimitsTests.swift` (стаб `StubURLProtocol` уже объявлен в `ClaudeLimitsTests.swift`, переиспользуй его):

```swift
final class OpenCodeLimitsFetcherTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func fetcher(cookie: String?) -> OpenCodeLimitsFetcher {
        let store = MemoryKeychainStore()
        if let cookie {
            try? store.set(cookie, account: "tester",
                           service: OpenCodeLimitsFetcher.keychainService)
        }
        return OpenCodeLimitsFetcher(keychain: store, account: "tester",
                                     session: StubURLProtocol.session(),
                                     now: { Date(timeIntervalSince1970: 1_785_000_000) })
    }

    private func ok(_ url: URL, _ body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
         Data(body.utf8))
    }

    func test_discovers_workspace_then_parses_limits() async {
        StubURLProtocol.handler = { request in
            let url = request.url!
            if url.path == "/_server" {
                return self.ok(url, #"{id:"wrk_ABC"}"#)
            }
            return self.ok(url, "rollingUsage:{usagePercent:0,resetInSec:1200},weeklyUsage:{usagePercent:2,resetInSec:200000}")
        }
        let limits = await fetcher(cookie: "Fe26.2**abc").fetch()
        XCTAssertEqual(limits.status, .ok)
        XCTAssertEqual(limits.windows.count, 2)
    }

    func test_no_cookie_is_unconfigured_and_never_hits_network() async {
        StubURLProtocol.handler = { _ in XCTFail("сети быть не должно"); return (HTTPURLResponse(), Data()) }
        let limits = await fetcher(cookie: nil).fetch()
        XCTAssertEqual(limits.status, .unconfigured)
    }

    func test_no_workspace_is_unauthorized() async {
        StubURLProtocol.handler = { request in self.ok(request.url!, "пусто") }
        let limits = await fetcher(cookie: "Fe26.2**abc").fetch()
        XCTAssertEqual(limits.status, .unauthorized)
    }

    // Вёрстка поменялась: воркспейс нашёлся, а usage не разобрался.
    func test_unparsable_page_is_unavailable() async {
        StubURLProtocol.handler = { request in
            request.url!.path == "/_server"
                ? self.ok(request.url!, #"{id:"wrk_ABC"}"#)
                : self.ok(request.url!, "<html>редизайн</html>")
        }
        let limits = await fetcher(cookie: "Fe26.2**abc").fetch()
        XCTAssertEqual(limits.status, .unavailable)
    }
}
```

- [ ] **Шаг 8: Прогнать — должен пройти**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/OpenCodeLimitsFetcherTests -only-testing:StatsAppTests/OpenCodeUsageParserTests`
Ожидание: PASS.

- [ ] **Шаг 4: Коммит**

```bash
git add StatsApp/Limits/OpenCodeLimitsFetcher.swift Tests/StatsAppTests/Limits/OpenCodeLimitsTests.swift
git commit -m "feat(limits): получать лимиты opencode по сессионной cookie"
```

---

### Задача 5: Хранилище истории

**Файлы:**
- Создать: `StatsApp/Limits/LimitsRepository.swift`
- Тест: `Tests/StatsAppTests/Limits/LimitsRepositoryTests.swift`

**Интерфейсы:**
- Использует: `LimitSnapshotRow`, `LimitFetchStateRow`, `ProviderLimits`, `LimitWindow`, `LimitStatus` (задача 1).
- Отдаёт: `LimitsRepository(db:retentionDays:)`, `record(_:now:) async throws`, `latest() async throws -> [LimitProvider: ProviderLimits]`, `saveState(provider:status:error:retryAfter:now:) async throws`, `pruneOldSnapshots(now:) async throws`.

- [ ] **Шаг 1: Написать падающий тест**

Создай `Tests/StatsAppTests/Limits/LimitsRepositoryTests.swift`:

```swift
import XCTest
import GRDB
@testable import StatsApp

final class LimitsRepositoryTests: XCTestCase {

    private func makeDB() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Database.migrate(queue)
        return queue
    }

    private func limits(_ pct: Double, reset: TimeInterval?, status: LimitStatus = .ok) -> ProviderLimits {
        ProviderLimits(provider: .codex,
                       windows: [LimitWindow(windowMinutes: 10080, usedPercent: pct,
                                             resetsAt: reset.map { Date(timeIntervalSince1970: $0) })],
                       status: status, fetchedAt: Date(timeIntervalSince1970: 1_000), error: nil)
    }

    // Ровный опрос раз в 5 минут не должен плодить одинаковые строки — второму
    // этапу нужны ступени, а не пила из идентичных значений.
    func test_identical_snapshot_is_not_written_twice() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_300))

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 1)
    }

    func test_changed_percent_is_written() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.record(limits(79, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_300))

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 2)
    }

    // Сброс окна: процент упал, время сброса уехало — это новая ступень.
    func test_changed_reset_time_is_written() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.record(limits(78, reset: 1_786_510_162), now: Date(timeIntervalSince1970: 1_300))

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 2)
    }

    // Неудачный опрос не имеет права затирать последние известные цифры.
    func test_failed_fetch_does_not_write_snapshot_but_updates_state() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.record(ProviderLimits.failure(.codex, status: .stale, error: "сеть"),
                              now: Date(timeIntervalSince1970: 1_300))

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 1)

        let state = try await db.read { try LimitFetchStateRow.fetchAll($0) }
        XCTAssertEqual(state.count, 1)
        XCTAssertEqual(state[0].status, "stale")
        XCTAssertEqual(state[0].lastSuccessAt, 1_000)
        XCTAssertEqual(state[0].lastAttemptAt, 1_300)
    }

    // Последнее состояние: цифры из snapshots, статус из state.
    func test_latest_merges_snapshots_with_state() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.record(ProviderLimits.failure(.codex, status: .stale, error: "сеть"),
                              now: Date(timeIntervalSince1970: 1_300))

        let latest = try await repo.latest()
        let codex = try XCTUnwrap(latest[.codex])
        XCTAssertEqual(codex.status, .stale)
        XCTAssertEqual(codex.windows.count, 1)
        XCTAssertEqual(codex.windows[0].usedPercent, 78)
        XCTAssertEqual(codex.fetchedAt, Date(timeIntervalSince1970: 1_000))
    }

    func test_latest_returns_only_newest_row_per_window() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(10, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.record(limits(20, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 2_000))

        let codex = try XCTUnwrap(try await repo.latest()[.codex])
        XCTAssertEqual(codex.windows.count, 1)
        XCTAssertEqual(codex.windows[0].usedPercent, 20)
    }

    func test_prune_drops_snapshots_older_than_retention() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db, retentionDays: 60)

        try await db.write { db in
            var old = LimitSnapshotRow(id: nil, provider: "codex", windowMinutes: 10080,
                                       usedPercent: 5, resetsAt: nil, observedAt: 0)
            try old.insert(db)
        }
        try await repo.record(limits(78, reset: nil), now: Date(timeIntervalSince1970: 61 * 86_400))
        try await repo.pruneOldSnapshots(now: Date(timeIntervalSince1970: 61 * 86_400))

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].usedPercent, 78)
    }
}
```

- [ ] **Шаг 2: Прогнать — должен не собраться**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/LimitsRepositoryTests`
Ожидание: провал компиляции, `cannot find 'LimitsRepository' in scope`.

- [ ] **Шаг 3: Написать хранилище**

Создай `StatsApp/Limits/LimitsRepository.swift`:

```swift
import Foundation
import GRDB

/// История лимитов и статусы опроса. Снапшот пишется только при изменении —
/// история должна быть ступенчатой, иначе второй этап (прогноз по темпу) будет
/// считать темп по шуму опроса, а не по расходу.
final class LimitsRepository {
    private let db: any DatabaseWriter
    private let retentionDays: Int

    init(db: any DatabaseWriter, retentionDays: Int = 60) {
        self.db = db
        self.retentionDays = retentionDays
    }

    /// Записать результат опроса: окна — в историю, статус — в состояние.
    func record(_ limits: ProviderLimits, now: Date) async throws {
        let observedAt = Int64(now.timeIntervalSince1970)
        let provider = limits.provider.rawValue

        try await db.write { db in
            var lastSuccessAt = try LimitFetchStateRow
                .filter(LimitFetchStateRow.Columns.provider == provider)
                .fetchOne(db)?.lastSuccessAt

            for window in limits.windows {
                let resetsAt = window.resetsAt.map { Int64($0.timeIntervalSince1970) }
                let previous = try LimitSnapshotRow
                    .filter(LimitSnapshotRow.Columns.provider == provider)
                    .filter(LimitSnapshotRow.Columns.windowMinutes == window.windowMinutes)
                    .order(LimitSnapshotRow.Columns.observedAt.desc)
                    .fetchOne(db)
                if previous?.usedPercent == window.usedPercent, previous?.resetsAt == resetsAt {
                    continue
                }
                var row = LimitSnapshotRow(id: nil, provider: provider,
                                           windowMinutes: window.windowMinutes,
                                           usedPercent: window.usedPercent,
                                           resetsAt: resetsAt, observedAt: observedAt)
                try row.insert(db)
            }

            if !limits.windows.isEmpty {
                lastSuccessAt = observedAt
            }
            try LimitFetchStateRow(provider: provider,
                                   lastAttemptAt: observedAt,
                                   lastSuccessAt: lastSuccessAt,
                                   status: limits.status.rawValue,
                                   error: limits.error,
                                   retryAfterAt: nil)
                .insert(db, onConflict: .replace)
        }
    }

    /// Отдельно сохранить статус, не трогая историю (например, retry_after после 429).
    func saveState(provider: LimitProvider, status: LimitStatus, error: String?,
                   retryAfter: Date?, now: Date) async throws {
        let key = provider.rawValue
        let attemptAt = Int64(now.timeIntervalSince1970)
        try await db.write { db in
            let previous = try LimitFetchStateRow
                .filter(LimitFetchStateRow.Columns.provider == key)
                .fetchOne(db)
            try LimitFetchStateRow(provider: key,
                                   lastAttemptAt: attemptAt,
                                   lastSuccessAt: previous?.lastSuccessAt,
                                   status: status.rawValue,
                                   error: error,
                                   retryAfterAt: retryAfter.map { Int64($0.timeIntervalSince1970) })
                .insert(db, onConflict: .replace)
        }
    }

    /// Последнее известное состояние по каждому провайдеру: цифры из истории,
    /// статус — из состояния опроса.
    func latest() async throws -> [LimitProvider: ProviderLimits] {
        try await db.read { db in
            var result: [LimitProvider: ProviderLimits] = [:]
            for provider in LimitProvider.allCases {
                let key = provider.rawValue
                let state = try LimitFetchStateRow
                    .filter(LimitFetchStateRow.Columns.provider == key)
                    .fetchOne(db)
                let rows = try LimitSnapshotRow
                    .filter(LimitSnapshotRow.Columns.provider == key)
                    .order(LimitSnapshotRow.Columns.observedAt.desc)
                    .fetchAll(db)

                var seen = Set<Int>()
                var windows: [LimitWindow] = []
                for row in rows where !seen.contains(row.windowMinutes) {
                    seen.insert(row.windowMinutes)
                    windows.append(LimitWindow(
                        windowMinutes: row.windowMinutes,
                        usedPercent: row.usedPercent,
                        resetsAt: row.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }))
                }

                guard state != nil || !windows.isEmpty else { continue }
                result[provider] = ProviderLimits(
                    provider: provider,
                    windows: windows,
                    status: state.flatMap { LimitStatus(rawValue: $0.status) } ?? .stale,
                    fetchedAt: state?.lastSuccessAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    error: state?.error)
            }
            return result
        }
    }

    func pruneOldSnapshots(now: Date) async throws {
        let cutoff = Int64(now.addingTimeInterval(-Double(retentionDays) * 86_400).timeIntervalSince1970)
        try await db.write { db in
            try db.execute(sql: "DELETE FROM limit_snapshots WHERE observed_at < ?",
                           arguments: [cutoff])
        }
    }
}
```

- [ ] **Шаг 4: Прогнать — должен пройти**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/LimitsRepositoryTests`
Ожидание: PASS, 7 тестов.

- [ ] **Шаг 5: Коммит**

```bash
git add StatsApp/Limits/LimitsRepository.swift Tests/StatsAppTests/Limits/LimitsRepositoryTests.swift
git commit -m "feat(limits): хранить ступенчатую историю лимитов и статусы опроса"
```

---

### Задача 6: Координатор опроса

**Файлы:**
- Создать: `StatsApp/Limits/LimitsCoordinator.swift`
- Изменить: `StatsApp/Sync/SyncCoordinator.swift` (вызов тика рядом с `maybeRunAnalyticsIngest`)
- Изменить: `StatsApp/AppContainer.swift` (сборка зависимостей)
- Тест: `Tests/StatsAppTests/Limits/LimitsCoordinatorTests.swift`

**Интерфейсы:**
- Использует: `LimitsFetching` (задача 2), `LimitsRepository` (задача 5), модель (задача 1).
- Отдаёт: `LimitsCoordinator(fetchers:repository:intervals:now:)`, `func tick() async`, `LimitsCoordinator.Intervals` со значениями по умолчанию `codex: 300`, `opencode: 900`, `claude: 3600`.

- [ ] **Шаг 1: Написать падающий тест**

Создай `Tests/StatsAppTests/Limits/LimitsCoordinatorTests.swift`:

```swift
import XCTest
import GRDB
@testable import StatsApp

/// Фейковый источник: считает вызовы и отдаёт заранее заданный результат.
final class FakeLimitsFetcher: LimitsFetching, @unchecked Sendable {
    let provider: LimitProvider
    private(set) var calls = 0
    var result: ProviderLimits

    init(provider: LimitProvider, result: ProviderLimits) {
        self.provider = provider
        self.result = result
    }

    func fetch() async -> ProviderLimits {
        calls += 1
        return result
    }
}

final class LimitsCoordinatorTests: XCTestCase {

    private func makeDB() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Database.migrate(queue)
        return queue
    }

    private func ok(_ provider: LimitProvider, pct: Double) -> ProviderLimits {
        ProviderLimits(provider: provider,
                       windows: [LimitWindow(windowMinutes: 10080, usedPercent: pct, resetsAt: nil)],
                       status: .ok, fetchedAt: Date(timeIntervalSince1970: 0), error: nil)
    }

    func test_first_tick_polls_every_provider() async throws {
        let db = try makeDB()
        let fetchers = LimitProvider.allCases.map { FakeLimitsFetcher(provider: $0, result: ok($0, pct: 10)) }
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let coordinator = LimitsCoordinator(fetchers: fetchers,
                                            repository: LimitsRepository(db: db),
                                            now: { clock })

        await coordinator.tick()
        XCTAssertEqual(fetchers.map(\.calls), [1, 1, 1])
        _ = clock
    }

    // Каждый источник со своим расписанием: через 6 минут Codex опрашивается
    // снова, а Claude с его часовым троттлингом — нет.
    func test_respects_per_provider_intervals() async throws {
        let db = try makeDB()
        let codex = FakeLimitsFetcher(provider: .codex, result: ok(.codex, pct: 10))
        let claude = FakeLimitsFetcher(provider: .claude, result: ok(.claude, pct: 20))
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let coordinator = LimitsCoordinator(fetchers: [codex, claude],
                                            repository: LimitsRepository(db: db),
                                            now: { clock })

        await coordinator.tick()
        clock = clock.addingTimeInterval(360)   // +6 минут
        await coordinator.tick()

        XCTAssertEqual(codex.calls, 2)
        XCTAssertEqual(claude.calls, 1)
    }

    // 429 у Claude: Retry-After перебивает расписание. Ставим его на два часа —
    // по часовому интервалу мы бы уже сходили, а по Retry-After ещё нельзя.
    func test_throttled_provider_is_not_polled_until_retry_after() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let claude = FakeLimitsFetcher(
            provider: .claude,
            result: .failure(.claude, status: .throttled, error: "429",
                             retryAfter: start.addingTimeInterval(7_200)))
        var clock = start
        let coordinator = LimitsCoordinator(fetchers: [claude], repository: repo, now: { clock })

        await coordinator.tick()
        XCTAssertEqual(claude.calls, 1)

        // +70 минут: часовой интервал истёк, но Retry-After — нет.
        clock = start.addingTimeInterval(4_200)
        await coordinator.tick()
        XCTAssertEqual(claude.calls, 1)

        // +2 часа с минутой: Retry-After истёк, можно снова.
        clock = start.addingTimeInterval(7_260)
        await coordinator.tick()
        XCTAssertEqual(claude.calls, 2)
    }

    func test_tick_writes_snapshots() async throws {
        let db = try makeDB()
        let codex = FakeLimitsFetcher(provider: .codex, result: ok(.codex, pct: 78))
        let coordinator = LimitsCoordinator(fetchers: [codex],
                                            repository: LimitsRepository(db: db),
                                            now: { Date(timeIntervalSince1970: 1_000_000) })

        await coordinator.tick()

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].usedPercent, 78)
    }
}
```

- [ ] **Шаг 2: Прогнать — должен не собраться**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/LimitsCoordinatorTests`
Ожидание: провал компиляции, `cannot find 'LimitsCoordinator' in scope`.

- [ ] **Шаг 3: Написать координатор**

Создай `StatsApp/Limits/LimitsCoordinator.swift`:

```swift
import Foundation
import os.log

/// Опрашивает источники лимитов по разным расписаниям и складывает результат в
/// историю. Расписания разные не для красоты: Codex локальный и дешёвый,
/// OpenCode ходит в сеть через Cloudflare, а эндпоинт Claude отдаёт 429 с
/// Retry-After около часа.
actor LimitsCoordinator {

    struct Intervals: Sendable {
        var codex: TimeInterval = 300
        var opencode: TimeInterval = 900
        var claude: TimeInterval = 3600

        func value(for provider: LimitProvider) -> TimeInterval {
            switch provider {
            case .codex:    return codex
            case .opencode: return opencode
            case .claude:   return claude
            }
        }
    }

    private let fetchers: [any LimitsFetching]
    private let repository: LimitsRepository
    private let intervals: Intervals
    private let now: @Sendable () -> Date

    private var lastAttempt: [LimitProvider: Date] = [:]
    private var retryAfter: [LimitProvider: Date] = [:]

    init(fetchers: [any LimitsFetching],
         repository: LimitsRepository,
         intervals: Intervals = Intervals(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetchers = fetchers
        self.repository = repository
        self.intervals = intervals
        self.now = now
    }

    /// Один проход: опрашиваем тех, кому пора. Ошибки не пробрасываем — тик
    /// вызывается из общего цикла синхронизации и не должен его ронять.
    func tick() async {
        let moment = now()
        for fetcher in fetchers where shouldPoll(fetcher.provider, at: moment) {
            lastAttempt[fetcher.provider] = moment
            let limits = await fetcher.fetch()

            if limits.status == .throttled {
                // Пока Retry-After не истёк, провайдера не трогаем вообще.
                let until = limits.retryAfter ?? moment.addingTimeInterval(3600)
                retryAfter[fetcher.provider] = until
                try? await repository.saveState(provider: fetcher.provider, status: .throttled,
                                                error: limits.error, retryAfter: until, now: moment)
                continue
            }
            retryAfter[fetcher.provider] = nil

            do {
                try await repository.record(limits, now: moment)
            } catch {
                AppLogger.sync.error(
                    "limits record failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        try? await repository.pruneOldSnapshots(now: moment)
    }

    private func shouldPoll(_ provider: LimitProvider, at moment: Date) -> Bool {
        if let until = retryAfter[provider], moment < until { return false }
        guard let last = lastAttempt[provider] else { return true }
        return moment.timeIntervalSince(last) >= intervals.value(for: provider)
    }
}
```

- [ ] **Шаг 4: Прогнать — должен пройти**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/LimitsCoordinatorTests`
Ожидание: PASS, 4 теста.

- [ ] **Шаг 5: Подключить к циклу синхронизации**

В `StatsApp/Sync/SyncCoordinator.swift` добавь опциональную зависимость и вызов. Рядом с существующим полем `analyticsIngest` объяви:

```swift
    /// Тик опроса лимитов. Опционален: в тестах синка лимиты не нужны.
    var limitsTick: (@Sendable () async -> Void)?
```

В методе `runAllSources()` сразу после строки `await maybeRunAnalyticsIngest()` (`StatsApp/Sync/SyncCoordinator.swift:91`) добавь:

```swift
        // Лимиты со своим расписанием внутри координатора — тут просто дёргаем
        // тик, а он сам решает, кому пора.
        await limitsTick?()
```

В `StatsApp/AppContainer.swift` собери зависимости при создании `SyncCoordinator`:

```swift
        let limitsCoordinator = LimitsCoordinator(
            fetchers: [CodexLimitsFetcher(), ClaudeLimitsFetcher(), OpenCodeLimitsFetcher()],
            repository: LimitsRepository(db: pool))
        syncCoordinator.limitsTick = { await limitsCoordinator.tick() }
```

Точное имя переменной пула базы и координатора возьми из текущего кода `AppContainer.swift` — там уже собираются `AnalyticsIngestor` и `SyncCoordinator`, повтори тот же стиль.

- [ ] **Шаг 6: Прогнать всю сюиту**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS'`
Ожидание: PASS, включая существующие `SyncCoordinatorTests`.

- [ ] **Шаг 7: Коммит**

```bash
git add StatsApp/Limits/LimitsCoordinator.swift StatsApp/Sync/SyncCoordinator.swift StatsApp/AppContainer.swift Tests/StatsAppTests/Limits/LimitsCoordinatorTests.swift
git commit -m "feat(limits): опрашивать источники по расписанию с уважением к 429"
```

---

### Задача 7: Секция «Лимиты» на вкладке «Расходы»

**Файлы:**
- Создать: `Shared/Limits/LimitFormat.swift`
- Создать: `Shared/Limits/LimitRingPalette.swift`
- Создать: `StatsApp/Status/DropdownLimitsSection.swift`
- Изменить: `StatsApp/Status/DropdownViewModel.swift` (загрузка состояния)
- Изменить: `StatsApp/Status/DropdownSections.swift` (вставить секцию в `DropdownAISection`)
- Тест: `Tests/StatsAppTests/Limits/LimitFormatTests.swift`
- Тест: `Tests/StatsAppTests/Limits/LimitRingPaletteTests.swift`

**Интерфейсы:**
- Использует: `ProviderLimits`, `LimitStatus`, `LimitProvider`, `LimitThresholds.severity(worstPercent:)` (задача 1), `LimitsRepository.latest()` (задача 5).
- Отдаёт: `LimitFormat.percent(_:)`, `LimitFormat.window(minutes:)`, `LimitFormat.resetsIn(_:now:)`, `LimitFormat.fetchedAt(_:)`, `LimitFormat.actionText(for:status:)`, `LimitRingPalette.color(for:severity:)`, `LimitRingPalette.trackColor`, `LimitRingPalette.contourColor`, вью `DropdownLimitsSection(limits:)`, свойство `DropdownViewModel.limits: [LimitProvider: ProviderLimits]`. Палитру использует задача 8.

Палитра живёт здесь, а не в задаче 8, потому что цвет нужен обеим поверхностям — и полоскам в попапе, и кольцам в капсуле.

- [ ] **Шаг 1: Написать падающий тест форматтера**

Создай `Tests/StatsAppTests/Limits/LimitFormatTests.swift`:

```swift
import XCTest
@testable import StatsApp

final class LimitFormatTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_785_000_000)

    func test_percent_without_pointless_decimals() {
        XCTAssertEqual(LimitFormat.percent(78), "78%")
        XCTAssertEqual(LimitFormat.percent(2.5), "2.5%")
        XCTAssertEqual(LimitFormat.percent(0), "0%")
        XCTAssertEqual(LimitFormat.percent(51.04), "51%")
    }

    func test_window_titles() {
        XCTAssertEqual(LimitFormat.window(minutes: 300), "5 часов")
        XCTAssertEqual(LimitFormat.window(minutes: 10080), "неделя")
        XCTAssertEqual(LimitFormat.window(minutes: 43200), "месяц")
        XCTAssertEqual(LimitFormat.window(minutes: 1440), "24 часа")
    }

    func test_resets_in_human_text() {
        XCTAssertEqual(LimitFormat.resetsIn(now.addingTimeInterval(90 * 60), now: now),
                       "сброс через 1ч 30м")
        XCTAssertEqual(LimitFormat.resetsIn(now.addingTimeInterval(40 * 60), now: now),
                       "сброс через 40м")
        XCTAssertEqual(LimitFormat.resetsIn(now.addingTimeInterval(50 * 3600), now: now),
                       "сброс через 2д 2ч")
        XCTAssertNil(LimitFormat.resetsIn(nil, now: now))
        // Время сброса в прошлом — окно уже должно было сброситься, врать не будем.
        XCTAssertNil(LimitFormat.resetsIn(now.addingTimeInterval(-60), now: now))
    }

    func test_action_text_only_for_states_needing_the_user() {
        XCTAssertEqual(LimitFormat.actionText(for: .claude, status: .unauthorized),
                       "Claude: нужен вход заново")
        XCTAssertEqual(LimitFormat.actionText(for: .opencode, status: .unconfigured),
                       "OpenCode: вставь cookie в настройках")
        XCTAssertNil(LimitFormat.actionText(for: .codex, status: .ok))
        XCTAssertNil(LimitFormat.actionText(for: .codex, status: .stale))
    }

    func test_fetched_at_label() {
        XCTAssertEqual(LimitFormat.fetchedAt(nil), "нет данных")
        XCTAssertTrue(LimitFormat.fetchedAt(now).hasPrefix("данные на "))
    }
}
```

Создай `Tests/StatsAppTests/Limits/LimitRingPaletteTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import StatsApp

final class LimitRingPaletteTests: XCTestCase {

    // Фирменный цвет живёт только в спокойном состоянии. Выше порогов все три
    // провайдера одинаковые: это сигнал «тормози», а не «кто это».
    func test_brand_colors_only_below_warning() {
        XCTAssertEqual(LimitRingPalette.color(for: .codex, severity: .calm), LimitRingPalette.codexBlue)
        XCTAssertEqual(LimitRingPalette.color(for: .claude, severity: .calm), LimitRingPalette.claudeOrange)
        XCTAssertEqual(LimitRingPalette.color(for: .opencode, severity: .calm), LimitRingPalette.openCodeWhite)

        for provider in LimitProvider.allCases {
            XCTAssertEqual(LimitRingPalette.color(for: provider, severity: .warning),
                           LimitRingPalette.warningYellow)
            XCTAssertEqual(LimitRingPalette.color(for: provider, severity: .critical),
                           BrandColor.danger)
        }
    }

    // Заливка идёт по ближайшему окну, цвет — по худшему. Проверяем связку
    // целиком, а не по кусочкам.
    func test_fill_and_color_come_from_different_windows() {
        let limits = ProviderLimits(
            provider: .claude,
            windows: [
                LimitWindow(windowMinutes: 300, usedPercent: 0,
                            resetsAt: Date(timeIntervalSince1970: 1_000)),
                LimitWindow(windowMinutes: 10080, usedPercent: 95,
                            resetsAt: Date(timeIntervalSince1970: 9_000)),
            ],
            status: .ok, fetchedAt: Date(timeIntervalSince1970: 0), error: nil)

        XCTAssertEqual(limits.ringWindow?.usedPercent, 0)
        XCTAssertEqual(LimitRingPalette.color(
            for: .claude,
            severity: LimitThresholds.severity(worstPercent: limits.worstPercent!)),
                       BrandColor.danger)
    }

    // Трек нейтральный у всех колец: белое кольцо с белым треком исчезает
    // в светлой теме меню-бара.
    func test_track_is_neutral_not_provider_tinted() {
        XCTAssertEqual(LimitRingPalette.trackColor, Color.primary.opacity(0.15))
    }
}
```

- [ ] **Шаг 2: Прогнать — должен не собраться**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/LimitFormatTests -only-testing:StatsAppTests/LimitRingPaletteTests`
Ожидание: провал компиляции, `cannot find 'LimitFormat' in scope`.

- [ ] **Шаг 3: Написать форматтер и палитру**

Создай `Shared/Limits/LimitFormat.swift`:

```swift
import Foundation

/// Тексты секции лимитов. Отдельно от вью — чтобы тестировались без SwiftUI.
enum LimitFormat {

    static func percent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return "\(Int(rounded.rounded()))%"
        }
        return String(format: "%.1f%%", rounded)
    }

    static func window(minutes: Int) -> String {
        switch minutes {
        case 300:   return "5 часов"
        case 1440:  return "24 часа"
        case 10080: return "неделя"
        case 43200: return "месяц"
        default:
            let hours = minutes / 60
            return hours > 0 ? "\(hours) ч" : "\(minutes) мин"
        }
    }

    /// nil — времени сброса нет или оно уже в прошлом. Показывать «сброс через
    /// -3м» нельзя: это не информация, а баг на экране.
    static func resetsIn(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return nil }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "сброс через \(days)д \(hours)ч" }
        if hours > 0 { return "сброс через \(hours)ч \(minutes)м" }
        return "сброс через \(minutes)м"
    }

    static func fetchedAt(_ date: Date?) -> String {
        guard let date else { return "нет данных" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "данные на \(formatter.string(from: date))"
    }

    /// Строка действия для состояний, где без человека не обойтись. Для
    /// остальных nil — рисуем обычные полоски.
    static func actionText(for provider: LimitProvider, status: LimitStatus) -> String? {
        switch status {
        case .unauthorized:
            return provider == .opencode
                ? "\(provider.displayTitle): cookie протухла, обнови в настройках"
                : "\(provider.displayTitle): нужен вход заново"
        case .unconfigured:
            return "\(provider.displayTitle): вставь cookie в настройках"
        case .unavailable:
            return "\(provider.displayTitle): источник недоступен"
        case .ok, .stale, .throttled:
            return nil
        }
    }
}
```

Создай `Shared/Limits/LimitRingPalette.swift`:

```swift
import SwiftUI

/// Цвета лимитов. Фирменный цвет провайдера виден только пока всё спокойно; на
/// порогах он уступает жёлтому и красному — в этот момент важно не «кто», а
/// «сколько осталось».
enum LimitRingPalette {
    static let codexBlue = Color(red: 59/255, green: 130/255, blue: 246/255)
    /// Фирменный оранжевый Anthropic, осветлённый под тёмную капсулу.
    static let claudeOrange = Color(red: 232/255, green: 135/255, blue: 95/255)
    static let openCodeWhite = Color.white
    static let warningYellow = Color(red: 255/255, green: 196/255, blue: 61/255)

    /// Нейтральный трек вместо «свой цвет с прозрачностью»: белое кольцо с белым
    /// треком в светлой теме меню-бара сливается с фоном.
    static let trackColor = Color.primary.opacity(0.15)
    /// Тонкий контур держит форму белого кольца на светлом фоне. На тёмном не виден.
    static let contourColor = Color.black.opacity(0.25)

    static func color(for provider: LimitProvider, severity: LimitSeverity) -> Color {
        switch severity {
        case .critical: return BrandColor.danger
        case .warning:  return warningYellow
        case .calm:
            switch provider {
            case .codex:    return codexBlue
            case .claude:   return claudeOrange
            case .opencode: return openCodeWhite
            }
        }
    }
}
```

- [ ] **Шаг 4: Прогнать — должен пройти**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/LimitFormatTests -only-testing:StatsAppTests/LimitRingPaletteTests`
Ожидание: PASS, 8 тестов.

- [ ] **Шаг 5: Написать вью секции**

Создай `StatsApp/Status/DropdownLimitsSection.swift`:

```swift
import SwiftUI

/// Секция «Лимиты» на вкладке «Расходы»: по строке на провайдера, внутри —
/// полоска на каждое окно.
struct DropdownLimitsSection: View {
    let limits: [LimitProvider: ProviderLimits]
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ЛИМИТЫ")
                .font(BrandFont.lbl)
                .tracking(1.2)
                .foregroundStyle(BrandColor.cyanLight.opacity(0.7))

            ForEach(LimitProvider.allCases, id: \.self) { provider in
                providerRow(provider, limits: limits[provider])
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: LimitProvider, limits: ProviderLimits?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(provider.displayTitle)
                    .font(BrandFont.body)
                Spacer()
                Text(LimitFormat.fetchedAt(limits?.fetchedAt))
                    .font(BrandFont.caption)
                    .foregroundStyle(TextColor.muted)
            }

            if let action = limits.flatMap({ LimitFormat.actionText(for: provider, status: $0.status) }) {
                Text(action)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.danger.opacity(0.9))
            } else if let windows = limits?.windows, !windows.isEmpty {
                ForEach(windows.sorted { $0.windowMinutes < $1.windowMinutes }, id: \.windowMinutes) { window in
                    windowRow(window, provider: provider)
                }
            } else {
                Text("нет данных")
                    .font(BrandFont.caption)
                    .foregroundStyle(TextColor.muted)
            }
        }
        .padding(.vertical, 2)
    }

    private func windowRow(_ window: LimitWindow, provider: LimitProvider) -> some View {
        HStack(spacing: 8) {
            Text(LimitFormat.window(minutes: window.windowMinutes))
                .font(BrandFont.caption)
                .foregroundStyle(TextColor.secondary)
                .frame(width: 62, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(LimitRingPalette.trackColor)
                    // Полоска окна красится по СВОЕМУ проценту, в отличие от кольца:
                    // здесь видно все окна сразу, подменять цвет худшим незачем.
                    Capsule()
                        .fill(LimitRingPalette.color(
                            for: provider,
                            severity: LimitThresholds.severity(worstPercent: window.usedPercent)))
                        .frame(width: geo.size.width * window.usedPercent / 100)
                }
            }
            .frame(height: 5)

            Text(LimitFormat.percent(window.usedPercent))
                .font(BrandFont.caption)
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)

            if let reset = LimitFormat.resetsIn(window.resetsAt, now: now) {
                Text(reset)
                    .font(BrandFont.caption)
                    .foregroundStyle(TextColor.muted)
            }
        }
    }
}
```

- [ ] **Шаг 6: Подключить состояние во вью-модель**

В `StatsApp/Status/DropdownViewModel.swift` рядом с полем карточки аналитики добавь:

```swift
    /// Последнее известное состояние лимитов. Пусто — опроса ещё не было.
    @Published private(set) var limits: [LimitProvider: ProviderLimits] = [:]
```

И метод загрузки по образцу существующего `loadAnalyticsCard`:

```swift
    /// Читает последнее состояние лимитов из базы. Опрос делает LimitsCoordinator —
    /// вью-модель только показывает то, что уже записано.
    func loadLimits() async {
        guard let limitsRepository else { return }
        limits = (try? await limitsRepository.latest()) ?? [:]
    }
```

Зависимость `limitsRepository: LimitsRepository?` прокинь через инициализатор так же,
как прокинуты остальные (смотри текущую сигнатуру `init` в этом файле).

В `StatsApp/Status/DropdownSections.swift` в `DropdownAISection` после блока со
спарклайном (после строки 91, перед закрывающей скобкой `VStack`) вставь:

```swift
            DropdownLimitsSection(limits: viewModel.limits)
                .padding(.top, 14)
```

И вызови `await viewModel.loadLimits()` там же, где вызывается загрузка данных вкладки.

- [ ] **Шаг 2: Прогнать всю сюиту**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS'`
Ожидание: PASS.

- [ ] **Шаг 8: Коммит**

```bash
git add Shared/Limits/LimitFormat.swift Shared/Limits/LimitRingPalette.swift StatsApp/Status/DropdownLimitsSection.swift StatsApp/Status/DropdownViewModel.swift StatsApp/Status/DropdownSections.swift Tests/StatsAppTests/Limits/LimitFormatTests.swift Tests/StatsAppTests/Limits/LimitRingPaletteTests.swift
git commit -m "feat(limits): показать лимиты на вкладке расходов"
```

---

### Задача 8: Три кольца в капсуле

**Файлы:**
- Создать: `StatsApp/Status/LimitRingView.swift`
- Изменить: `StatsApp/Status/MenuBarCapsuleView.swift`
- Изменить: `StatsApp/Status/StatusItemController.swift` (передать состояние в капсулу)

**Интерфейсы:**
- Использует: `ProviderLimits.ringWindow`, `worstPercent`, `LimitThresholds.severity(worstPercent:)` (задача 1), `LimitRingPalette` (задача 7).
- Отдаёт: вью `LimitRingView(provider:limits:)`, изменённый `MenuBarCapsuleView(priceText:limits:)`.

Новых чистых функций тут нет — вся тестируемая логика (выбор окна, пороги,
палитра) закрыта задачами 1 и 7. Поэтому задача заканчивается проверкой глазами
в обеих темах, и это осознанно, а не пропущенный тест.

- [ ] **Шаг 1: Написать кольцо и вставить в капсулу**

Создай `StatsApp/Status/LimitRingView.swift`:

```swift
import SwiftUI

/// Кольцо лимита одного провайдера. Заливка — по ближайшему к сбросу окну,
/// цвет — по худшему окну. Нет данных — серый пунктир.
struct LimitRingView: View {
    let provider: LimitProvider
    let limits: ProviderLimits?
    var diameter: CGFloat = 10
    var lineWidth: CGFloat = 2

    private var fillFraction: Double {
        guard let percent = limits?.ringWindow?.usedPercent else { return 0 }
        return min(max(percent / 100, 0), 1)
    }

    private var hasData: Bool {
        guard let limits, limits.status != .unconfigured, limits.status != .unavailable
        else { return false }
        return limits.ringWindow != nil
    }

    private var strokeColor: Color {
        guard let worst = limits?.worstPercent else { return .secondary }
        return LimitRingPalette.color(for: provider,
                                      severity: LimitThresholds.severity(worstPercent: worst))
    }

    var body: some View {
        ZStack {
            if hasData {
                Circle()
                    .stroke(LimitRingPalette.trackColor, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fillFraction)
                    .stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .stroke(LimitRingPalette.contourColor, lineWidth: 0.5)
            } else {
                Circle()
                    .stroke(Color.secondary.opacity(0.5),
                            style: StrokeStyle(lineWidth: lineWidth, dash: [2, 2]))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(Text(provider.displayTitle))
    }
}
```

Замени `StatsApp/Status/MenuBarCapsuleView.swift` целиком:

```swift
import SwiftUI

struct MenuBarCapsuleView: View {
    let priceText: String   // "$1,602.78"
    var limits: [LimitProvider: ProviderLimits] = [:]

    /// Кольца прячем, если ни по одному провайдеру нет данных: три серых
    /// пунктира в меню-баре — мусор, а не информация.
    private var showsRings: Bool {
        LimitProvider.allCases.contains { limits[$0]?.ringWindow != nil }
    }

    var body: some View {
        HStack(spacing: 4) {
            MiniEmberView(size: 12)
            Text(priceText)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
            if showsRings {
                HStack(spacing: 3) {
                    ForEach(LimitProvider.allCases, id: \.self) { provider in
                        LimitRingView(provider: provider, limits: limits[provider])
                    }
                }
                .padding(.leading, 2)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(
            LinearGradient(
                colors: [BrandColor.pink.opacity(0.25), BrandColor.cyan.opacity(0.25)],
                startPoint: .leading, endPoint: .trailing
            )
            .clipShape(Capsule())
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
    }
}
```

В `StatsApp/Status/StatusItemController.swift` найди место, где создаётся
`MenuBarCapsuleView(priceText:)`, и передай туда состояние лимитов из того же
источника, что использует вью-модель попапа. Ширина айтема в меню-баре
пересчитывается при смене контента — проверь, что вызов пересчёта размера
остался после добавления колец.

- [ ] **Шаг 2: Прогнать всю сюиту**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS'`
Ожидание: PASS.

- [ ] **Шаг 3: Проверить глазами в обеих темах**

Собери и запусти приложение. Переключи macOS между светлой и тёмной темой
(Системные настройки → Оформление). Убедись, что белое кольцо OpenCode читается
в обеих. Это единственная проверка в фиче, которую автотест не заменяет: если
контура 0.5pt не хватает — увеличивай толщину штриха или уходи от чистого белого
к очень светлому серому, и запиши что выбрал в спеке в §13.

- [ ] **Шаг 4: Коммит**

```bash
git add StatsApp/Status/LimitRingView.swift StatsApp/Status/MenuBarCapsuleView.swift StatsApp/Status/StatusItemController.swift
git commit -m "feat(limits): нарисовать три кольца лимитов в капсуле меню-бара"
```

---

### Задача 9: Настройка cookie OpenCode

**Файлы:**
- Создать: `StatsApp/Settings/OpenCodeCookieSection.swift`
- Изменить: `StatsApp/Settings/GeneralTabView.swift`
- Тест: `Tests/StatsAppTests/Settings/OpenCodeCookieStoreTests.swift`

**Интерфейсы:**
- Использует: `KeychainStore`, `OpenCodeLimitsFetcher.keychainService`, `OpenCodeUsageParser.normalizeCookie`, `LimitsFetching`.
- Отдаёт: `OpenCodeCookieStore(keychain:account:)` с `load()`, `save(_:) throws`, `clear() throws`; вью `OpenCodeCookieSection`.

- [ ] **Шаг 1: Написать падающий тест хранения**

Создай `Tests/StatsAppTests/Settings/OpenCodeCookieStoreTests.swift`:

```swift
import XCTest
@testable import StatsApp

final class OpenCodeCookieStoreTests: XCTestCase {

    private func store() -> (OpenCodeCookieStore, MemoryKeychainStore) {
        let keychain = MemoryKeychainStore()
        return (OpenCodeCookieStore(keychain: keychain, account: "tester"), keychain)
    }

    // Cookie — секрет, лежит только в Keychain и только в auth-виде.
    func test_saves_normalized_cookie_to_keychain() throws {
        let (subject, keychain) = store()
        try subject.save("  Fe26.2**abc  ")
        XCTAssertEqual(keychain.get(account: "tester",
                                    service: OpenCodeLimitsFetcher.keychainService),
                       "auth=Fe26.2**abc")
    }

    func test_load_returns_nil_when_empty() {
        let (subject, _) = store()
        XCTAssertNil(subject.load())
    }

    func test_clear_removes_value() throws {
        let (subject, keychain) = store()
        try subject.save("Fe26.2**abc")
        try subject.clear()
        XCTAssertNil(keychain.get(account: "tester",
                                  service: OpenCodeLimitsFetcher.keychainService))
    }

    // Пустая строка — это «убрать», а не «сохранить пустоту».
    func test_saving_blank_clears() throws {
        let (subject, keychain) = store()
        try subject.save("Fe26.2**abc")
        try subject.save("   ")
        XCTAssertNil(keychain.get(account: "tester",
                                  service: OpenCodeLimitsFetcher.keychainService))
    }
}
```

- [ ] **Шаг 2: Прогнать — должен не собраться**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/OpenCodeCookieStoreTests`
Ожидание: провал компиляции, `cannot find 'OpenCodeCookieStore' in scope`.

- [ ] **Шаг 3: Написать хранилище и секцию настроек**

Создай `StatsApp/Settings/OpenCodeCookieSection.swift`:

```swift
import SwiftUI

/// Cookie сессии opencode.ai. Секрет — живёт только в Keychain, в UserDefaults и
/// в логи не попадает никогда.
struct OpenCodeCookieStore {
    private let keychain: KeychainStore
    private let account: String

    init(keychain: KeychainStore = MacOSKeychainStore(), account: String = NSUserName()) {
        self.keychain = keychain
        self.account = account
    }

    func load() -> String? {
        keychain.get(account: account, service: OpenCodeLimitsFetcher.keychainService)
    }

    /// Пустая строка means «убрать»: хранить пустой секрет незачем.
    func save(_ raw: String) throws {
        let normalized = OpenCodeUsageParser.normalizeCookie(raw)
        guard !normalized.isEmpty else {
            try clear()
            return
        }
        try keychain.set(normalized, account: account,
                         service: OpenCodeLimitsFetcher.keychainService)
    }

    func clear() throws {
        try keychain.delete(account: account, service: OpenCodeLimitsFetcher.keychainService)
    }
}

struct OpenCodeCookieSection: View {
    @State private var cookie: String = ""
    @State private var checkResult: String?
    @State private var checking = false

    private let store = OpenCodeCookieStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Лимиты OpenCode")
                .font(.headline)

            Text("""
            Ключи моделей для этого не годятся — нужна сессионная cookie сайта. \
            Открой opencode.ai, залогинься, в DevTools скопируй значение cookie \
            auth и вставь сюда.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)

            SecureField("auth=Fe26.2**…", text: $cookie)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Сохранить") { save() }
                Button(checking ? "Проверяю…" : "Проверить") { Task { await check() } }
                    .disabled(checking)
                if let checkResult {
                    Text(checkResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { cookie = store.load() ?? "" }
    }

    private func save() {
        do {
            try store.save(cookie)
            checkResult = cookie.trimmingCharacters(in: .whitespaces).isEmpty ? "убрана" : "сохранена"
        } catch {
            // В текст ошибки значение cookie не подставляем ни при каких условиях.
            checkResult = "не удалось сохранить"
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        do { try store.save(cookie) } catch { checkResult = "не удалось сохранить"; return }

        let limits = await OpenCodeLimitsFetcher().fetch()
        switch limits.status {
        case .ok:
            let windows = limits.windows.count
            checkResult = "работает, окон: \(windows)"
        case .unconfigured:  checkResult = "cookie пустая"
        case .unauthorized:  checkResult = "cookie не принята"
        case .unavailable:   checkResult = "страница не разобралась"
        case .stale, .throttled: checkResult = "не достучался"
        }
    }
}
```

В `StatsApp/Settings/GeneralTabView.swift` добавь секцию в конец основного
`VStack`/`Form` (точное место смотри в текущем коде — повтори отступы соседних
секций):

```swift
            Divider()
            OpenCodeCookieSection()
```

- [ ] **Шаг 4: Прогнать — должен пройти**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/OpenCodeCookieStoreTests`
Ожидание: PASS, 4 теста.

- [ ] **Шаг 5: Прогнать всю сюиту**

Запуск: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS'`
Ожидание: PASS, все существующие тесты плюс новые.

- [ ] **Шаг 6: Обновить CHANGELOG**

В `CHANGELOG.md` в секцию `## [Unreleased]` → `### Добавлено`:

```markdown
- Мониторинг лимитов: три кольца в капсуле меню-бара показывают, сколько
  израсходовано у Claude, Codex и OpenCode. Разбор по окнам с временем сброса —
  на вкладке «Расходы». Cookie OpenCode вставляется в настройках.
```

- [ ] **Шаг 7: Коммит**

```bash
git add StatsApp/Settings/OpenCodeCookieSection.swift StatsApp/Settings/GeneralTabView.swift Tests/StatsAppTests/Settings/OpenCodeCookieStoreTests.swift CHANGELOG.md
git commit -m "feat(limits): добавить настройку cookie opencode"
```

---

## Что осталось за рамками

Прогноз по темпу расхода («при текущем темпе Codex кончится завтра к 18:00») —
второй этап, отдельной спекой. Данные для него копятся с первого дня: таблица
`limit_snapshots` пишет ступени, ретеншен 60 дней.

Лимиты на WidgetKit-виджете рабочего стола. `WidgetSnapshot` в этой фиче не
менялся, поля добавятся аддитивно через `decodeIfPresent`.
