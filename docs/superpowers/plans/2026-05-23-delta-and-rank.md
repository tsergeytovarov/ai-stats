# Delta для трат и дельта ранга — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Под большой цифрой трат показывать дельту vs предыдущий период (день/неделя/месяц); в каждой строке лидерборда показывать сдвиг позиции (▲/▼/NEW).

**Architecture:** Дельта трат считается на клиенте — второй вызов `StatsQueries.aiTotals` для непересекающегося предыдущего окна, форматтер в момент рендера. Дельта ранга приходит с сервера (`previous_rank: int | null` в каждой `LeaderboardEntry`), клиент только форматирует. Два чистых форматтера (`formatCostDelta`, `formatRankDelta`) тестируются юнитами; SwiftUI-вьюхи — тонкие обёртки над ними. GitHub-секцию не трогаем.

**Tech Stack:** Swift 5.10, SwiftUI, GRDB, XCTest.

**Spec:** [docs/superpowers/specs/2026-05-23-delta-and-rank-design.md](../specs/2026-05-23-delta-and-rank-design.md)

---

## File Structure

**Create:**
- `Tests/StatsAppTests/UI/CostDeltaTests.swift` — юниты на форматтер трат
- `Tests/StatsAppTests/UI/RankDeltaTests.swift` — юниты на форматтер ранга

**Modify:**
- `Shared/Util/DateUtils.swift` — добавить `previousPeriodDays(endingAt:lookback:)`
- `Tests/StatsAppTests/DateUtilsTests.swift` — тесты на `previousPeriodDays`
- `StatsApp/Network/AiuseDTO.swift` — добавить `previousRank: Int?` в `LeaderboardEntry`
- `Tests/StatsAppTests/Network/AiuseAPIClientTests.swift` — тесты декодинга `previous_rank`
- `StatsApp/Status/DropdownViewModel.swift` — `@Published var aiTotalsPrev`, второй вызов `aiTotals` в `reload()`
- `StatsApp/Status/DropdownSections.swift` — `formatCostDelta`, `formatRankDelta`, `CostDelta` View, `RankDelta` View; интеграция в `DropdownAISection` и `DropdownLeaderboardSection`
- `Shared/Resources/ru.lproj/Localizable.strings` — `delta.vs_yesterday`, `delta.vs_prev_week`, `delta.vs_prev_month`, `delta.new`
- `Shared/Resources/en.lproj/Localizable.strings` — те же ключи
- `CHANGELOG.md` — запись в `## [Unreleased]`

---

## Task 1: `DateUtils.previousPeriodDays` (TDD)

**Files:**
- Modify: `Shared/Util/DateUtils.swift`
- Test: `Tests/StatsAppTests/DateUtilsTests.swift`

- [ ] **Step 1: Write failing tests**

Добавить в конец класса `DateUtilsTests` в `Tests/StatsAppTests/DateUtilsTests.swift`:

```swift
    // MARK: - previousPeriodDays

    /// Якорь — 2024-05-22 12:00 UTC. В любой разумной TZ это всё ещё 2024-05-22.
    private var anchor: Date { Date(timeIntervalSince1970: 1716379200) }

    func test_previousPeriodDays_day_returns_yesterday() {
        let result = DateUtils.previousPeriodDays(endingAt: anchor, lookback: 0)
        XCTAssertEqual(result, ["2024-05-21"])
    }

    func test_previousPeriodDays_week_returns_seven_prior_days() {
        let result = DateUtils.previousPeriodDays(endingAt: anchor, lookback: 6)
        XCTAssertEqual(result.count, 7)
        XCTAssertEqual(result.first, "2024-05-09")
        XCTAssertEqual(result.last, "2024-05-15")
    }

    func test_previousPeriodDays_month_returns_thirty_prior_days() {
        let result = DateUtils.previousPeriodDays(endingAt: anchor, lookback: 29)
        XCTAssertEqual(result.count, 30)
        XCTAssertEqual(result.first, "2024-03-24")
        XCTAssertEqual(result.last, "2024-04-22")
    }

    /// Окна не пересекаются и стыкуются встык с current.
    func test_previousPeriodDays_does_not_overlap_with_current_range() {
        for lookback in [0, 6, 29] {
            let current = DateUtils.daysRange(endingAt: anchor, lookback: lookback)
            let previous = DateUtils.previousPeriodDays(endingAt: anchor, lookback: lookback)
            XCTAssertEqual(current.count, previous.count, "lookback=\(lookback): длины должны совпадать")
            XCTAssertTrue(Set(current).isDisjoint(with: Set(previous)), "lookback=\(lookback): окна не должны пересекаться")
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd /Users/sergeytovarov/work/ai-stats
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' test \
    -only-testing:StatsAppTests/DateUtilsTests 2>&1 | tail -30
```
Expected: компиляция падает с «Type 'DateUtils' has no member 'previousPeriodDays'».

