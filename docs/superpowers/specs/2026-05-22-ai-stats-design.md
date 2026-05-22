# ai-stats — Design Spec

**Дата:** 2026-05-22
**Статус:** Draft v1 — ждёт ревью пользователя
**Автор:** Boris (через брейнсторм с Сергеем)

## 1. Цель и контекст

Личный macOS menu bar app, показывающий статистику использования AI-агентов (токены, $) и активности на GitHub (коммиты) за периоды Day / Week / Month. Долгосрочно — open source, в v0.1 — только для личного использования.

**Не делаем** (явно вырезано):
- ChatGPT web/Plus и Claude.ai web подписки — у них нет публичного API использования, перехватывать через cookies/scraping не будем.
- iCloud sync / multi-device merge — отложено в v0.3+.
- Алёрты, бюджеты, прогнозы — не нужны для MVP.
- Cross-platform — только macOS.

## 2. Фазировка

| Фаза | Содержание |
|------|------------|
| v0.1 | Menu bar app. ccusage shell-out + GitHub commits. SQLite. Export/Import DB. Settings sheet. Конфиг в JSON-файле. |
| v0.2 | WidgetKit виджет (small + medium), переезд DB в App Group container, расширение схемы под widget timeline. |
| v0.3 | GitHub LOC (additions/deletions) через contributor stats API. Merge при импорте DB (never-decrease между двумя источниками). |
| v1.0 | Open-source-ready: Keychain для API-ключей, onboarding UI, codesigning + notarization, distribution через Homebrew cask или DMG. README на двух языках, MIT license. |

Дальнейшее описание относится к **v0.1** если не указано иное.

## 3. Архитектура

### 3.1 Таргеты

Один Xcode проект, один таргет `StatsApp` (LSUIElement = YES — без иконки в Dock).

В v0.2 добавится второй таргет — `StatsWidget` (Widget Extension). Тогда же общий код вынесем в внутренний фреймворк `StatsKit` или просто в shared sources.

### 3.2 Структура процессов

В v0.1 — один процесс. `StatsApp` запускается, держит:
- `StatusItemController` — NSStatusItem + NSPopover с SwiftUI dropdown.
- `SyncCoordinator` — Timer на 5 минут + однократный sync при старте. Управляет фетчерами через Swift Concurrency (Task).
- `Database` (GRDB) — открыта на всё время жизни процесса.

Без отдельного launchd-демона. Если app не запущен — sync не происходит. Это осознанное ограничение v0.1.

### 3.3 Источники данных

#### 3.3.1 AI usage — через ccusage

`Process.run("bunx", ["-y", "ccusage@latest", "<provider>", "daily", "--json", "--since", "YYYYMMDD"])`.

- ccusage фильтрует по провайдеру через **subcommand**: `ccusage claude daily`, `ccusage codex daily` и т.д. Одного вызова на «все провайдеры с разбивкой» нет — делаем один вызов на каждого провайдера из списка `enabled_providers` в конфиге.
- Окно sync — последние 7 дней (`--since YYYYMMDD`, без дефисов).
- Парсим JSON. Структура:
  ```
  { "type": "daily", "data": [{ "date": "YYYY-MM-DD", "models": [...],
    "inputTokens": N, "outputTokens": N, "cacheCreationTokens": N,
    "cacheReadTokens": N, "totalTokens": N, "costUSD": N.NN }], "summary": {...} }
  ```
- Гранулярность хранения — **per (день, source)**, не per-модель. ccusage не отдаёт per-model breakdown в `daily`. Список моделей хранится как JSON массив в колонке `models`.
- В наш `input_tokens` мапим `inputTokens + cacheCreationTokens + cacheReadTokens` (кэш биллится по input rate). В `output_tokens` — `outputTokens`.
- **Требование к окружению:** установленный `bun` (или `node` + `npx`). Документируем в README. В v1.0 — либо бандлим, либо обнаруживаем при первом запуске и просим установить.

#### 3.3.2 GitHub commits

GraphQL запрос:
```graphql
query($from: DateTime!, $to: DateTime!) {
  viewer {
    contributionsCollection(from: $from, to: $to) {
      commitContributionsByRepository(maxRepositories: 100) {
        repository { nameWithOwner }
        contributions(first: 100) {
          nodes { occurredAt commitCount }
        }
      }
    }
  }
}
```

- Окно — те же 7 дней.
- Аггрегируем `commitCount` по дням, без разбивки по репам в v0.1 (репы — это столбец в DB, но UI на v0.1 показывает только daily total).
- Авторизация — personal access token, scope: `repo` (для приватных) + `read:user`.

### 3.4 Sync logic — «never-decrease»

Ядро политики хранения исторических данных.

```
Для каждого дня D в окне [today - sync_window .. today]:
  new = значение из источника
  old = значение в SQLite (если есть)

  if old is None:
    insert(D, new)
  elif new > old:
    update(D, new)
  else:
    skip  # never decrease
```

