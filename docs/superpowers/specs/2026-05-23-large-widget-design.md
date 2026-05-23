# Large widget — мои траты + лидерборд

**Дата:** 2026-05-23
**Статус:** Design approved
**Скоуп:** `StatsWidget` + `Shared` + `SyncCoordinator` в `StatsApp`
**Зависит от:** ветка `feat/delta-and-rank` (форматтеры дельт)

## Зачем

Сейчас виджет умеет только `.systemSmall` и `.systemMedium`. На большом виджете (`.systemLarge`, ~360×360pt) места достаточно, чтобы показать одновременно:

- слева — мои траты за выбранный период (как Medium, плюс топ-моделей),
- справа — лидерборд друзей за тот же период.

Это тот же набор данных, что уже виден в menu bar dropdown, но всегда на десктопе — без клика по статус-айкону.

## Решения

| Вопрос | Решение |
|---|---|
| Период | Уважает существующий `PeriodConfigurationIntent` (day / week / month). Левая и правая колонки используют один и тот же период. |
| Layout | Две колонки с делителем по центру. Слева сверху сводка, снизу `TOP MODELS`. Справа — список лидерборда. |
| Глубина лидерборда | Топ-8 строк. Если я не в топе — после `⋯` добавляется 9-я строка с моим рангом. |
| Дельты | Включаем обе: дельта трат под суммой слева (`▲ +$X.XX vs вчера`), дельта ранга в строках лидерборда справа (`▲N` / `▼N` / `NEW`). |
| Аватарки | Не показываем. Аватарки хранятся отдельным PNG-кэшем в DB; протаскивать их в `snapshot.json` — раздувать файл ради косметики. |

## Архитектура

```
┌───────────────────────┬─────────────────────────┐
│ DAY                   │ LEADERBOARD             │
│                       │                         │
│ $250.00               │ 1. ▲10  Серёжа   12.4k │
│ ▲ +$28.40 vs вчера    │ 2. ▼3   Вася      9.8k │
│ 12.4M tokens          │ 3. NEW  Петя      4.1k │
│ 5 commits             │ 4.      Гриша     3.0k │
│                       │ 5.      Маша      2.1k │
│ ─ TOP MODELS ─        │ 6.      Дима      1.8k │
│ opus-4-7      $180.00 │ 7.      Алиса     1.0k │
│ sonnet-4-6     $50.00 │ 8.      Лёша        500│
│ gpt-5.5        $20.00 │ ⋯ #42   я         200  │
└───────────────────────┴─────────────────────────┘
```

### Изменения по слоям

1. **`Shared/WidgetSnapshot.swift`** — расширяется `PeriodSlice` и добавляется тип `LeaderboardSlice`.
2. **`Shared/Util/`** — новый файл с чистыми форматтерами `formatCostDelta`, `formatRankDelta`, `formatTokensShort`. Используются и UI dropdown (через `CostDelta`/`RankDelta` views в `StatsApp/Status/DropdownSections.swift`, которые пишутся в рамках delta-and-rank), и LargeView виджета.
3. **`StatsApp/Sync/SyncCoordinator.swift`** — `buildAndWriteWidgetSnapshot()` дополнительно заполняет `aiCostPrev` и `leaderboard` для каждого периода.
4. **`StatsWidget/StatsWidget.swift`** — `.supportedFamilies` добавляет `.systemLarge`.
5. **`StatsWidget/StatsTimelineProvider.swift`** — `StatsEntry` обогащается полем `leaderboard: WidgetSnapshot.LeaderboardSlice?` и `aiCostPrev: Double`.
6. **`StatsWidget/Views/StatsWidgetView.swift`** — switch family добавляет ветку `.systemLarge → LargeView`. Новые приватные структуры `LargeView` и `LeaderboardRow`.

## Модель данных

### `Shared/WidgetSnapshot.swift`

```swift
struct WidgetSnapshot: Codable, Equatable {
    let generatedAt: Date
    let day: PeriodSlice
    let week: PeriodSlice
    let month: PeriodSlice
    let githubEnabled: Bool
    let myFriendCode: String?              // new, для определения «я в топе или нет»

    struct PeriodSlice: Codable, Equatable {
        let aiCost: Double
        let aiCostPrev: Double            // new
        let aiTokens: Int64
        let commits: Int64
        let uniqueRepos: Int
        let topModels: [ModelEntry]
        let leaderboard: LeaderboardSlice?  // new
    }

    struct ModelEntry: Codable, Equatable, Hashable {
        let model: String
        let source: String
        let costUsd: Double
        let inputTokens: Int64
        let outputTokens: Int64
    }

    struct LeaderboardSlice: Codable, Equatable {
        let entries: [Entry]              // <= 8
        let meExtra: Entry?               // nil, если я в top-8 или меня нет вовсе

        struct Entry: Codable, Equatable {
            let rank: Int
            let previousRank: Int?
            let displayName: String
            let tokensTotal: Int64
            let isMe: Bool
        }
    }
}
```

