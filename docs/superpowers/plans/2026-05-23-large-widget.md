# Large widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить `.systemLarge` family в виджет: слева — мои траты с дельтой и top-моделями за выбранный период, справа — топ-8 лидерборда с дельтой ранга и опц. строкой «я».

**Architecture:** Расширяем существующий `WidgetSnapshot` (на диске JSON, в `~/Library/Containers/.../snapshot.json`) тремя полями: `aiCostPrev` и `leaderboard` per period, `myFriendCode` в корне. `SyncCoordinator.buildAndWriteWidgetSnapshot()` дополнительно читает `leaderboard_cache.payload_json` и считает prev-cost. Виджет получает Large вьюху, которая переиспользует `SummaryColumn`/`ModelRow` слева и `DropdownFormat` форматтеры (вынесем в `Shared/Util/`) для дельт. Аватарки в виджете не показываем.

**Tech Stack:** Swift 5.9, SwiftUI, WidgetKit, GRDB.swift 6.x, XCTest, xcodegen.

**Спека:** [docs/superpowers/specs/2026-05-23-large-widget-design.md](../specs/2026-05-23-large-widget-design.md)

**Контекст:** дельта-and-rank уже в main (`DropdownFormat` в `StatsApp/Status/DropdownSections.swift`, `previousRank` в `LeaderboardEntry`, `previousPeriodDays` в `DateUtils`). Работаем с новой ветки `feat/large-widget` от текущего main.

---

## File Structure

**Создаём:**
- `Tests/StatsAppTests/WidgetSnapshotTests.swift` — round-trip и back-compat для расширенного снапшота.
- `Tests/StatsAppTests/Sync/SyncCoordinatorSnapshotTests.swift` — что `buildAndWriteWidgetSnapshot` пишет prev-cost и leaderboard slice из мок-БД.
- `StatsWidget/Views/LargeView.swift` — `LargeView`, `LeaderboardColumn`, `LeaderboardRow` (отдельный файл, чтобы `StatsWidgetView.swift` не превратился в кашу).

**Меняем:**
- `Shared/WidgetSnapshot.swift` — поля `aiCostPrev`, `leaderboard`, `myFriendCode` + back-compat decoder.
- `Shared/Util/Formatters.swift` — **новое**: переносим сюда `DropdownFormat` (типы `CostDeltaContent`, `RankDeltaContent`, `DeltaDirection` тоже).
- `StatsApp/Status/DropdownSections.swift` — выпиливаем `DropdownFormat`/`CostDeltaContent`/`RankDeltaContent`/`DeltaDirection` (переехали в Shared), оставляем только SwiftUI views.
- `StatsApp/Sync/SyncCoordinator.swift` — `makeSlice` расширяется на prev-окно и leaderboard, `buildAndWriteWidgetSnapshot` передаёт `myFriendCode`.
- `StatsWidget/StatsWidget.swift` — `.supportedFamilies` += `.systemLarge`.
- `StatsWidget/StatsTimelineProvider.swift` — `StatsEntry` обогащается `aiCostPrev`, `leaderboard`, `myFriendCode`.
- `StatsWidget/Views/StatsWidgetView.swift` — switch family case для `.systemLarge`.
- `Shared/Resources/en.lproj/Localizable.strings`, `Shared/Resources/ru.lproj/Localizable.strings` — 3 новых ключа (`section.leaderboard`, `widget.leaderboard.no_account`, `widget.leaderboard.empty`).
- `CHANGELOG.md` — запись в `## [Unreleased]`.
- `README.md` — упомянуть Large.

---

## Task 1: Вынести DropdownFormat в Shared

`DropdownFormat` сейчас в `StatsApp/Status/DropdownSections.swift` и виден только app-таргету. Виджету нужны те же форматтеры — перетаскиваем в `Shared/Util/`, оба таргета подхватят (xcodegen цепляет `path: Shared` обоим).

**Files:**
- Create: `Shared/Util/Formatters.swift`
- Modify: `StatsApp/Status/DropdownSections.swift`

- [ ] **Step 1: Прочитать существующий DropdownFormat**

Запустить:
```bash
sed -n '1,75p' StatsApp/Status/DropdownSections.swift
```

Убедиться, что есть `DropdownFormat`, `CostDeltaContent`, `RankDeltaContent`, `DeltaDirection`. Скопировать их целиком.

- [ ] **Step 2: Создать `Shared/Util/Formatters.swift`**

Создать файл с содержимым:

```swift
import Foundation

// MARK: - delta content types

enum DeltaDirection: Equatable {
    case up
    case down
}

struct CostDeltaContent: Equatable {
    let arrow: String       // "▲" или "▼"
    let amount: String      // "+$27.60" или "−$50.00"
    let labelKey: String    // ключ для NSLocalizedString
    let direction: DeltaDirection
}

struct RankDeltaContent: Equatable {
    enum Kind: Equatable {
        case change(magnitude: Int, direction: DeltaDirection)
        case new
    }
    let kind: Kind
}

// MARK: - helpers (shared between sections and widgets)

enum DropdownFormat {
    static func tokens(_ count: Int64) -> String {
        let value = Double(count)
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fk", value / 1_000) }
        return "\(count)"
    }

    static func loc(_ count: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// "owner/name" → "name"
    static func repoShortName(_ full: String) -> String {
        guard let slash = full.firstIndex(of: "/") else { return full }
        return String(full[full.index(after: slash)...])
    }

    static func formatCostDelta(current: Double, previous: Double, period: Period) -> CostDeltaContent? {
        guard current > 0 else { return nil }
        let diff = current - previous
        // Скрываем дельту, если разница меньше копейки — после округления до $0.00 показывать стрелку бессмысленно.
        guard abs(diff) >= 0.005 else { return nil }
        let direction: DeltaDirection = diff > 0 ? .up : .down
        let arrow = diff > 0 ? "▲" : "▼"
        let sign = diff > 0 ? "+" : "−"
        let amount = String(format: "%@$%.2f", sign, abs(diff))
        let labelKey: String
        switch period {
        case .day:   labelKey = "delta.vs_yesterday"
        case .week:  labelKey = "delta.vs_prev_week"
        case .month: labelKey = "delta.vs_prev_month"
        }
        return CostDeltaContent(arrow: arrow, amount: amount, labelKey: labelKey, direction: direction)
    }

    static func formatRankDelta(current: Int, previous: Int?) -> RankDeltaContent? {
        guard let previous else {
            return RankDeltaContent(kind: .new)
        }
        let diff = previous - current   // подъём в рейтинге = current уменьшился = diff положительный
        guard diff != 0 else { return nil }
        let direction: DeltaDirection = diff > 0 ? .up : .down
        return RankDeltaContent(kind: .change(magnitude: abs(diff), direction: direction))
    }
}
```