- [ ] **Step 3: Implement `previousPeriodDays`**

Добавить в `Shared/Util/DateUtils.swift` (после `daysRange`):

```swift
    /// Возвращает `lookback + 1` ISO-дней для окна, непосредственно предшествующего
    /// `daysRange(endingAt: end, lookback: lookback)` — той же длины.
    /// lookback=0 → [yesterday]
    /// lookback=6 → 7 дней, [end-13 ... end-7]
    /// lookback=29 → 30 дней, [end-59 ... end-30]
    static func previousPeriodDays(endingAt end: Date, lookback: Int) -> [String] {
        let cal = Calendar(identifier: .gregorian)
        guard let prevEnd = cal.date(byAdding: .day, value: -(lookback + 1), to: end) else { return [] }
        return daysRange(endingAt: prevEnd, lookback: lookback)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' test \
    -only-testing:StatsAppTests/DateUtilsTests 2>&1 | tail -20
```
Expected: 4 новых теста PASS, все старые DateUtilsTests тоже PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/Util/DateUtils.swift Tests/StatsAppTests/DateUtilsTests.swift
git commit -m "feat(util): добавить DateUtils.previousPeriodDays для дельты по периодам"
```

- [ ] **Step 6: Закрепить контракт `aiTotals` для непересекающихся диапазонов**

Дельта трат полагается на то, что два независимых вызова `aiTotals` с непересекающимися `days:` дают независимые суммы. Фиксируем тестом в `Tests/StatsAppTests/StatsQueriesTests.swift` — добавить в конец класса:

```swift
    /// Контракт для дельты по периодам: два вызова с непересекающимися диапазонами
    /// возвращают независимые суммы — нет общего стейта между вызовами.
    func test_aiTotals_disjointDayRanges_giveIndependentSums() throws {
        let current = try dbq.read { db in
            try StatsQueries.aiTotals(in: db, days: ["2024-05-22"])
        }
        let previous = try dbq.read { db in
            try StatsQueries.aiTotals(in: db, days: ["2024-05-20"])
        }
        XCTAssertEqual(current.totalCost, 5.0)   // 2.0 (claude) + 3.0 (codex)
        XCTAssertEqual(previous.totalCost, 1.5)  // 1.5 (claude)
    }
```

- [ ] **Step 7: Run StatsQueriesTests**

Run:
```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' test \
    -only-testing:StatsAppTests/StatsQueriesTests 2>&1 | tail -10