### Back-compat

`aiCostPrev` и `leaderboard` декодируются опционально. Между апдейтами app/widget на диске может остаться старый `snapshot.json` — новый виджет читает его без падения: `aiCostPrev = 0` (дельта скрывается по правилу), `leaderboard = nil` (правая колонка показывает empty state). Старый виджет (без поддержки Large) спокойно игнорирует новые поля при декодинге.

Реализация: использовать стандартный `Decoder` с `decodeIfPresent` для новых полей, дефолты выставлять в `init(from:)`.

## Сборка snapshot

`SyncCoordinator.makeSlice(in:days:)` расширяется так:

```swift
private static func makeSlice(
    in db: GRDB.Database,
    days: [String],
    prevDays: [String],
    leaderboardPeriod: String,
    myFriendCode: String?
) throws -> WidgetSnapshot.PeriodSlice
```

1. **`aiCostPrev`** — второй вызов `StatsQueries.aiTotals(in: prevDays)`, берём `totalCost`. `prevDays` приходит из `DateUtils.previousPeriodDays(endingAt:lookback:)` — функция уже добавляется в delta-and-rank спеке, можно переиспользовать.
2. **`leaderboard`** —
   - Читаем `StatsQueries.loadLeaderboardCache(db, period: leaderboardPeriod)` (вернёт payload_json или nil).
   - Если nil → `leaderboard = nil`.
   - Декодируем в `LeaderboardResponse`. Берём первые 8 entries как `entries`.
   - Если `myFriendCode != nil` и моей строки нет в первых 8, ищем в полном списке. Найдено → кладём в `meExtra`. Не найдено → `meExtra = nil`.
   - Маппим `LeaderboardEntry` → `LeaderboardSlice.Entry`. `isMe` берём из DTO (`is_me`).

`myFriendCode` берётся из того же провайдера, что и `LeaderboardPullSyncer.hasAccount()` (keychain/config), и сохраняется в корне `WidgetSnapshot` (см. модель данных выше). Виджет в keychain не лезет — читает только `snapshot.json`.

### Mapping периодов

| Widget period | leaderboard period |
|---|---|
| `.day` | `"day"` |
| `.week` | `"week"` |
| `.month` | `"month"` |

`24h` из API не используем — для виджета это шум.

## UI

### LargeView (псевдокод)

```swift
struct LargeView: View {
    let entry: StatsEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SummaryColumn(entry: entry)
                if !entry.topModels.isEmpty {
                    Divider()
                    Text("section.top_models").font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                    ForEach(entry.topModels.prefix(3), id: \.self) { ModelRow(model: $0) }
                }
            }
            Divider()
            LeaderboardColumn(slice: entry.leaderboard)
        }
        .padding(14)
    }
}
```

`SummaryColumn` дополняется опциональной строкой дельты под `Text("$%.2f", entry.aiCost)`. Логика рендера дельты — тот же `formatCostDelta(current:previous:period:)`, что и в dropdown. Если функция возвращает `nil` — строка не показывается.

### LeaderboardColumn

```swift
struct LeaderboardColumn: View {
    let slice: WidgetSnapshot.LeaderboardSlice?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("section.leaderboard").font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
            switch state {
            case .noAccount:
                Text("widget.leaderboard.no_account").font(.caption2).foregroundStyle(.secondary)
            case .empty:
                Text("widget.leaderboard.empty").font(.caption2).foregroundStyle(.secondary)
            case .rows(let entries, let meExtra):
                ForEach(entries, id: \.rank) { LeaderboardRow(entry: $0) }
                if let me = meExtra {
                    Text("⋯").font(.caption2).foregroundStyle(.secondary)
                    LeaderboardRow(entry: me)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private enum State { case noAccount, empty, rows([...], Entry?) }
    private var state: State { /* slice == nil → noAccount; entries empty → empty; else rows */ }
}
```

### LeaderboardRow

Три зоны: ранг (фикс. ширина), дельта ранга (фикс. ширина 3 символа под `▲99`), имя (truncating tail), токены (моноспейс).

```
1. ▲10  Серёжа              12.4k
```

`isMe == true` → фон строки получает `Color.accentColor.opacity(0.15)` или аналог subtle highlight. Без эмодзи, без жирного — глаз итак цепляется.

### Состояния (резюме)

| Состояние | Левая колонка | Правая колонка |
|---|---|---|
| Нет snapshot.json | стандартный fallback | — |
| `aiCost == 0` | сумма `$0.00`, дельта скрыта | как обычно |
| `topModels.isEmpty` | секция TOP MODELS скрыта | как обычно |
| `leaderboard == nil` | как обычно | `widget.leaderboard.no_account` |
| `entries.isEmpty` | как обычно | `widget.leaderboard.empty` |
| `meExtra != nil` | как обычно | top-8 + `⋯` + моя строка |