- [ ] **Step 3: Удалить дубль из `DropdownSections.swift`**

Открыть `StatsApp/Status/DropdownSections.swift` и удалить блоки:
- `enum DeltaDirection` (строки ~5-8)
- `struct CostDeltaContent` (~10-15)
- `struct RankDeltaContent` (~17-23)
- `enum DropdownFormat` (~27-75)

Оставить SwiftUI views (`CostDelta`, `RankDelta`, остальные секции), которые их используют. Импорт `SwiftUI` остаётся.

Добавить наверх (если ещё нет) `import Foundation` — но он не нужен, `SwiftUI` его подтягивает. Просто убедиться, что файл собирается.

- [ ] **Step 4: Сгенерить проект и собрать**

```bash
xcodegen generate
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -configuration Debug build 2>&1 | tail -20
```

Ожидание: BUILD SUCCEEDED. Если есть ошибки про дубль типов — какой-то блок не удалён.

- [ ] **Step 5: Запустить тесты форматтеров**

```bash
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -only-testing:StatsAppTests/CostDeltaTests -only-testing:StatsAppTests/RankDeltaTests 2>&1 | tail -20
```

Ожидание: тесты `CostDeltaTests` и `RankDeltaTests` зелёные. Они ссылаются на `DropdownFormat.formatCostDelta`/`formatRankDelta` — теперь они в Shared, но `@testable import StatsApp` всё равно их видит, потому что `Shared/` входит в `StatsApp` source paths.

- [ ] **Step 6: Commit**

```bash
git add Shared/Util/Formatters.swift StatsApp/Status/DropdownSections.swift
git commit -m "refactor(shared): вынести DropdownFormat в Shared/Util/Formatters.swift"
```

---

## Task 2: Расширить WidgetSnapshot (TDD)

Добавляем поля `aiCostPrev`, `leaderboard`, `myFriendCode` и тип `LeaderboardSlice`. Back-compat decoder: старый JSON без новых полей читается с дефолтами (`aiCostPrev = 0`, `leaderboard = nil`, `myFriendCode = nil`).

**Files:**
- Modify: `Shared/WidgetSnapshot.swift`
- Create: `Tests/StatsAppTests/WidgetSnapshotTests.swift`

- [ ] **Step 1: Написать падающий тест back-compat**

Создать `Tests/StatsAppTests/WidgetSnapshotTests.swift`:

```swift
import XCTest
@testable import StatsApp

final class WidgetSnapshotTests: XCTestCase {
    func test_decode_legacy_json_without_new_fields_uses_defaults() throws {
        // JSON в старом формате — без aiCostPrev, leaderboard, myFriendCode.
        let json = """
        {
            "generatedAt": "2026-05-23T12:00:00Z",
            "githubEnabled": true,
            "day":   { "aiCost": 10.0, "aiTokens": 100, "commits": 1, "uniqueRepos": 1, "topModels": [] },
            "week":  { "aiCost": 50.0, "aiTokens": 500, "commits": 5, "uniqueRepos": 2, "topModels": [] },
            "month": { "aiCost": 200.0, "aiTokens": 2000, "commits": 20, "uniqueRepos": 3, "topModels": [] }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: json)

        XCTAssertEqual(snapshot.day.aiCost, 10.0)
        XCTAssertEqual(snapshot.day.aiCostPrev, 0.0)
        XCTAssertNil(snapshot.day.leaderboard)
        XCTAssertNil(snapshot.myFriendCode)
    }
}
```

- [ ] **Step 2: Запустить тест — должен упасть**

```bash
xcodegen generate
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -only-testing:StatsAppTests/WidgetSnapshotTests/test_decode_legacy_json_without_new_fields_uses_defaults 2>&1 | tail -20
```

Ожидание: FAIL — поле `aiCostPrev` не существует в `PeriodSlice`, либо `myFriendCode` в `WidgetSnapshot`.

- [ ] **Step 3: Расширить `Shared/WidgetSnapshot.swift`**

Полностью заменить содержимое `Shared/WidgetSnapshot.swift` на:

