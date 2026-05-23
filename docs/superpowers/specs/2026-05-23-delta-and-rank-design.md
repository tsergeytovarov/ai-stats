# Delta для трат и дельта ранга для лидерборда

**Дата:** 2026-05-23
**Статус:** Design approved, plan TBD
**Скоуп:** macOS app (`StatsApp`) + контракт API `aiuse.popovs.tech/api/leaderboard`

## Зачем

В дропдауне сейчас видна только текущая цифра — `$250.00` за день, `12.4k токенов`, список лидерборда с рангом. Не видно динамики. Цель:

1. Рядом с большой цифрой трат показывать дельту относительно прошлого периода (день → вчера, неделя → прошлая неделя, месяц → прошлый месяц).
2. В лидерборде для каждой строки показывать сдвиг позиции относительно прошлого периода.

GitHub-секцию в этой итерации не трогаем.

## Семантика цветов

- **Дельта трат:** больше = зелёный, меньше = красный. Логика — больше использования AI — больше работы.
- **Дельта ранга:** поднялся в рейтинге (номер уменьшился) = зелёный, опустился (номер вырос) = красный. Независимо от того, что числовой ранг при подъёме уменьшается.

## Архитектура

Две независимые подзадачи в одном слое каждая.

### Дельта трат — чисто клиент

Данные уже лежат в локальной БД. В `DropdownViewModel.reload()` делается второй вызов `StatsQueries.aiTotals(in:days:)` с диапазоном «предыдущее окно». Полученный `AITotals` сохраняется в `aiTotalsPrev`. Дельта считается в момент рендера форматтером.

Окна непересекающиеся и одинаковой длины. Для `period.lookbackDays = N` предыдущее окно — `[end − 2N − 1 … end − N − 1]` календарных дней.

| period | current window | previous window |
|---|---|---|
| `day` | сегодня | вчера |
| `week` | последние 7 дней | предыдущие 7 дней |
| `month` | последние 30 дней | предыдущие 30 дней |

### Дельта ранга — серверный контракт + клиент

Бэкенд `aiuse` расширяет `LeaderboardEntry` полем `previous_rank: int | null`. Логика на сервере:

- Для каждого `entry` в текущем окне посчитать её ранг в предыдущем окне той же длины.
- `null` — пользователя в предыдущем окне в выборке не было.

Клиент в DTO добавляет `previousRank: Int?`. В строке считает `current − previous` для стрелки.

«Предыдущий месяц» = 30 дней назад (симметрично с `lookbackDays = 29`), не календарный месяц.

### Что НЕ делаем

- Не плодим новые методы агрегации в `StatsQueries` — хватает повторного вызова `aiTotals` с другим `days:`.
- Не добавляем фоновую агрегацию prev-периода — считается синхронно в том же `reload()`.
- Не вводим клиентскую таблицу `leaderboard_history` — бэкенд знает, клиент не помнит.
- Не делаем миграцию БД — `leaderboard_cache.payload_json` уже хранит произвольный JSON.

## Модель данных и DTO

### Бэкенд (контракт)

`GET /api/leaderboard?period=day|week|month` отдаёт массив `entries`, каждый получает доп. поле:

```json
{
  "rank": 3,
  "previous_rank": 5,
  "...": "..."
}
```

`previous_rank` — `int` или `null`. Прочие поля без изменений.

### Клиент (Swift)

`StatsApp/Network/AiuseDTO.swift`:

```swift
struct LeaderboardEntry: Codable, Identifiable, Equatable {
    let rank: Int
    let previousRank: Int?       // new
    // ...existing fields...

    enum CodingKeys: String, CodingKey {
        case rank
        case previousRank = "previous_rank"  // new
        // ...
    }
}
```

`StatsApp/Status/DropdownViewModel.swift`:

```swift
@Published var aiTotalsPrev: AITotals = .init(totalCost: 0, totalInputTokens: 0, totalOutputTokens: 0)
```

В `reload()` второй вызов `aiTotals` для prev-окна.

`Shared/Util/DateUtils.swift`:

```swift
static func previousPeriodDays(endingAt end: Date, lookback: Int) -> [String]
```

Возвращает массив `isoDayLocal` для непересекающегося смежного окна слева от `daysRange(endingAt:lookback:)`.

## UI

### AI-секция

```
$250.00
▲ +$28.40 vs вчера          ← новая строка, мелкий шрифт, цвет по правилу
12.4M tokens
```

Лейбл периода:

- `day` → `vs вчера`
- `week` → `vs прошлой недели`
- `month` → `vs прошлого месяца`

Правила отображения строки дельты:

| Условие | Поведение |
|---|---|
| `current == 0` | строка не показывается |
| `current == prev` | строка не показывается |
| `prev == 0 && current > 0` | `▲ +$X.XX vs ...`, зелёный |
| `prev > 0 && current > prev` | `▲ +$X.XX vs ...`, зелёный |
| `prev > 0 && current < prev` | `▼ −$X.XX vs ...`, красный |