## Локализация

`StatsApp/Resources/*.lproj/Localizable.strings` и виджет используют общий пул ключей (виджет читает из своего bundle, но строки повторяются). Новые ключи:

- `section.leaderboard` → «Лидерборд» / «Leaderboard»
- `widget.leaderboard.no_account` → «Включи sharing в Настройках, чтобы увидеть лидерборд» / «Enable sharing in Settings to see the leaderboard»
- `widget.leaderboard.empty` → «Пока никого. Добавь друзей.» / «No friends yet.»

Существующие ключи (`period.day/week/month`, `delta.*`, `section.top_models`) переиспользуются.

## Тесты

| Файл | Тип | Что проверяем |
|---|---|---|
| `Tests/StatsAppTests/WidgetSnapshotTests.swift` | новый | (1) encode → decode round-trip с расширенными `PeriodSlice` и `LeaderboardSlice`; (2) back-compat: декодинг JSON-а без новых полей → `aiCostPrev = 0`, `leaderboard = nil`; (3) `meExtra` опционально кодируется. |
| `Tests/StatsAppTests/Sync/SyncCoordinatorSnapshotTests.swift` | новый | `buildAndWriteWidgetSnapshot` с мок-базой: записывает prev-cost из второго `aiTotals` и leaderboard top-8 + meExtra из `leaderboard_cache.payload_json`. Сценарии: я в топе → meExtra nil; я не в топе → meExtra с моим рангом; кэша нет → leaderboard nil. |
| `Tests/StatsAppTests/UI/CostDeltaFormatterTests.swift` | разделяемо с delta-and-rank | таблица кейсов формата `▲ +$X.XX`, `▼ −$X.XX`, скрытие по правилам. |
| `Tests/StatsAppTests/UI/RankDeltaFormatterTests.swift` | разделяемо с delta-and-rank | `NEW`, `▲N`, `▼N`, пустое значение при `prev == rank`. |

SwiftUI-вьюхи (`LargeView`, `LeaderboardRow`, `LeaderboardColumn`) юнит-тестами не покрываем — рендер тривиален, вся логика отображения вытащена в форматтеры. Визуальная проверка — Xcode preview/runtime.

## Что НЕ делаем

- Не добавляем `.systemExtraLarge` (это iOS-only, на macOS нет такого размера).
- Не тащим аватарки в виджет — отдельная задача, требует прокидывания PNG-кэша в `snapshot.json` или sandbox file-link, обе опции нетривиальны.
- Не добавляем настройку количества строк лидерборда в `PeriodConfigurationIntent`. 8 — жёстко.
- Не делаем deep-link «клик по строке лидерборда открывает app» — у macOS-виджетов с этим сложнее, чем у iOS; отдельный скоуп.
- Не трогаем Medium и Small.

## Зависимости и порядок

1. `feat/delta-and-rank` доезжает до состояния, где `formatCostDelta`/`formatRankDelta` вынесены в `Shared/Util/`. Если в текущей итерации delta-and-rank они окажутся в `StatsApp/Status/` — Large widget сначала их перенесёт в `Shared/Util/` (это допустимое улучшение в рамках задачи, не плодит абстракций).
2. Расширяется `WidgetSnapshot` + back-compat decoder.
3. Расширяется `SyncCoordinator.buildAndWriteWidgetSnapshot`.
4. Добавляется `.systemLarge` в `supportedFamilies` + `LargeView` + `LeaderboardColumn` + `LeaderboardRow`.
5. Локализация.
6. Тесты.
7. Обновление `CHANGELOG.md` и `README.md` (упомянуть, что виджет умеет Large).

## Риски

- **Размер `snapshot.json`.** +27 leaderboard entries в худшем случае — ~3-5 KB сверху. Незаметно. Не риск.
- **Расхождение `is_me` между бэком и клиентом.** `is_me` приходит из API, доверяем. Если бэк сломается — `isMe` будет false везде, подсветки не будет, но виджет не упадёт.
- **Период `month` лидерборда** на бэке = 30-дневное окно, у клиентских AI-трат — тоже 30 дней (`lookbackDays = 29`). Симметрично, расхождений не будет.
- **Прав на keychain в виджете нет.** `myFriendCode` нужен для определения «я не в топ-8 → добавить meExtra». Решено выше в модели данных: поле `myFriendCode: String?` сидит в корне `WidgetSnapshot`, app его пишет (keychain доступен не-sandboxed app'у), виджет читает.

## Открытые вопросы

Нет. Все требования согласованы в сессии brainstorming 2026-05-23.