```swift
import Foundation

/// Mini-snapshot всех метрик за каждый период. Пишется app'ом после sync
/// и читается виджетом из своего sandbox-контейнера.
struct WidgetSnapshot: Codable, Equatable {
    let generatedAt: Date
    let day: PeriodSlice
    let week: PeriodSlice
    let month: PeriodSlice
    let githubEnabled: Bool
    let myFriendCode: String?

    init(
        generatedAt: Date,
        day: PeriodSlice,
        week: PeriodSlice,
        month: PeriodSlice,
        githubEnabled: Bool,
        myFriendCode: String?
    ) {
        self.generatedAt = generatedAt
        self.day = day
        self.week = week
        self.month = month
        self.githubEnabled = githubEnabled
        self.myFriendCode = myFriendCode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        self.day = try c.decode(PeriodSlice.self, forKey: .day)
        self.week = try c.decode(PeriodSlice.self, forKey: .week)
        self.month = try c.decode(PeriodSlice.self, forKey: .month)
        self.githubEnabled = try c.decode(Bool.self, forKey: .githubEnabled)
        self.myFriendCode = try c.decodeIfPresent(String.self, forKey: .myFriendCode)
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt, day, week, month, githubEnabled, myFriendCode
    }

    struct PeriodSlice: Codable, Equatable {
        let aiCost: Double
        let aiCostPrev: Double
        let aiTokens: Int64
        let commits: Int64
        let uniqueRepos: Int
        let topModels: [ModelEntry]
        let leaderboard: LeaderboardSlice?

        init(
            aiCost: Double,
            aiCostPrev: Double,
            aiTokens: Int64,
            commits: Int64,
            uniqueRepos: Int,
            topModels: [ModelEntry],
            leaderboard: LeaderboardSlice?
        ) {
            self.aiCost = aiCost
            self.aiCostPrev = aiCostPrev
            self.aiTokens = aiTokens
            self.commits = commits
            self.uniqueRepos = uniqueRepos
            self.topModels = topModels
            self.leaderboard = leaderboard
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.aiCost = try c.decode(Double.self, forKey: .aiCost)
            self.aiCostPrev = try c.decodeIfPresent(Double.self, forKey: .aiCostPrev) ?? 0
            self.aiTokens = try c.decode(Int64.self, forKey: .aiTokens)
            self.commits = try c.decode(Int64.self, forKey: .commits)
            self.uniqueRepos = try c.decode(Int.self, forKey: .uniqueRepos)
            self.topModels = try c.decode([ModelEntry].self, forKey: .topModels)
            self.leaderboard = try c.decodeIfPresent(LeaderboardSlice.self, forKey: .leaderboard)
        }

        private enum CodingKeys: String, CodingKey {
            case aiCost, aiCostPrev, aiTokens, commits, uniqueRepos, topModels, leaderboard
        }
    }

    struct ModelEntry: Codable, Equatable, Hashable {
        let model: String
        let source: String
        let costUsd: Double
        let inputTokens: Int64
        let outputTokens: Int64
    }

    struct LeaderboardSlice: Codable, Equatable {
        let entries: [Entry]      // <= 8
        let meBelow: Entry?       // nil, если я в top-8 или меня нет вовсе

        struct Entry: Codable, Equatable {
            let rank: Int
            let previousRank: Int?
            let displayName: String
            let tokensTotal: Int64
            let isMe: Bool
        }
    }
}

enum WidgetSnapshotIO {
    /// Bundle id виджет-таргета, в чей контейнер app пишет snapshot.
    static let widgetBundleID = "com.sergeytovarov.aistats.widget"

    static var writeURL: URL {
        let realHome = URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory())
        return realHome
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Library/Application Support/ai-stats")
            .appendingPathComponent("snapshot.json")
    }

    static var readURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ai-stats/snapshot.json")
    }

    static func write(_ snapshot: WidgetSnapshot) throws {
        let url = writeURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: readURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
```

- [ ] **Step 4: Запустить тест — должен пройти**

```bash
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -only-testing:StatsAppTests/WidgetSnapshotTests 2>&1 | tail -20
```

Ожидание: PASS. Если другие тесты сломались из-за изменённого `init` — следующий шаг их пофиксит.

- [ ] **Step 5: Починить вызовы `WidgetSnapshot(...)` и `PeriodSlice(...)` в app**

`SyncCoordinator` уже строит снапшот по старому api. Скомпилируется только после Task 3, но чтобы не блокироваться — временно добавить дефолты в инициализатор `WidgetSnapshot.init`:

Найти `SyncCoordinator.swift` строки `WidgetSnapshot(generatedAt: ...)` и `WidgetSnapshot.PeriodSlice(aiCost: ...)`. Добавить недостающие аргументы:

```swift
// в makeSlice:
return WidgetSnapshot.PeriodSlice(
    aiCost: totals.totalCost,
    aiCostPrev: 0,                // placeholder, заполняется в Task 3
    aiTokens: totals.totalInputTokens + totals.totalOutputTokens,
    commits: gh.totalCommits,
    uniqueRepos: gh.uniqueRepos,
    topModels: models.map { ... },
    leaderboard: nil               // placeholder, заполняется в Task 3
)

// в buildAndWriteWidgetSnapshot:
let snapshot = WidgetSnapshot(
    generatedAt: nowDate,
    day: slices.0,
    week: slices.1,
    month: slices.2,
    githubEnabled: anyCommits > 0 || anyRepos > 0,
    myFriendCode: nil              // placeholder, заполняется в Task 3
)
```

- [ ] **Step 6: Написать round-trip тест**

Добавить в `WidgetSnapshotTests.swift`:

```swift
func test_roundtrip_with_full_leaderboard_slice() throws {
    let me = WidgetSnapshot.LeaderboardSlice.Entry(
        rank: 42, previousRank: 50, displayName: "Я", tokensTotal: 200, isMe: true
    )
    let lb = WidgetSnapshot.LeaderboardSlice(
        entries: [
            .init(rank: 1, previousRank: 11, displayName: "Серёжа", tokensTotal: 12_400, isMe: false),
            .init(rank: 2, previousRank: 5,  displayName: "Вася",    tokensTotal: 9_800,  isMe: false),
        ],
        meBelow: me
    )
    let slice = WidgetSnapshot.PeriodSlice(
        aiCost: 250.0, aiCostPrev: 222.40,
        aiTokens: 12_400_000, commits: 5, uniqueRepos: 2,
        topModels: [], leaderboard: lb
    )
    let snapshot = WidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_716_336_000),
        day: slice, week: slice, month: slice,
        githubEnabled: true,
        myFriendCode: "abc123"
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(snapshot)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

    XCTAssertEqual(decoded, snapshot)
    XCTAssertEqual(decoded.day.leaderboard?.meBelow?.rank, 42)
    XCTAssertEqual(decoded.myFriendCode, "abc123")
}

func test_decode_legacy_json_with_partial_period_slice() throws {
    // PeriodSlice без leaderboard и aiCostPrev — должны дефолтиться.
    let json = """
    {
        "generatedAt": "2026-05-23T12:00:00Z",
        "githubEnabled": false,
        "day":   { "aiCost": 5.0, "aiTokens": 50, "commits": 0, "uniqueRepos": 0, "topModels": [] },
        "week":  { "aiCost": 5.0, "aiTokens": 50, "commits": 0, "uniqueRepos": 0, "topModels": [] },
        "month": { "aiCost": 5.0, "aiTokens": 50, "commits": 0, "uniqueRepos": 0, "topModels": [] }
    }
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(WidgetSnapshot.self, from: json)
    XCTAssertEqual(snapshot.day.aiCostPrev, 0)
    XCTAssertNil(snapshot.day.leaderboard)
}
```

- [ ] **Step 7: Запустить все тесты в файле**