Формат — абсолют в долларах (`$X.XX`), без процентов. Знак внутри стрелки (`▲`/`▼`), сумма всегда положительная.

### Leaderboard-секция

```
1. ▲10  [ava] Сергей            12.4k tok
2. ▼3   [ava] Вася               9.8k tok
3. NEW  [ava] Петя               4.1k tok
4.      [ava] Гриша              3.0k tok    ← previous_rank == rank
```

Правила:

| Условие | Поведение |
|---|---|
| `previous_rank == nil` | `NEW`, нейтральный серый |
| `previous_rank == rank` | пусто (резервируем место, но не рисуем) |
| `previous_rank > rank` | `▲N`, зелёный, где `N = previous_rank − rank` |
| `previous_rank < rank` | `▼N`, красный, где `N = rank − previous_rank` |

Ширина зарезервирована под 3 символа (`▲99` максимум), чтобы колонка с аватарками не прыгала.

### Новые компоненты

В `StatsApp/Status/DropdownSections.swift`:

```swift
struct CostDelta: View {
    let current: Double
    let previous: Double
    let period: Period
}

struct RankDelta: View {
    let current: Int
    let previous: Int?
}
```

Каждый View вызывает чистую функцию-форматтер (`formatCostDelta`, `formatRankDelta`), возвращающую `(text: String, color: Color)?`. Это позволяет тестировать форматтеры без SwiftUI-рендера.

### Локализация

`StatsApp/Resources/*.lproj/Localizable.strings` — новые ключи:

- `delta.vs_yesterday`
- `delta.vs_prev_week`
- `delta.vs_prev_month`
- `delta.new`

Локали — те же, что уже есть (минимум ru, en — если оба представлены).

## Тесты

| Файл | Тип | Что проверяем |
|---|---|---|
| `Tests/StatsAppTests/DateUtilsTests.swift` | расширить | `previousPeriodDays` для `lookback=0,6,29` — непересекающиеся окна равной длины |
| `Tests/StatsAppTests/StatsQueriesTests.swift` | расширить | контракт `aiTotals` для двух непересекающихся диапазонов |
| `Tests/StatsAppTests/Network/AiuseAPIClientTests.swift` | расширить | декодинг `LeaderboardResponse` с `previous_rank` (Int) и без (`null` → `nil`) |
| `Tests/StatsAppTests/UI/CostDeltaTests.swift` | новый | таблица кейсов из правил отображения выше |
| `Tests/StatsAppTests/UI/RankDeltaTests.swift` | новый | таблица кейсов из правил отображения выше |

UI-тесты SwiftUI-вьюх не пишем — тестируем чистые форматтеры, View их зовёт.

## План изменений по файлам (клиент)

| Файл | Изменение |
|---|---|
| `StatsApp/Network/AiuseDTO.swift` | + `previousRank: Int?` в `LeaderboardEntry`, + `case previousRank = "previous_rank"` |
| `Shared/Util/DateUtils.swift` | + `previousPeriodDays(endingAt:lookback:) -> [String]` |
| `StatsApp/Status/DropdownViewModel.swift` | + `@Published var aiTotalsPrev`; в `reload()` второй вызов `aiTotals` для prev-окна |
| `StatsApp/Status/DropdownSections.swift` | + `CostDelta`, `RankDelta`, форматтеры; интеграция в `DropdownAISection` и `DropdownLeaderboardSection` |
| `StatsApp/Resources/*.lproj/Localizable.strings` | + ключи `delta.vs_yesterday`, `delta.vs_prev_week`, `delta.vs_prev_month`, `delta.new` |
| `CHANGELOG.md` | запись в `## [Unreleased]` |

## План изменений по файлам (бэкенд)

В **этой** спеке фиксируется только контракт `previous_rank: int | null`. Реализация серверной агрегации — отдельная задача в репозитории `aiuse`, за рамками клиентского implementation plan'а.

Совместимость: пока бэкенд не раскатан, поле приходит как `null` (или отсутствует — декодинг `Optional<Int>` это переваривает), клиент показывает `NEW` всем и не падает.

## Риски и открытые вопросы

- **Согласование контракта с бэкендом.** Если бэк отдаст другое имя поля или уже-посчитанную `rank_delta` — клиент сломается на декодинге. Контракт зафиксирован выше; до его реализации клиент работает в режиме «все NEW».
- **Прошлый период = 30 дней vs календарный месяц.** Решено: 30 дней. Симметрично с `lookbackDays = 29`. Если потребуется календарный — это переделка и на клиенте, и на бэкенде.
- **Производительность.** Второй вызов `aiTotals` идёт по индексированному `day`, миллисекунды. Не паримся.