**Initial backfill.** При первом запуске (`sync_state` пустой для данного источника) `sync_window` расширяется до **365 дней**. Это разовая операция — нужна чтобы захватить уже существующую историю ccusage и GitHub. Дальше steady-state — 7 дней.

Применяется одинаково к AI usage и к GitHub. Покрывает:
- Удалили `~/.claude/` → ccusage отдаёт 0 за прошлые дни → старые цифры в DB сохраняются.
- Поставили новый Claude → новые дни накапливаются нормально.
- App offline несколько дней → следующий sync захватит окно 7d и заполнит пропуски.
- Первый запуск на машине где ccusage писал месяцами → backfill подтянет всю историю.

Дни старше окна не трогаем вообще — sealed forever (в рамках этой инсталляции).

### 3.5 Схема SQLite

```sql
CREATE TABLE ai_usage (
  id            INTEGER PRIMARY KEY,
  day           TEXT NOT NULL,           -- ISO YYYY-MM-DD
  source        TEXT NOT NULL,           -- 'claude', 'codex', ...
  models_json   TEXT NOT NULL,           -- JSON array: ["claude-opus-4-7", ...]
  input_tokens  INTEGER NOT NULL,        -- includes cacheCreation + cacheRead
  output_tokens INTEGER NOT NULL,
  cost_usd      REAL NOT NULL,
  updated_at    TEXT NOT NULL,
  UNIQUE(day, source)
);
CREATE INDEX idx_ai_usage_day ON ai_usage(day);

CREATE TABLE github_activity (
  id         INTEGER PRIMARY KEY,
  day        TEXT NOT NULL,
  repo       TEXT NOT NULL,             -- 'owner/repo'
  commits    INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(day, repo)
);
CREATE INDEX idx_github_day ON github_activity(day);

CREATE TABLE sync_state (
  source         TEXT PRIMARY KEY,      -- 'ccusage', 'github'
  last_sync_at   TEXT NOT NULL,
  last_error     TEXT
);
```

Single source of daily aggregate — ccusage. Никакого хранения сырых event'ов, никакого пересчёта из сырья. Если ccusage завтра поменяет формат — мы поменяем парсер, и `never-decrease` защитит историю.

### 3.6 Расположение файлов

```
~/Library/Application Support/ai-stats/stats.db
~/Library/Application Support/ai-stats/stats.db-wal
~/.config/ai-stats/config.json
```

В v0.2 (когда появится widget) `stats.db` переедет в App Group container:
`~/Library/Group Containers/group.com.sergeytovarov.aistats/stats.db`.
Миграция при первом запуске v0.2 — простой `FileManager.copyItem` со старого места.

### 3.7 Config файл

```json
{
  "github_token": "ghp_xxx",
  "github_login": "popovs",
  "sync_interval_minutes": 5,
  "ccusage_command": ["npx", "-y", "ccusage@latest"],
  "enabled_providers": ["claude", "codex"]
}
```

`enabled_providers` — список ccusage subcommand'ов которые мы будем дёргать. На v0.1 — `claude` и `codex`. Если у юзера появится OpenCode/Amp/etc — добавит руками в конфиг.

Читается при старте app. Изменения требуют рестарта app в v0.1 (никакого file watcher).

**Если конфиг отсутствует** при первом запуске:
1. App создаёт `~/.config/ai-stats/config.json` с дефолтным шаблоном (пустой `github_token`, `github_login`).
2. Показывает алёрт «Config initialized at `<path>`. Add your GitHub token and restart the app.» с кнопкой «Open config».
3. Sync GitHub отключён пока `github_token` пустой. AI usage (ccusage) — работает независимо.

## 4. UI

### 4.1 Status item

- Иконка: SF Symbol `chart.line.uptrend.xyaxis`.
- Слева от иконки маленький текст: `$X.XX` — сегодняшний total cost. Обновляется каждые 5 мин вместе с sync, плюс сразу после ручного refresh.

### 4.2 Dropdown (NSPopover, SwiftUI)

Размер: ~380×480 pt.

```
┌─────────────────────────────────────────┐
│  [ Day ] [ Week ] [ Month ]             │
├─────────────────────────────────────────┤
│  $42.18                                 │
│  1.2M tokens • 17 commits               │
├─────────────────────────────────────────┤
│  AI Usage                               │
│  ┌────────────┬──────────┬──────────┐   │
│  │ claude     │ $31.40   │ 870k tok │   │
│  │ codex      │ $10.78   │ 330k tok │   │
│  └────────────┴──────────┴──────────┘   │
│  Total: $42.18 • 1.2M tokens            │
├─────────────────────────────────────────┤
│  GitHub                                 │
│  17 commits across 4 repos              │
├─────────────────────────────────────────┤
│  Trend (last 14 days)                   │
│  ▁▂▄▅▇█▆▅▃▂▄▆█▆                         │
├─────────────────────────────────────────┤
│  Last sync 2m ago      [↻]   [⚙ ︎]       │
└─────────────────────────────────────────┘
```