```bash
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -only-testing:StatsAppTests/WidgetSnapshotTests 2>&1 | tail -20
```

Ожидание: 3 теста зелёные.

- [ ] **Step 8: Commit**

```bash
git add Shared/WidgetSnapshot.swift Tests/StatsAppTests/WidgetSnapshotTests.swift StatsApp/Sync/SyncCoordinator.swift
git commit -m "feat(widget): расширить WidgetSnapshot полями aiCostPrev/leaderboard/myFriendCode"
```

---

## Task 3: SyncCoordinator пишет prev-cost и leaderboard в snapshot (TDD)

Заполняем placeholder'ы из Task 2 настоящими значениями: prev-cost из второго вызова `aiTotals`, leaderboard из `leaderboard_cache.payload_json`, `myFriendCode` из `MyProfileRow`.

**Files:**
- Modify: `StatsApp/Sync/SyncCoordinator.swift`
- Create: `Tests/StatsAppTests/Sync/SyncCoordinatorSnapshotTests.swift`

- [ ] **Step 1: Написать падающий тест — prev-cost попадает в slice**

Создать `Tests/StatsAppTests/Sync/SyncCoordinatorSnapshotTests.swift`:

```swift
import XCTest
import GRDB
@testable import StatsApp

final class SyncCoordinatorSnapshotTests: XCTestCase {
    /// Кладёт траты «вчера» и «сегодня», ожидает что snapshot.day.aiCostPrev = вчерашняя сумма.
    func test_snapshot_day_slice_contains_prev_cost() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        // Now = 2026-05-23 12:00:00 UTC. Lookback day = 0 → today only. Prev = вчера.
        let now = Date(timeIntervalSince1970: 1_779_873_600)  // 2026-05-23T12:00:00Z
        let today = DateUtils.daysRange(endingAt: now, lookback: 0).first!     // "2026-05-23"
        let yesterday = DateUtils.previousPeriodDays(endingAt: now, lookback: 0).first! // "2026-05-22"

        try await dbq.write { db in
            try AIUsageRow(
                id: nil, day: today, source: "claude", modelsJson: "[]",
                inputTokens: 100, outputTokens: 100, costUsd: 250.0,
                updatedAt: "2026-05-23T12:00:00Z"
            ).insert(db)
            try AIUsageRow(
                id: nil, day: yesterday, source: "claude", modelsJson: "[]",
                inputTokens: 50, outputTokens: 50, costUsd: 222.40,
                updatedAt: "2026-05-22T12:00:00Z"
            ).insert(db)
        }

        let coordinator = await SyncCoordinator(db: dbq, now: { now })

        // Триггерим запись snapshot'а через runOnce с пустым фетчером (всё уже в DB).
        let fetcher = await MockFetcher(result: .aiUsage(CcusagePayload(dayRows: [], modelRows: [])))
        try await coordinator.runOnce(source: "ccusage", fetchers: [fetcher])

        let snapshot = WidgetSnapshotIO.read()
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot!.day.aiCost, 250.0, accuracy: 0.001)
        XCTAssertEqual(snapshot!.day.aiCostPrev, 222.40, accuracy: 0.001)
    }

    /// Если в leaderboard_cache есть payload — top-N попадает в slice; если меня нет в топе, я в meBelow.
    func test_snapshot_day_slice_contains_leaderboard_top8_and_meBelow() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        try await dbq.write { db in
            // Свой профиль — нужен для myFriendCode и meBelow.
            try StatsQueries.saveMyProfile(db, MyProfileRow(
                friendCode: "me123", displayName: "Я", avatarPath: nil, sharingEnabled: true, serverUserId: 1
            ))
            // Лидерборд: 10 человек, я — 9-й.
            let payload = """
            {
              "period": "day",
              "as_of": "2026-05-23T12:00:00Z",
              "entries": [
                {"friend_code":"u1","display_name":"A","rank":1,"previous_rank":2,"tokens_total":1000,"is_me":false},
                {"friend_code":"u2","display_name":"B","rank":2,"previous_rank":1,"tokens_total":900, "is_me":false},
                {"friend_code":"u3","display_name":"C","rank":3,"previous_rank":null,"tokens_total":800,"is_me":false},
                {"friend_code":"u4","display_name":"D","rank":4,"previous_rank":4,"tokens_total":700, "is_me":false},
                {"friend_code":"u5","display_name":"E","rank":5,"previous_rank":3,"tokens_total":600, "is_me":false},
                {"friend_code":"u6","display_name":"F","rank":6,"previous_rank":6,"tokens_total":500, "is_me":false},
                {"friend_code":"u7","display_name":"G","rank":7,"previous_rank":8,"tokens_total":400, "is_me":false},
                {"friend_code":"u8","display_name":"H","rank":8,"previous_rank":7,"tokens_total":300, "is_me":false},
                {"friend_code":"me123","display_name":"Я","rank":9,"previous_rank":12,"tokens_total":200,"is_me":true},
                {"friend_code":"u10","display_name":"J","rank":10,"previous_rank":null,"tokens_total":100,"is_me":false}
              ]
            }
            """
            try StatsQueries.saveLeaderboardCache(db, period: "day", payloadJson: payload)
        }

        let now = Date(timeIntervalSince1970: 1_779_873_600)
        let coordinator = await SyncCoordinator(db: dbq, now: { now })
        let fetcher = await MockFetcher(result: .aiUsage(CcusagePayload(dayRows: [], modelRows: [])))
        try await coordinator.runOnce(source: "ccusage", fetchers: [fetcher])

        let snapshot = WidgetSnapshotIO.read()
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot!.myFriendCode, "me123")
        let lb = snapshot!.day.leaderboard
        XCTAssertNotNil(lb)
        XCTAssertEqual(lb!.entries.count, 8)
        XCTAssertEqual(lb!.entries.first?.rank, 1)
        XCTAssertEqual(lb!.entries.last?.rank, 8)
        // Я — 9-й, в топ-8 не попал, должен быть в meBelow.
        XCTAssertNotNil(lb!.meBelow)
        XCTAssertEqual(lb!.meBelow?.rank, 9)
        XCTAssertEqual(lb!.meBelow?.isMe, true)
    }

    /// Если меня нет в кэше вообще — meBelow = nil.
    func test_snapshot_leaderboard_meBelow_nil_when_me_absent() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        try await dbq.write { db in
            try StatsQueries.saveMyProfile(db, MyProfileRow(
                friendCode: "ghost", displayName: "?", avatarPath: nil, sharingEnabled: true, serverUserId: 1
            ))
            let payload = """
            {"period":"day","as_of":"2026-05-23T12:00:00Z","entries":[
              {"friend_code":"u1","display_name":"A","rank":1,"previous_rank":null,"tokens_total":1000,"is_me":false}
            ]}
            """
            try StatsQueries.saveLeaderboardCache(db, period: "day", payloadJson: payload)
        }

        let now = Date(timeIntervalSince1970: 1_779_873_600)
        let coordinator = await SyncCoordinator(db: dbq, now: { now })
        let fetcher = await MockFetcher(result: .aiUsage(CcusagePayload(dayRows: [], modelRows: [])))
        try await coordinator.runOnce(source: "ccusage", fetchers: [fetcher])

        let lb = WidgetSnapshotIO.read()!.day.leaderboard!
        XCTAssertEqual(lb.entries.count, 1)
        XCTAssertNil(lb.meBelow)
    }

    /// Если кэша лидерборда нет — leaderboard = nil.
    func test_snapshot_leaderboard_nil_when_no_cache() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        let now = Date(timeIntervalSince1970: 1_779_873_600)
        let coordinator = await SyncCoordinator(db: dbq, now: { now })
        let fetcher = await MockFetcher(result: .aiUsage(CcusagePayload(dayRows: [], modelRows: [])))
        try await coordinator.runOnce(source: "ccusage", fetchers: [fetcher])

        let snapshot = WidgetSnapshotIO.read()!
        XCTAssertNil(snapshot.day.leaderboard)
        XCTAssertNil(snapshot.myFriendCode)
    }
}

// Локальный MockFetcher — копия из SyncCoordinatorTests (намеренно дублируем, файлы тестов независимы).
private actor MockFetcher: Fetcher {
    var callCount = 0
    var lastSince: Date?
    var result: FetchResult
    init(result: FetchResult) { self.result = result }
    func fetch(since: Date) async throws -> FetchResult {
        callCount += 1
        lastSince = since
        return result
    }
}
```