```
Expected: новый тест PASS, существующие PASS.

- [ ] **Step 8: Commit**

```bash
git add Tests/StatsAppTests/StatsQueriesTests.swift
git commit -m "test(queries): зафиксировать контракт aiTotals для непересекающихся диапазонов"
```

---

## Task 2: `LeaderboardEntry.previousRank` в DTO (TDD)

**Files:**
- Modify: `StatsApp/Network/AiuseDTO.swift:125-141`
- Test: `Tests/StatsAppTests/Network/AiuseAPIClientTests.swift`

- [ ] **Step 1: Write failing tests**

Добавить в конец класса `AiuseAPIClientTests`:

```swift
    // MARK: - leaderboard previous_rank

    func testGetLeaderboard_decodes_previousRank_when_present() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/leaderboard?period=week")!,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = """
            {
              "period": "week",
              "as_of": "2024-05-22T12:00:00Z",
              "entries": [
                {"friend_code":"AAA","display_name":"Сергей","rank":1,"previous_rank":3,"tokens_total":12000,"is_me":false},
                {"friend_code":"BBB","display_name":"Я","rank":2,"previous_rank":null,"tokens_total":8000,"is_me":true}
              ]
            }
            """
            return (resp, json.data(using: .utf8)!)
        }
        let resp = try await client.getLeaderboard(period: "week")
        XCTAssertEqual(resp.entries[0].previousRank, 3)
        XCTAssertNil(resp.entries[1].previousRank)
    }

    func testGetLeaderboard_decodes_previousRank_as_nil_when_field_missing() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/leaderboard?period=day")!,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            // Без previous_rank — старый формат бэкенда, до раскатки.
            let json = """
            {
              "period": "day",
              "as_of": "2024-05-22T12:00:00Z",
              "entries": [
                {"friend_code":"AAA","display_name":"Сергей","rank":1,"tokens_total":100,"is_me":false}
              ]
            }
            """
            return (resp, json.data(using: .utf8)!)
        }
        let resp = try await client.getLeaderboard(period: "day")
        XCTAssertNil(resp.entries[0].previousRank)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' test \
    -only-testing:StatsAppTests/AiuseAPIClientTests 2>&1 | tail -20
```
Expected: компиляция падает с «Value of type 'LeaderboardEntry' has no member 'previousRank'».

- [ ] **Step 3: Add `previousRank` to DTO**

В `StatsApp/Network/AiuseDTO.swift` заменить блок `LeaderboardEntry` (строки 125-141) на:

```swift
struct LeaderboardEntry: Codable, Identifiable, Equatable {
    let friendCode: String
    let displayName: String
    let rank: Int
    let previousRank: Int?
    let tokensTotal: Int64
    let isMe: Bool

    var id: String { friendCode }

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case displayName = "display_name"
        case rank
        case previousRank = "previous_rank"
        case tokensTotal = "tokens_total"
        case isMe = "is_me"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' test \
    -only-testing:StatsAppTests/AiuseAPIClientTests 2>&1 | tail -20
```
Expected: 2 новых теста PASS. Все существующие `AiuseAPIClientTests` тоже PASS (старые ответы без `previous_rank` теперь декодятся как `nil`).

- [ ] **Step 5: Commit**

```bash
git add StatsApp/Network/AiuseDTO.swift Tests/StatsAppTests/Network/AiuseAPIClientTests.swift
git commit -m "feat(api): добавить previous_rank в LeaderboardEntry DTO"
```

---

## Task 3: `formatCostDelta` форматтер (TDD)

**Files:**
- Modify: `StatsApp/Status/DropdownSections.swift` (добавить в начало, рядом с `DropdownFormat`)
- Test: `Tests/StatsAppTests/UI/CostDeltaTests.swift` (новый файл)

- [ ] **Step 1: Создать директорию для UI-тестов**

```bash
mkdir -p /Users/sergeytovarov/work/ai-stats/Tests/StatsAppTests/UI
```

- [ ] **Step 2: Write failing tests**

Создать `Tests/StatsAppTests/UI/CostDeltaTests.swift`:

```swift
import XCTest
@testable import StatsApp

final class CostDeltaTests: XCTestCase {
    func test_currentGreaterThanPrevious_isUp_withPlusSign() {
        let result = DropdownFormat.formatCostDelta(current: 250.0, previous: 222.40, period: .day)
        XCTAssertEqual(result?.arrow, "▲")
        XCTAssertEqual(result?.amount, "+$27.60")
        XCTAssertEqual(result?.direction, .up)
        XCTAssertEqual(result?.labelKey, "delta.vs_yesterday")
    }

    func test_currentLessThanPrevious_isDown_withMinusSign() {
        let result = DropdownFormat.formatCostDelta(current: 200.0, previous: 250.0, period: .week)
        XCTAssertEqual(result?.arrow, "▼")
        XCTAssertEqual(result?.amount, "−$50.00")
        XCTAssertEqual(result?.direction, .down)
        XCTAssertEqual(result?.labelKey, "delta.vs_prev_week")
    }

    func test_currentZero_returnsNil() {
        let result = DropdownFormat.formatCostDelta(current: 0, previous: 30.0, period: .day)
        XCTAssertNil(result)
    }

    func test_equal_returnsNil() {
        let result = DropdownFormat.formatCostDelta(current: 30.0, previous: 30.0, period: .month)
        XCTAssertNil(result)
    }

    func test_previousZero_currentPositive_isUp() {
        let result = DropdownFormat.formatCostDelta(current: 10.0, previous: 0, period: .day)
        XCTAssertEqual(result?.arrow, "▲")
        XCTAssertEqual(result?.amount, "+$10.00")
        XCTAssertEqual(result?.direction, .up)
    }

    func test_monthPeriod_labelKey() {
        let result = DropdownFormat.formatCostDelta(current: 100.0, previous: 50.0, period: .month)
        XCTAssertEqual(result?.labelKey, "delta.vs_prev_month")
    }
}
```

- [ ] **Step 3: Add test file to xcodeproj**

Открыть `project.yml` (XcodeGen), убедиться, что `Tests/StatsAppTests` сканируется рекурсивно (директория `UI/` подхватится автоматически). Затем регенерировать:

```bash
cd /Users/sergeytovarov/work/ai-stats
xcodegen generate 2>&1 | tail -5
```

Expected: «Generated project successfully».

- [ ] **Step 4: Run tests to verify they fail**

Run:
```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' test \
    -only-testing:StatsAppTests/CostDeltaTests 2>&1 | tail -20
```
Expected: компиляция падает с «Type 'DropdownFormat' has no member 'formatCostDelta'».

- [ ] **Step 5: Implement `formatCostDelta`**

В `StatsApp/Status/DropdownSections.swift` добавить **в начало файла, перед `enum DropdownFormat`**:

```swift
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
```

В `enum DropdownFormat` добавить (в конец, перед закрывающей `}`):

```swift
    static func formatCostDelta(current: Double, previous: Double, period: Period) -> CostDeltaContent? {
        guard current > 0, current != previous else { return nil }
        let diff = current - previous
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
```

- [ ] **Step 6: Run tests to verify they pass**

Run:
```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' test \
    -only-testing:StatsAppTests/CostDeltaTests 2>&1 | tail -15
```
Expected: 6 тестов PASS.

- [ ] **Step 7: Commit**

```bash
git add StatsApp/Status/DropdownSections.swift Tests/StatsAppTests/UI/CostDeltaTests.swift ai-stats.xcodeproj
git commit -m "feat(ui): formatCostDelta — форматтер дельты трат vs предыдущий период"
```

---

## Task 4: `formatRankDelta` форматтер (TDD)

**Files:**
- Modify: `StatsApp/Status/DropdownSections.swift` (добавить функцию в `DropdownFormat`)
- Test: `Tests/StatsAppTests/UI/RankDeltaTests.swift` (новый файл)

- [ ] **Step 1: Write failing tests**

Создать `Tests/StatsAppTests/UI/RankDeltaTests.swift`:

```swift
import XCTest
@testable import StatsApp

final class RankDeltaTests: XCTestCase {
    func test_climbedUp_isUpWithMagnitude() {
        // Был #11, стал #1 — поднялся на 10 позиций.
        let result = DropdownFormat.formatRankDelta(current: 1, previous: 11)
        XCTAssertEqual(result?.kind, .change(magnitude: 10, direction: .up))
    }

    func test_fellDown_isDownWithMagnitude() {
        // Был #2, стал #5 — опустился на 3 позиции.
        let result = DropdownFormat.formatRankDelta(current: 5, previous: 2)
        XCTAssertEqual(result?.kind, .change(magnitude: 3, direction: .down))
    }

    func test_previousNil_isNew() {
        let result = DropdownFormat.formatRankDelta(current: 7, previous: nil)
        XCTAssertEqual(result?.kind, .new)
    }

    func test_sameRank_returnsNil() {
        let result = DropdownFormat.formatRankDelta(current: 3, previous: 3)
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Regenerate xcodeproj**

```bash
cd /Users/sergeytovarov/work/ai-stats
xcodegen generate 2>&1 | tail -3
```

- [ ] **Step 3: Run tests to verify they fail**

Run:
```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' test \
    -only-testing:StatsAppTests/RankDeltaTests 2>&1 | tail -15
```
Expected: компиляция падает с «Type 'DropdownFormat' has no member 'formatRankDelta'».

- [ ] **Step 4: Implement `formatRankDelta`**

В `StatsApp/Status/DropdownSections.swift`, в `enum DropdownFormat`, добавить после `formatCostDelta`:

```swift
    static func formatRankDelta(current: Int, previous: Int?) -> RankDeltaContent? {
        guard let previous else {
            return RankDeltaContent(kind: .new)
        }
        let diff = previous - current   // подъём в рейтинге = current уменьшился = diff положительный
        guard diff != 0 else { return nil }
        let direction: DeltaDirection = diff > 0 ? .up : .down
        return RankDeltaContent(kind: .change(magnitude: abs(diff), direction: direction))
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' test \
    -only-testing:StatsAppTests/RankDeltaTests 2>&1 | tail -15
```
Expected: 4 теста PASS.

- [ ] **Step 6: Commit**

```bash
git add StatsApp/Status/DropdownSections.swift Tests/StatsAppTests/UI/RankDeltaTests.swift ai-stats.xcodeproj
git commit -m "feat(ui): formatRankDelta — форматтер сдвига позиции в лидерборде"
```

---

## Task 5: Wire `aiTotalsPrev` в `DropdownViewModel`

**Files:**
- Modify: `StatsApp/Status/DropdownViewModel.swift`

Этот таск — pipeline-изменение поверх уже протестированного `DateUtils.previousPeriodDays`. Без отдельного TDD (нет существующих VM-тестов, моки `MainActor`-VM с GRDB.DatabaseReader избыточны для одного нового вызова). Проверяем существующими тестами на компиляцию + smoke-сборкой.

- [ ] **Step 1: Добавить `@Published var aiTotalsPrev`**

В `StatsApp/Status/DropdownViewModel.swift` после строки `@Published var aiTotals: AITotals = ...` (около строки 48) добавить:

```swift
    @Published var aiTotalsPrev: AITotals = .init(totalCost: 0, totalInputTokens: 0, totalOutputTokens: 0)
```

- [ ] **Step 2: Расширить `reload()` для запроса prev-окна**

Заменить тело метода `reload()` (строки ~76–105) на:

```swift
    func reload() async {
        let now = Date()
        let periodDays = DateUtils.daysRange(endingAt: now, lookback: period.lookbackDays)
        let prevPeriodDays = DateUtils.previousPeriodDays(endingAt: now, lookback: period.lookbackDays)
        let sparkDays = DateUtils.daysRange(endingAt: now, lookback: 29)

        do {
            let snapshot = try await db.read { db -> (AITotals, AITotals, [SourceTotal], [ModelTotal], GitHubTotals, GitHubLOC, [RepoTotal], [Double], [Double]) in
                let totals = try StatsQueries.aiTotals(in: db, days: periodDays)
                let totalsPrev = try StatsQueries.aiTotals(in: db, days: prevPeriodDays)
                let bySource = try StatsQueries.aiTotalsBySource(in: db, days: periodDays)
                let models = try StatsQueries.topModels(in: db, days: periodDays, limit: 5)
                let gh = try StatsQueries.githubTotals(in: db, days: periodDays)
                let loc = try StatsQueries.githubLOC(in: db, days: periodDays)
                let repos = try StatsQueries.topRepos(in: db, days: periodDays, limit: 5)
                let costSeries = try StatsQueries.dailyAICostSeries(in: db, days: sparkDays)
                let addsSeries = try StatsQueries.dailyAdditionsSeries(in: db, days: sparkDays)
                return (totals, totalsPrev, bySource, models, gh, loc, repos, costSeries, addsSeries)
            }
            self.aiTotals = snapshot.0
            self.aiTotalsPrev = snapshot.1
            self.bySource = snapshot.2
            self.topModels = snapshot.3
            self.githubTotals = snapshot.4
            self.loc = snapshot.5
            self.topRepos = snapshot.6
            self.sparklineSeries = snapshot.7
            self.additionsSeries = snapshot.8
            self.lastSyncDescription = relativeDescription(for: syncCoordinator?.lastSyncAt.values.max())
        } catch {
            NSLog("ai-stats reload error: \(error)")
        }
    }
```

- [ ] **Step 3: Build & run full test suite**

Run:
```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' test 2>&1 | tail -30
```
Expected: BUILD SUCCEEDED, все тесты (включая ранее добавленные DateUtils/Cost/Rank) PASS.

- [ ] **Step 4: Commit**

```bash
git add StatsApp/Status/DropdownViewModel.swift
git commit -m "feat(ui): aiTotalsPrev в DropdownViewModel — данные за прошлый период"
```

---

## Task 6: Localization keys

**Files:**
- Modify: `Shared/Resources/ru.lproj/Localizable.strings`
- Modify: `Shared/Resources/en.lproj/Localizable.strings`

- [ ] **Step 1: Добавить русские ключи**

В конец `Shared/Resources/ru.lproj/Localizable.strings` добавить:

```
"delta.vs_yesterday" = "vs вчера";
"delta.vs_prev_week" = "vs прошлой недели";
"delta.vs_prev_month" = "vs прошлого месяца";
"delta.new" = "NEW";
```

- [ ] **Step 2: Добавить английские ключи**

В конец `Shared/Resources/en.lproj/Localizable.strings` добавить:

```
"delta.vs_yesterday" = "vs yesterday";
"delta.vs_prev_week" = "vs last week";
"delta.vs_prev_month" = "vs last month";
"delta.new" = "NEW";
```

- [ ] **Step 3: Verify resources compile**

Run:
```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED, никаких warning'ов про `.strings`.

- [ ] **Step 4: Commit**

```bash
git add Shared/Resources/ru.lproj/Localizable.strings Shared/Resources/en.lproj/Localizable.strings
git commit -m "i18n: ключи для дельты периода и NEW в лидерборде (ru, en)"
```

---

## Task 7: `CostDelta` и `RankDelta` SwiftUI views + интеграция

**Files:**
- Modify: `StatsApp/Status/DropdownSections.swift`

- [ ] **Step 1: Добавить SwiftUI-вьюхи**

В `StatsApp/Status/DropdownSections.swift`, **после блока `enum DropdownFormat { ... }`** и **перед `// MARK: - AI section`**, добавить:

```swift
// MARK: - delta views

private extension DeltaDirection {
    var color: Color {
        switch self {
        case .up:   return .green
        case .down: return .red
        }
    }
}

struct CostDelta: View {
    let current: Double
    let previous: Double
    let period: Period

    var body: some View {
        if let content = DropdownFormat.formatCostDelta(current: current, previous: previous, period: period) {
            HStack(spacing: 4) {
                Text(content.arrow + " " + content.amount)
                    .foregroundStyle(content.direction.color)
                Text(NSLocalizedString(content.labelKey, comment: ""))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }
}

struct RankDelta: View {
    let current: Int
    let previous: Int?

    var body: some View {
        Group {
            if let content = DropdownFormat.formatRankDelta(current: current, previous: previous) {
                switch content.kind {
                case .new:
                    Text(NSLocalizedString("delta.new", comment: ""))
                        .foregroundStyle(.secondary)
                case .change(let magnitude, let direction):
                    let arrow = direction == .up ? "▲" : "▼"
                    Text("\(arrow)\(magnitude)")
                        .foregroundStyle(direction.color)
                }
            } else {
                Text(" ")   // зарезервировать место, чтобы аватарки не прыгали
            }
        }
        .font(.system(.caption, design: .monospaced))
        .frame(width: 32, alignment: .leading)
    }
}
```

- [ ] **Step 2: Интегрировать `CostDelta` в `DropdownAISection`**

В `DropdownSections.swift`, в `DropdownAISection.body`, заменить блок (около строк 33–40):

```swift
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "$%.2f", viewModel.aiTotals.totalCost))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(DropdownFormat.tokens(viewModel.aiTotals.totalInputTokens + viewModel.aiTotals.totalOutputTokens) + " tokens")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
```

на:

```swift
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "$%.2f", viewModel.aiTotals.totalCost))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                CostDelta(
                    current: viewModel.aiTotals.totalCost,
                    previous: viewModel.aiTotalsPrev.totalCost,
                    period: viewModel.period
                )
                Text(DropdownFormat.tokens(viewModel.aiTotals.totalInputTokens + viewModel.aiTotals.totalOutputTokens) + " tokens")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
```

- [ ] **Step 3: Интегрировать `RankDelta` в `DropdownLeaderboardSection`**

В том же файле, в `DropdownLeaderboardSection.body`, заменить строку (около строки 170–183) внутри `ForEach`:

```swift
                    ForEach(viewModel.leaderboard) { entry in
                        HStack(spacing: 10) {
                            Text("\(entry.rank).")
                                .frame(width: 22, alignment: .trailing)
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                            AvatarView(data: viewModel.friendAvatars[entry.friendCode], size: 28)
                            Text(entry.isMe ? "Я" : entry.displayName)
                                .fontWeight(entry.isMe ? .semibold : .regular)
                            Spacer()
                            Text(DropdownFormat.tokens(entry.tokensTotal) + " tok")
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
```

на:

```swift
                    ForEach(viewModel.leaderboard) { entry in
                        HStack(spacing: 10) {
                            Text("\(entry.rank).")
                                .frame(width: 22, alignment: .trailing)
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                            RankDelta(current: entry.rank, previous: entry.previousRank)
                            AvatarView(data: viewModel.friendAvatars[entry.friendCode], size: 28)
                            Text(entry.isMe ? "Я" : entry.displayName)
                                .fontWeight(entry.isMe ? .semibold : .regular)
                            Spacer()
                            Text(DropdownFormat.tokens(entry.tokensTotal) + " tok")
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
```

- [ ] **Step 4: Build + full test run**

Run:
```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED, все тесты PASS.

- [ ] **Step 5: Smoke-проверка в реальном app**

Run:
```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
open build/Debug/StatsApp.app
```

Проверить руками:
- Открыть menu bar dropdown → AI секция: под крупной цифрой `$X.XX` появилась строка `▲ +$… vs вчера` (зелёная) или `▼ −$… vs вчера` (красная). При смене period — лейбл меняется.
- Лидерборд: рядом с номером ранга есть `▲N` (зелёная), `▼N` (красная), `NEW` (серая) или пусто. Колонка с аватарками не дёргается между строками.
- Если данных за прошлый период нет (свежая БД) — дельта трат отсутствует, в лидерборде везде `NEW` (пока бэк не отдаёт `previous_rank`).

- [ ] **Step 6: Commit**

```bash
git add StatsApp/Status/DropdownSections.swift
git commit -m "feat(ui): CostDelta и RankDelta — показываем динамику в дропдауне"
```

---

## Task 8: CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Добавить запись в Unreleased**

В `CHANGELOG.md`, в раздел `## [Unreleased]`, в начало добавить новый блок:

```markdown
### UI — динамика в дропдауне
- AI-секция: под крупной цифрой трат показывается дельта vs предыдущий период (день → вчера, неделя → прошлая неделя, месяц → прошлый месяц). Зелёный — больше потратил, красный — меньше.
- Лидерборд: рядом с рангом каждой строки — стрелка `▲N` (поднялся в рейтинге, зелёный) / `▼N` (опустился, красный) / `NEW` (не было в прошлом периоде).
- Серверный контракт: `/api/leaderboard` отдаёт `previous_rank: int | null` в каждой entry. Пока бэк не раскатан — клиент тихо показывает `NEW` всем, не ломается.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): дельта трат и сдвиг позиции в лидерборде"
```

---

## Done criteria

- Все 8 тасков closed, коммиты на месте.
- `xcodebuild test` зелёный.
- В дропдауне визуально видна дельта трат и стрелки в лидерборде.
- CHANGELOG обновлён.
- Бэкенд `aiuse` — отдельный таск в другом репо. После его раскатки `previous_rank` начнёт приходить с реальными значениями, клиент менять не надо.