- Сегментированный контрол сверху меняет «активный период» для всего dropdown.
- Карточка «Сводка» — крупный total cost AI, под ним токены и коммиты.
- **AI Usage** — отдельная секция, таблица per-source с $ и tokens. Простой VStack of HStacks.
- **GitHub** — отдельная секция. Метрика — `commits + repos count`. Без $, без таблицы — другие единицы измерения, мешать с AI нельзя.
- Sparkline всегда показывает последние 14 дней независимо от выбранного периода — даёт контекст вне зависимости от текущего фильтра. Метрика sparkline — total AI cost per day (фиксированно, не зависит от периода-фильтра).
- `↻` — manual refresh (запускает sync асинхронно).
- `⚙` — открывает Settings sheet.

### 4.3 Settings sheet

Отдельное окно (`NSWindow`, не popover), чтобы файловые диалоги нормально себя вели.

```
┌──────────────────────────────────────┐
│  Settings                            │
├──────────────────────────────────────┤
│  Config file:                        │
│  ~/.config/ai-stats/config.json      │
│  [ Open in editor ]                  │
│                                      │
│  Database                            │
│  ~/.../stats.db (3.2 MB)             │
│  [ Export… ]  [ Import… ]            │
│                                      │
│  [ Refresh now ]                     │
│                                      │
│  ai-stats v0.1.0                     │
└──────────────────────────────────────┘
```

**Export:** `NSSavePanel` → `PRAGMA wal_checkpoint(TRUNCATE)` → `FileManager.copyItem` в выбранную точку.

**Import:** `NSOpenPanel` → confirmation alert «This will replace your current database. A backup will be saved at `<path>`. Continue?» → backup текущей DB в `stats.db.backup-<yyyyMMdd-HHmmss>` рядом → закрыть GRDB connection → копирование → переоткрыть connection → trigger UI refresh.

Merge при импорте — **не в v0.1** (см. фазу v0.3).

## 5. Update cadence

- Sync triggered: при старте app + каждые 5 минут (configurable через `sync_interval_minutes`).
- Manual refresh из dropdown или Settings — иммедиатный sync, не сбрасывает таймер.
- Если sync уже в полёте — новый запрос игнорируется (single-flight).

## 6. Зависимости

- **Swift packages:** [GRDB.swift](https://github.com/groue/GRDB.swift) (SQLite ORM).
- **System frameworks:** SwiftUI, AppKit, Charts, Combine, Security (последнее — потенциально, не v0.1).
- **External runtime:** `bun` (или `node`) для запуска ccusage. Documented в README.
- **Target:** macOS 14 Sonoma+ (Swift Charts mature, modern Process API).

## 7. Структура проекта

```
ai-stats/
├── ai-stats.xcodeproj/
├── StatsApp/
│   ├── StatsApp.swift              # @main
│   ├── Status/
│   │   ├── StatusItemController.swift
│   │   └── DropdownView.swift      # SwiftUI
│   ├── Settings/
│   │   ├── SettingsWindowController.swift
│   │   └── SettingsView.swift
│   ├── Sources/
│   │   ├── CcusageFetcher.swift
│   │   ├── GitHubFetcher.swift
│   │   └── FetcherProtocol.swift
│   ├── Storage/
│   │   ├── Database.swift          # GRDB setup, schema migrations
│   │   ├── AIUsageDay.swift
│   │   ├── GitHubDay.swift
│   │   └── NeverDecreaseUpserter.swift
│   ├── Sync/
│   │   └── SyncCoordinator.swift
│   ├── Config/
│   │   └── Config.swift            # JSON parser
│   └── Resources/
│       └── Assets.xcassets
├── Tests/
│   └── StatsAppTests/
│       ├── NeverDecreaseUpserterTests.swift
│       ├── CcusageParserTests.swift
│       └── GitHubFetcherTests.swift   # с заглушкой GraphQL
├── README.md
├── CHANGELOG.md
└── .gitignore
```

## 8. Тестирование

- **Unit-тесты обязательны** для:
  - `NeverDecreaseUpserter` — табличные кейсы (нет записи / больше / меньше / равно).
  - `CcusageParser` — на зафиксированных фикстурах вывода ccusage.
  - `GitHubFetcher` — против замоканного GraphQL ответа.
- **Без интеграционных тестов на реальные сервисы** в CI. Реальный ccusage и GitHub — ручной smoke на dev машине.
- UI-тесты — не делаем в v0.1.

## 9. Открытые вопросы (отложены)

- Бандлить `bun + ccusage` внутрь .app или требовать installed runtime — решение к v1.0.
- App Group identifier — финализировать перед v0.2 (нужен для widget extension).
- Codesigning identity / notarization workflow — v1.0.

---

**Approval gate:** этот спек — основа для следующего шага (writing-plans). Любые правки лучше внести до того как пойдём в implementation plan.