**Внимание про `WidgetSnapshotIO.read()`/`write()` в тестах:** на CI/локально записывает в реальный `~/Library/Containers/...`. Тесты делают side effect на диск. Это уже так у существующего snapshot-write кода — не плодим инфраструктуру в этом плане. Если на каком-то прогоне тест мешает другим — добавим setUp/tearDown с удалением файла. Пока не нужно.

- [ ] **Step 2: Запустить тесты — должны упасть**

```bash
xcodegen generate
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -only-testing:StatsAppTests/SyncCoordinatorSnapshotTests 2>&1 | tail -30
```

Ожидание: FAIL. `aiCostPrev = 0` вместо `222.40`, `leaderboard = nil`, `myFriendCode = nil` — placeholder'ы из Task 2 ещё не заменены.

- [ ] **Step 3: Реализовать заполнение prev-cost и leaderboard**

Полностью заменить `buildAndWriteWidgetSnapshot` и `makeSlice` в `StatsApp/Sync/SyncCoordinator.swift`:

```swift
/// Считает текущие totals за Day/Week/Month, prev-cost для дельт, и leaderboard slice.
/// Пишет JSON в контейнер виджета.
private func buildAndWriteWidgetSnapshot() throws {
    let nowDate = now()
    let dayDays = DateUtils.daysRange(endingAt: nowDate, lookback: Period.day.lookbackDays)
    let weekDays = DateUtils.daysRange(endingAt: nowDate, lookback: Period.week.lookbackDays)
    let monthDays = DateUtils.daysRange(endingAt: nowDate, lookback: Period.month.lookbackDays)
    let dayPrev = DateUtils.previousPeriodDays(endingAt: nowDate, lookback: Period.day.lookbackDays)
    let weekPrev = DateUtils.previousPeriodDays(endingAt: nowDate, lookback: Period.week.lookbackDays)
    let monthPrev = DateUtils.previousPeriodDays(endingAt: nowDate, lookback: Period.month.lookbackDays)

    struct BuildResult {
        let day: WidgetSnapshot.PeriodSlice
        let week: WidgetSnapshot.PeriodSlice
        let month: WidgetSnapshot.PeriodSlice
        let myFriendCode: String?
    }

    let result: BuildResult = try db.read { db in
        let myCode = try StatsQueries.loadMyProfile(db)?.friendCode
        return BuildResult(
            day: try Self.makeSlice(in: db, days: dayDays, prevDays: dayPrev, leaderboardPeriod: "day", myFriendCode: myCode),
            week: try Self.makeSlice(in: db, days: weekDays, prevDays: weekPrev, leaderboardPeriod: "week", myFriendCode: myCode),
            month: try Self.makeSlice(in: db, days: monthDays, prevDays: monthPrev, leaderboardPeriod: "month", myFriendCode: myCode),
            myFriendCode: myCode
        )
    }

    let anyCommits = result.day.commits + result.week.commits + result.month.commits
    let anyRepos = max(result.day.uniqueRepos, result.week.uniqueRepos, result.month.uniqueRepos)

    let snapshot = WidgetSnapshot(
        generatedAt: nowDate,
        day: result.day,
        week: result.week,
        month: result.month,
        githubEnabled: anyCommits > 0 || anyRepos > 0,
        myFriendCode: result.myFriendCode
    )
    try WidgetSnapshotIO.write(snapshot)
}

private static func makeSlice(
    in db: GRDB.Database,
    days: [String],
    prevDays: [String],
    leaderboardPeriod: String,
    myFriendCode: String?
) throws -> WidgetSnapshot.PeriodSlice {
    let totals = try StatsQueries.aiTotals(in: db, days: days)
    let totalsPrev = try StatsQueries.aiTotals(in: db, days: prevDays)
    let gh = try StatsQueries.githubTotals(in: db, days: days)
    let models = try StatsQueries.topModels(in: db, days: days, limit: 4)
    let lb = try Self.makeLeaderboardSlice(in: db, period: leaderboardPeriod, myFriendCode: myFriendCode)

    return WidgetSnapshot.PeriodSlice(
        aiCost: totals.totalCost,
        aiCostPrev: totalsPrev.totalCost,
        aiTokens: totals.totalInputTokens + totals.totalOutputTokens,
        commits: gh.totalCommits,
        uniqueRepos: gh.uniqueRepos,
        topModels: models.map {
            WidgetSnapshot.ModelEntry(
                model: $0.model, source: $0.source, costUsd: $0.costUsd,
                inputTokens: $0.inputTokens, outputTokens: $0.outputTokens
            )
        },
        leaderboard: lb
    )
}

/// Парсит leaderboard_cache.payload_json в LeaderboardSlice: top-8 entries + meBelow если я ниже.
private static func makeLeaderboardSlice(
    in db: GRDB.Database, period: String, myFriendCode: String?
) throws -> WidgetSnapshot.LeaderboardSlice? {
    guard let row = try StatsQueries.loadLeaderboardCache(db, period: period) else { return nil }
    guard let data = row.payloadJson.data(using: .utf8) else { return nil }
    let decoder = JSONDecoder()
    guard let resp = try? decoder.decode(LeaderboardResponse.self, from: data) else { return nil }

    func mapEntry(_ e: LeaderboardEntry) -> WidgetSnapshot.LeaderboardSlice.Entry {
        WidgetSnapshot.LeaderboardSlice.Entry(
            rank: e.rank,
            previousRank: e.previousRank,
            displayName: e.displayName,
            tokensTotal: e.tokensTotal,
            isMe: e.isMe
        )
    }

    let top8 = resp.entries.prefix(8).map(mapEntry)
    let meBelow: WidgetSnapshot.LeaderboardSlice.Entry?
    if let myCode = myFriendCode,
       !top8.contains(where: { $0.isMe }),
       let mine = resp.entries.first(where: { $0.friendCode == myCode })
    {
        meBelow = mapEntry(mine)
    } else {
        meBelow = nil
    }

    return WidgetSnapshot.LeaderboardSlice(entries: Array(top8), meBelow: meBelow)
}
```

- [ ] **Step 4: Запустить тесты — должны пройти**

```bash
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -only-testing:StatsAppTests/SyncCoordinatorSnapshotTests 2>&1 | tail -30
```

Ожидание: 4 теста зелёные. Если падает на `LeaderboardEntry`/`LeaderboardResponse` — это типы из `StatsApp/Network/AiuseDTO.swift`, импорт `StatsApp` в тестах уже есть через `@testable`.

- [ ] **Step 5: Прогнать весь тестовый таргет — ничего не сломалось**

```bash
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp 2>&1 | tail -20
```

Ожидание: все тесты зелёные.

- [ ] **Step 6: Commit**

```bash
git add StatsApp/Sync/SyncCoordinator.swift Tests/StatsAppTests/Sync/SyncCoordinatorSnapshotTests.swift
git commit -m "feat(sync): SyncCoordinator пишет prev-cost и leaderboard в snapshot"
```

---

## Task 4: StatsEntry и timeline provider тащат новые поля

Чтобы виджет добрался до prev-cost и leaderboard, обогащаем `StatsEntry` и `makeEntry`.

**Files:**
- Modify: `StatsWidget/StatsTimelineProvider.swift`

- [ ] **Step 1: Заменить содержимое `StatsTimelineProvider.swift`**

```swift
import WidgetKit
import Foundation

struct StatsEntry: TimelineEntry {
    let date: Date
    let period: Period
    let aiCost: Double
    let aiCostPrev: Double
    let aiTokens: Int64
    let commits: Int64
    let uniqueRepos: Int
    let topModels: [WidgetSnapshot.ModelEntry]
    let githubEnabled: Bool
    let leaderboard: WidgetSnapshot.LeaderboardSlice?
    let myFriendCode: String?
}

struct StatsTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = PeriodConfigurationIntent
    typealias Entry = StatsEntry

    func placeholder(in context: Context) -> StatsEntry {
        emptyEntry(period: .day, date: Date(), githubEnabled: true)
    }

    func snapshot(for configuration: PeriodConfigurationIntent, in context: Context) async -> StatsEntry {
        makeEntry(period: configuration.period.sharedPeriod)
    }

    func timeline(for configuration: PeriodConfigurationIntent, in context: Context) async -> Timeline<StatsEntry> {
        let entry = makeEntry(period: configuration.period.sharedPeriod)
        let next = Date().addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func makeEntry(period: Period) -> StatsEntry {
        guard let snapshot = WidgetSnapshotIO.read() else {
            return emptyEntry(period: period, date: Date(), githubEnabled: false)
        }
        let slice: WidgetSnapshot.PeriodSlice
        switch period {
        case .day: slice = snapshot.day
        case .week: slice = snapshot.week
        case .month: slice = snapshot.month
        }
        return StatsEntry(
            date: snapshot.generatedAt,
            period: period,
            aiCost: slice.aiCost,
            aiCostPrev: slice.aiCostPrev,
            aiTokens: slice.aiTokens,
            commits: slice.commits,
            uniqueRepos: slice.uniqueRepos,
            topModels: slice.topModels,
            githubEnabled: snapshot.githubEnabled,
            leaderboard: slice.leaderboard,
            myFriendCode: snapshot.myFriendCode
        )
    }

    private func emptyEntry(period: Period, date: Date, githubEnabled: Bool) -> StatsEntry {
        StatsEntry(
            date: date, period: period,
            aiCost: 0, aiCostPrev: 0, aiTokens: 0,
            commits: 0, uniqueRepos: 0, topModels: [],
            githubEnabled: githubEnabled,
            leaderboard: nil,
            myFriendCode: nil
        )
    }
}
```

- [ ] **Step 2: Проверить сборку виджет-таргета**

```bash
xcodegen generate
xcodebuild -project ai-stats.xcodeproj -scheme StatsWidget -configuration Debug build 2>&1 | tail -20
```

Ожидание: BUILD SUCCEEDED. Если падает на `WidgetSnapshot.LeaderboardSlice` not visible — `Shared/WidgetSnapshot.swift` в targets:StatsWidget, должно быть видно.

- [ ] **Step 3: Commit**

```bash
git add StatsWidget/StatsTimelineProvider.swift
git commit -m "feat(widget): StatsEntry носит aiCostPrev и leaderboard slice"
```

---

## Task 5: Локализация — добавить ключи

Виджет видит `Shared/Resources/*.lproj/Localizable.strings` через bundle (Shared включается обоим таргетам как sources). Добавляем три ключа.

**Files:**
- Modify: `Shared/Resources/en.lproj/Localizable.strings`
- Modify: `Shared/Resources/ru.lproj/Localizable.strings`

- [ ] **Step 1: Добавить ключи в `ru.lproj/Localizable.strings`**

В конец файла:

```
"section.leaderboard" = "Лидерборд";
"widget.leaderboard.no_account" = "Включи sharing в Настройках, чтобы увидеть лидерборд.";
"widget.leaderboard.empty" = "Пока никого. Добавь друзей.";
```

- [ ] **Step 2: Добавить ключи в `en.lproj/Localizable.strings`**

В конец файла:

```
"section.leaderboard" = "Leaderboard";
"widget.leaderboard.no_account" = "Enable sharing in Settings to see the leaderboard.";
"widget.leaderboard.empty" = "No friends yet.";
```

- [ ] **Step 3: Commit**

```bash
git add Shared/Resources/en.lproj/Localizable.strings Shared/Resources/ru.lproj/Localizable.strings
git commit -m "i18n(widget): ключи для секции лидерборда в Large widget"
```

---

## Task 6: LargeView, LeaderboardColumn, LeaderboardRow

Сам Large View, выделяем в отдельный файл `StatsWidget/Views/LargeView.swift`. SwiftUI-вьюхи юнит-тестами не покрываем — рендер тривиальный, форматтеры протестированы отдельно.

**Files:**
- Create: `StatsWidget/Views/LargeView.swift`
- Modify: `StatsWidget/Views/StatsWidgetView.swift`

- [ ] **Step 1: Создать `StatsWidget/Views/LargeView.swift`**

```swift
import SwiftUI
import WidgetKit

struct LargeView: View {
    let entry: StatsEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leftColumn
            Divider()
            LeaderboardColumn(slice: entry.leaderboard)
        }
        .padding(14)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryColumnWithDelta(entry: entry)

            if !entry.topModels.isEmpty {
                Text("section.top_models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.topModels.prefix(3), id: \.self) { ModelRow(model: $0) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Сводка как в Medium, но со строкой дельты под суммой.
private struct SummaryColumnWithDelta: View {
    let entry: StatsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(periodLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(String(format: "$%.2f", entry.aiCost))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            if let delta = DropdownFormat.formatCostDelta(current: entry.aiCost, previous: entry.aiCostPrev, period: entry.period) {
                HStack(spacing: 4) {
                    Text(delta.arrow + " " + delta.amount)
                        .foregroundStyle(delta.direction == .up ? .green : .red)
                    Text(NSLocalizedString(delta.labelKey, comment: ""))
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(DropdownFormat.tokens(entry.aiTokens)) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.githubEnabled {
                    Text(commitsText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var periodLabel: LocalizedStringKey {
        switch entry.period {
        case .day: return "period.day"
        case .week: return "period.week"
        case .month: return "period.month"
        }
    }

    private var commitsText: String {
        let n = entry.commits
        let suffix = NSLocalizedString("widget.commits_suffix", comment: "")
        return "\(n) \(suffix)"
    }
}

// MARK: - Leaderboard

struct LeaderboardColumn: View {
    let slice: WidgetSnapshot.LeaderboardSlice?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("section.leaderboard")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if let slice {
            if slice.entries.isEmpty {
                Text("widget.leaderboard.empty")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(slice.entries, id: \.rank) { LeaderboardRow(entry: $0) }
                    if let me = slice.meBelow {
                        Text("⋯").font(.caption2).foregroundStyle(.secondary)
                        LeaderboardRow(entry: me)
                    }
                }
            }
        } else {
            Text("widget.leaderboard.no_account")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct LeaderboardRow: View {
    let entry: WidgetSnapshot.LeaderboardSlice.Entry

    var body: some View {
        HStack(spacing: 4) {
            Text("\(entry.rank).")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)

            rankDelta
                .frame(width: 30, alignment: .leading)

            Text(entry.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Text(DropdownFormat.tokens(entry.tokensTotal))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
        .background(entry.isMe ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private var rankDelta: some View {
        if let content = DropdownFormat.formatRankDelta(current: entry.rank, previous: entry.previousRank) {
            switch content.kind {
            case .new:
                Text(NSLocalizedString("delta.new", comment: ""))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            case .change(let magnitude, let direction):
                Text("\(direction == .up ? "▲" : "▼")\(magnitude)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(direction == .up ? .green : .red)
            }
        } else {
            Text(" ").font(.system(.caption2, design: .monospaced))
        }
    }
}
```

- [ ] **Step 2: Подключить `LargeView` в `StatsWidgetView.swift`**

В `StatsWidget/Views/StatsWidgetView.swift` поменять switch:

```swift
var body: some View {
    switch family {
    case .systemSmall: SmallView(entry: entry)
    case .systemMedium: MediumView(entry: entry)
    case .systemLarge: LargeView(entry: entry)
    default: SmallView(entry: entry)
    }
}
```

- [ ] **Step 3: Сделать `ModelRow` доступным для LargeView**

Сейчас `ModelRow` объявлен как `private struct ModelRow` (см. строка 113 в `StatsWidgetView.swift`). LargeView из соседнего файла его не увидит. Убрать `private` — становится internal в том же модуле:

```swift
struct ModelRow: View {
    let model: WidgetSnapshot.ModelEntry
    // тело без изменений
}
```

`SummaryColumn` LargeView не использует — внутри `LargeView.swift` объявлен приватный `SummaryColumnWithDelta` со своей расширенной вёрсткой (сводка + строка дельты).

- [ ] **Step 4: Сборка**

```bash
xcodegen generate
xcodebuild -project ai-stats.xcodeproj -scheme StatsWidget -configuration Debug build 2>&1 | tail -20
```

Ожидание: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add StatsWidget/Views/LargeView.swift StatsWidget/Views/StatsWidgetView.swift
git commit -m "feat(widget): LargeView — сводка слева, лидерборд справа"
```

---

## Task 7: Зарегистрировать `.systemLarge`

**Files:**
- Modify: `StatsWidget/StatsWidget.swift`

- [ ] **Step 1: Добавить `.systemLarge` в `supportedFamilies`**

Заменить блок `.supportedFamilies(...)` в `StatsWidget.swift`:

```swift
.supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
```

- [ ] **Step 2: Сборка**

```bash
xcodegen generate
xcodebuild -project ai-stats.xcodeproj -scheme StatsWidget -configuration Debug build 2>&1 | tail -20
```

Ожидание: BUILD SUCCEEDED.

- [ ] **Step 3: Прогнать полный тестовый таргет**

```bash
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp 2>&1 | tail -20
```

Ожидание: всё зелёное.

- [ ] **Step 4: Commit**

```bash
git add StatsWidget/StatsWidget.swift
git commit -m "feat(widget): зарегистрировать systemLarge family"
```

---

## Task 8: Сборка релиз-конфигурации и установка

Это финальная проверка — собираем app целиком, ставим, добавляем Large виджет на десктоп, смотрим, что рендерится.

**Files:** —

- [ ] **Step 1: Релиз-сборка**

```bash
xcodegen generate
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -configuration Release -derivedDataPath build/ 2>&1 | tail -10
```

Ожидание: BUILD SUCCEEDED. Артефакт в `build/Build/Products/Release/StatsApp.app`.

- [ ] **Step 2: Установить и запустить**

```bash
killall StatsApp 2>/dev/null || true
open build/Build/Products/Release/StatsApp.app
```

Подождать ~30 секунд — sync должен пройти и записать новый snapshot.

- [ ] **Step 3: Глазами проверить виджет**

На macOS:
1. Cmd+клик на десктоп → Edit Widgets (или System Settings → Wallpaper → Edit Widgets).
2. Найти ai-stats Widget → выбрать `Large`.
3. Перетащить на десктоп.

Проверить визуально:
- Слева: период, сумма, дельта (если данные есть), tokens, commits, TOP MODELS с 3 строками.
- Справа: до 8 строк лидерборда. Если есть аккаунт и я не в топ-8 — после `⋯` строка с моим рангом.
- Моя строка визуально подсвечена.

Edge cases — переключить период в редакторе виджета:
- `day` / `week` / `month` — обе колонки меняются.
- Без аккаунта — справа «Включи sharing…».

- [ ] **Step 4: Если что-то не так — фиксим и пушим отдельный коммит**

Если визуально косяки (выровнялки, отступы, переполнение) — править `LargeView.swift`, коммитить с `fix(widget): <что фиксим>`.

---

## Task 9: Документация

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1: Добавить запись в `CHANGELOG.md`**

В блок `## [Unreleased]` (или создать, если нет) — секция `### Added`:

```markdown
### Added
- Large виджет: совмещённый экран «мои траты + лидерборд». Слева — сумма с дельтой и top-3 моделей за период, справа — топ-8 лидерборда с дельтой ранга, моя строка подсвечена. Если меня нет в топ-8 — добавляется отдельной строкой ниже.
```

- [ ] **Step 2: Обновить раздел «Что показывает» в `README.md`**

Добавить строку:

```markdown
- Large виджет на десктопе: всё то же + лидерборд друзей с дельтой ранга.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md README.md
git commit -m "docs: changelog и readme — Large widget с лидербордом"
```

---

## Сводка по тестам

| Тест-файл | Что покрывает |
|---|---|
| `Tests/StatsAppTests/WidgetSnapshotTests.swift` (новый, 3 теста) | round-trip с полным `LeaderboardSlice`, back-compat для top-level и для `PeriodSlice` |
| `Tests/StatsAppTests/Sync/SyncCoordinatorSnapshotTests.swift` (новый, 4 теста) | `aiCostPrev` берётся из второго `aiTotals`; leaderboard top-8 + meBelow; `meBelow=nil` если меня нет в кэше; `leaderboard=nil` если кэша нет |
| `Tests/StatsAppTests/UI/CostDeltaTests.swift` (существующий) | переиспользуем — `DropdownFormat.formatCostDelta` теперь в Shared, но `@testable import StatsApp` всё видит |
| `Tests/StatsAppTests/UI/RankDeltaTests.swift` (существующий) | переиспользуем |

SwiftUI-вьюхи `LargeView`/`LeaderboardColumn`/`LeaderboardRow` юнитами не покрываем — рендер тривиален, вся логика отображения вынесена в форматтеры.

## Риски и заметки

- **Side effect от тестов на снапшот.** `SyncCoordinatorSnapshotTests` через `runOnce` → `buildAndWriteWidgetSnapshot` → `WidgetSnapshotIO.write` пишет в `~/Library/Containers/com.sergeytovarov.aistats.widget/...` на машине разработчика/CI. Это уже так у существующих тестов (если они вообще запускают `buildAndWriteWidgetSnapshot`). Если на CI это даст false positive из-за остатков предыдущего прогона — добавить `setUp { try? FileManager.default.removeItem(at: WidgetSnapshotIO.writeURL) }` в новом тестовом классе. Не делаем превентивно.

- **Sandbox у виджета.** Виджет читает `~/Library/Application Support/ai-stats/snapshot.json` в **своём** контейнере (sandboxed). App пишет туда **снаружи** sandbox'а через `WidgetSnapshotIO.writeURL`. Эта развязка уже работает в Medium/Small, для Large ничего нового не нужно.

- **Локализация и виджет-bundle.** Виджет использует `NSLocalizedString` — резолвит из своего bundle. `Shared/Resources/*.lproj` входит в обоих таргетов через `path: Shared` в `project.yml`, xcodegen раскатает `.strings` файлы в виджет-bundle. Если ключи `widget.leaderboard.*` не зарезолвятся (виден ключ как строка) — проверить, что `Shared/Resources` действительно копируется в виджет-bundle через `xcodebuild -showBuildSettings -target StatsWidget | grep LOCALIZED`.

- **Очень тонкий сценарий:** sharing enabled, но друзей 0 и меня одного нет в выдаче (бэк отдаёт пустой массив). `entries.isEmpty` → empty state. ОК.
