# План C — подсистема «Аналитика»

> **For agentic workers:** REQUIRED SUB-SKILL: super-puper-powers:subagent-driven-development. Шаги — чекбоксы.
> **Порядок:** исполнять ПОСЛЕ Плана B (нужна `DropdownSection` уже сведённая к `.expenses`, чтобы добавить `.analytics`).

**Goal:** Вкладка «Аналитика» за фикс-окно 30 дней: ингест транскриптов Claude Code + Codex в GRDB, вердикты «мог быть дешевле» по лестницам моделей, карточка (суммы + утечки + советы + шпаргалка), строка советника в Large-виджете.

**Architecture:** Новый модуль `StatsApp/Analytics/` и `Shared/Analytics/`. Ингестор перечитывает изменённые transcript-файлы целиком (mtime/size-гейт) → upsert в `analytics_turns`. Расчёт карточки (30-дневное окно, полуночная граница локальной TZ) детерминированно считает суммы/вердикты/кластеры/лимиты. Нормативная референс-реализация методики — `scripts/analytics-prototype/experiment2.py` + `experiment3.py`: при расхождении прозы и прототипа прав прототип.

**Tech Stack:** Swift/SwiftUI, GRDB, XCTest. Verify: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/<Suite>`.

## Global Constraints

- Окно = последние 30 дней, граница = начало локального календарного дня даты `now−30д`. Без переключателя периода.
- Приватность (жёсткое): `prompt_head` (≤300 символов) НИКОГДА не уходит в сеть/снапшот — только локальная БД и экспорт БД.
- Формула экономии (спека 5.3): не-T0 → 0; T0 tier0 → `cost × judgeRatioT0(source)`; T0 tier1/2 → `max(0, cost − cf_usd)`. `judgeRatioT0`: claude 0.057, codex 0.072.
- Ступени по префиксу имени модели (специфичный раньше общего): T0 = claude-fable-/mythos-/opus-, gpt-5.5, gpt-5.6-sol; средняя = claude-sonnet-, gpt-5.4 (не mini), gpt-5.6-terra; маленькая = claude-haiku-, gpt-5.4-mini, gpt-5.3-codex-spark, gpt-5.6-luna. Вердикт только T0.
- Целевые модели даунгрейда: claude→claude-sonnet-4-6(t1)/claude-haiku-4-5(t2); codex→gpt-5.4(t1)/gpt-5.4-mini(t2).
- Деньги — целые доллары через `MoneyFormatter.widget`; пороги в целых центах; % объёма = `Σexp_saved/Σcost_usd` (доллары); токены — новый `AnalyticsFormat.tokens` (млрд/млн/тыс).
- Coauthor trailer в каждом коммите.

---

### Task C1: GRDB-схема аналитики (миграция v9 + records)

**Verification:** unit (`DatabaseTests` расширить ассертом таблиц; новый `AnalyticsModelsTests`).

**Files:**
- Modify: `Shared/Storage/Database.swift` — добавить `migrator.registerMigration("v9_analytics")` ПОСЛЕ v8, до `try migrator.migrate`. Четыре таблицы (спека 5.2):
  - `analytics_turns(id INTEGER PK AUTOINCREMENT, source, ts, day, session, project, model, effort, origin, prompt_head, prompt_chars, n_requests, n_tool_calls, n_edits, input_tokens, cache_read, cache_create_5m, cache_create_1h, output_tokens, cost_usd, heur_tier, cf_model, cf_usd, exp_saved_usd, UNIQUE(source, session, ts))` + индекс по `day`
  - `analytics_ingest_state(path TEXT PRIMARY KEY, mtime REAL, size INTEGER)`
  - `analytics_meta(key TEXT PRIMARY KEY, value TEXT)`
  - `analytics_rate_limits(path TEXT, ts TEXT, window TEXT, used_percent REAL, UNIQUE(path, ts, window))`
- Modify: `Shared/Storage/Models.swift` — records `AnalyticsTurnRow`, `AnalyticsIngestStateRow`, `AnalyticsMetaRow`, `AnalyticsRateLimitRow` по паттерну файла (Codable/FetchableRecord/PersistableRecord/Equatable, Columns, CodingKeys snake_case, `id: Int64?` для turns; nullable-defaults для эволюции).
- Modify: `Tests/StatsAppTests/DatabaseTests.swift` — добавить 4 новые таблицы в ассерт набора таблиц.
- Create: `Tests/StatsAppTests/Analytics/AnalyticsModelsTests.swift` — round-trip insert/fetch каждого record в in-memory DB.

**Interfaces produces:** record-типы выше — потребляются всеми следующими задачами.

**Steps:**
- [ ] Написать падающий `AnalyticsModelsTests` (insert AnalyticsTurnRow → fetch → Equatable).
- [ ] Run → fail (нет таблицы/типа).
- [ ] Добавить миграцию v9 + records.
- [ ] Run `DatabaseTests`+`AnalyticsModelsTests` → pass.
- [ ] Commit: `feat(analytics): GRDB-схема analytics_turns и спутники (миграция v9)`.

---

### Task C2: Парсеры транскриптов (порт прототипа)

**Verification:** unit (`AnalyticsParserTests` с inline-JSONL фикстурами, как `ClaudeCoworkParserTests`).

**Files:**
- Create: `Shared/Analytics/AnalyticsTurn.swift` — value-тип `ParsedTurn` (поля = колонки `analytics_turns` без id/cost/tier, они считаются позже).
- Create: `Shared/Analytics/ClaudeTranscriptParser.swift` — порт `parse_claude` из `experiment2.py`: ход = user-запись с реальным промптом (не tool_result/isMeta/sidechain) + assistant-записи до следующего промпта; usage дедуп по `message.id` (последнее вхождение); `<synthetic>` пропуск; cache-write 5m/1h из `usage.cache_creation`; тул-коллы = `tool_use` не-sidechain; edits = Edit/Write/MultiEdit/NotebookEdit; `origin` по правилу 5.2 (после lstrip: `<command-`→human, иначе `<`→auto, иначе human).
- Create: `Shared/Analytics/CodexRolloutParser.swift` — порт `parse_codex`: ход = `turn_context`(model,effort); токены = дельты кумулятивного `token_count.total_token_usage` (cached ⊂ input); тул-коллы = `custom_tool_call|function_call|local_shell_call`; edits = имя тула содержит `patch`; rate_limits при `limit_id=="codex"` (primary 5ч/secondary неделя).
- Create: `Tests/StatsAppTests/Analytics/AnalyticsParserTests.swift` — inline JSONL: 1 claude-ход с тул-коллами и правкой; 1 codex-ход с дельтой токенов; проверка origin (command/task-notification/обычный); проверка дедупа usage.

**Interfaces produces:** `ClaudeTranscriptParser.parse(lines:) -> [ParsedTurn]`, `CodexRolloutParser.parse(lines:) -> (turns: [ParsedTurn], rateLimits: [ParsedRateLimit])`.

**Steps:**
- [ ] Падающие тесты с эталонными числами (сверить с прогоном прототипа на тех же inline-данных).
- [ ] Реализовать парсеры.
- [ ] Run → pass.
- [ ] Commit: `feat(analytics): парсеры транскриптов Claude Code и Codex`.

---

### Task C3: Классификатор ступеней + расчёт стоимости/экономии

**Verification:** unit (`AnalyticsVerdictTests`).

**Files:**
- Create: `Shared/Analytics/ModelLadder.swift` — `tier(for model:) -> Tier?` (префикс-матч, специфичный раньше общего; nil = не-T0), `targetModel(source:tier:)`, `judgeRatioT0(source:)`.
- Create: `Shared/Analytics/TurnCostCalculator.swift` — `cost` через `PricingTable.cost`; `heurTier(nEdits:nTools:outTok:promptChars:)` (5.3); `expSaved` по формуле (Global Constraints).
- Create: `Tests/StatsAppTests/Analytics/AnalyticsVerdictTests.swift` — таблица: opus короткий вопрос→tier2, exp_saved=cost×0.057; gpt-5.5 длинный агентный→tier0; sonnet→не-T0 exp_saved=0; проверка cf_usd по правильной целевой модели.

**Interfaces produces:** `TurnCostCalculator.enrich(_ turn: ParsedTurn) -> AnalyticsTurnRow` (проставляет cost_usd/heur_tier/cf_model/cf_usd/exp_saved_usd).

**Steps:**
- [ ] Падающие тесты вердиктов (числа из прототипа).
- [ ] Реализовать лестницу + калькулятор.
- [ ] Run → pass.
- [ ] Commit: `feat(analytics): лестницы моделей и расчёт экономии`.

---

### Task C4: Ингестор (файловый гейт + upsert + pricing_version)

**Verification:** unit (`AnalyticsIngestorTests` с temp-директорией фикстур).

**Files:**
- Create: `StatsApp/Analytics/AnalyticsIngestor.swift` — обход `~/.claude/projects/**/*.jsonl` и `~/.codex/sessions/**/*.jsonl` (инъектируемые базовые URL + `now:()->Date`, как в `ClaudeCoworkFetcher`); файл перечитывается целиком если `analytics_ingest_state.mtime/size` изменились; ходы → `enrich` → upsert по `UNIQUE(source, session, ts)` (`INSERT OR REPLACE`); rate_limits upsert по `UNIQUE(path, ts, window)`; окном НЕ режет (пишет всю историю); при смене `analytics_meta.pricing_version` — пересчёт cost/tier/exp_saved in-place по хранимым полям (без реингеста).
- Create: `StatsApp/Storage/` upsert-хелперы для analytics (или в `NeverDecreaseUpserter`): `INSERT OR REPLACE`, не never-decrease (ходы дополняются).
- Create: `Tests/StatsAppTests/Analytics/AnalyticsIngestorTests.swift` — temp-дир с 2 JSONL; ингест дважды → нет дублей; изменение файла → дополнение усечённого хода; смена pricing_version → пересчёт стоимости.

**Interfaces produces:** `AnalyticsIngestor.ingest() async throws` (idempotent).

**Steps:**
- [ ] Падающие тесты идемпотентности/upsert/пересчёта.
- [ ] Реализовать ингестор.
- [ ] Run → pass.
- [ ] Commit: `feat(analytics): инкрементальный ингестор транскриптов`.

---

### Task C5: Расчёт карточки (окно, лимиты, кластеры)

**Verification:** unit (`AnalyticsCardTests`).

**Files:**
- Create: `Shared/Analytics/AnalyticsCard.swift` — value-модель карточки: per-source (tokens, cost, weekLimitPct?, leakUsd, leakPct), топ-3 кластера (title/nModels/model/adviceText/usdPerMonth), шпаргалка. `Σexp_saved`, `topLeakTitle`, `advisorComputedAt`.
- Create: `StatsApp/Analytics/AnalyticsCardBuilder.swift` — SQL по `analytics_turns` за окно [начало дня now−30д, now]; лимиты Codex по эпохам `analytics_rate_limits.secondary` (сброс при падении >30 п.п.; вклад = max−первое; среднее/нед = Σэпох/(30/7)); кластеры (ключ = source+lower(первые60), спецключи command/`<`→уведомления; фильтр ≥3 ходов и exp_saved_cents>100; сорт exp_saved DESC, ходы DESC, ключ; топ-3); советы по типу кластера (тексты 5.5); состояния «нет данных»/«мало данных <50 ходов суммарно»/«утечек нет ≤$1».
- Create: `Shared/Util/AnalyticsFormat.swift` — `tokens(_:)`: ≥1e9 «X.XX млрд ток», ≥1e6 «N млн ток», ≥1e3 «N тыс ток», иначе «N ток».
- Create: `Tests/StatsAppTests/Analytics/AnalyticsCardTests.swift` — сид `analytics_turns`/`analytics_rate_limits`, проверка сумм/лимитов/кластеров/пороговых состояний; `AnalyticsFormatTests` для форматтера.

**Interfaces produces:** `AnalyticsCardBuilder.build(in db:) throws -> AnalyticsCard`.

**Steps:**
- [ ] Падающие тесты (числа сверить с `experiment3.py` на совпадающем сид-наборе).
- [ ] Реализовать builder + форматтер.
- [ ] Run → pass.
- [ ] Commit: `feat(analytics): расчёт карточки — окно, лимиты, кластеры, советы`.

---

### Task C6: Шпаргалка моделей (Codex из models_cache + Claude статик)

**Verification:** unit (`ModelGuideTests`).

**Files:**
- Create: `Shared/Analytics/ModelGuide.swift` — Codex: читать `~/.codex/models_cache.json` (инъектируемый URL), только `visibility=="list"`, в порядке файла (slug+description); файла нет → пустой Codex-раздел. Claude — статическая таблица (тексты 2.2 дословно).
- Create: `Tests/StatsAppTests/Analytics/ModelGuideTests.swift` — фикстура models_cache.json (зарегистрировать в project.yml resources!), проверка фильтра visibility и порядка; отсутствие файла → пусто.

**Steps:**
- [ ] Падающий тест на парс фикстуры.
- [ ] Реализовать + `project.yml` добавить фикстуру в `StatsAppTests` resources.
- [ ] Run → pass.
- [ ] Commit: `feat(analytics): шпаргалка моделей (Codex live + Claude статик)`.

---

### Task C7: Вкладка «Аналитика» в попапе

**Verification:** unit (VM-загрузка) + acceptance (открыть попап → пилюля «Аналитика» → карточка за 30 дней).

**Files:**
- Modify: `StatsApp/Status/DropdownViewModel.swift` — `DropdownSection` добавить `.analytics`; `@Published var analyticsCard: AnalyticsCard?`; `func loadAnalytics() async` (читает через `AnalyticsCardBuilder`); опц. ингест при открытии если последний >15 мин.
- Create: `StatsApp/Status/DropdownAnalyticsSection.swift` — рендер `AnalyticsCard` из дизайн-токенов (BrandSurface/HeroNumber/Crumb/BrandColor/BrandFont); блоки: заголовок, per-source, топ-утечки+советы, шпаргалка; состояния «нет данных»/«мало»/«утечек нет».
- Modify: `StatsApp/Status/DropdownView.swift` — `case .analytics:` → `DropdownAnalyticsSection`.
- Modify: `StatsApp/Status/IslandControl.swift` — вторая `CategoryPill` «Аналитика» (учесть 400pt ширину — 2 пилюли + период-сегмент).
- Create: `Tests/StatsAppTests/Status/DropdownAnalyticsTests.swift` — VM грузит карточку из сид-БД.

**Steps:**
- [ ] Падающий VM-тест.
- [ ] VM + секция + island-пилюля + switch-case.
- [ ] Run VM-тест → pass; сборка `.app`, acceptance: попап → «Аналитика» → карточка.
- [ ] Commit: `feat(analytics): вкладка Аналитика в попапе`.

---

### Task C8: Хук ингеста в refresh-цикл (гейт раз в час)

**Verification:** unit (`AnalyticsScheduleTests`).

**Files:**
- Modify: `StatsApp/Sync/SyncCoordinator.swift` или `AppContainer.swift` — вызывать `AnalyticsIngestor.ingest()` при старте и внутри тика с гейтом «не чаще раза в час» через `analytics_ingest_state`/`sync_state`-подобную метку в `analytics_meta(last_ingest_at)`. После успешного ингеста — пересчёт карточки и запись полей советника в снапшот (Task C9).
- Create: `Tests/StatsAppTests/Analytics/AnalyticsScheduleTests.swift` — метка <1ч → скип; >1ч → ингест; инъекция `now`.

**Steps:**
- [ ] Падающий тест гейта.
- [ ] Реализовать хук + гейт.
- [ ] Run → pass; `SyncCoordinatorTests` не сломаны.
- [ ] Commit: `feat(analytics): часовой ингест в refresh-цикле`.

---

### Task C9: Строка советника в Large-виджете

**Verification:** unit (`WidgetSnapshotTests` доп. поля) + acceptance (Large показывает строку/состояния).

**Files:**
- Modify: `Shared/WidgetSnapshot.swift` — добавить `advisorComputedAt: Date?`, `leakUsdPerMonth: Double?`, `topLeakTitle: String?` (decodeIfPresent). Семантика/маппинг состояний — спека 2.3.
- Modify: `StatsApp/Sync/SyncCoordinator.swift` `buildSnapshot` — заполнять поля советника из `AnalyticsCardBuilder` (Σexp_saved суммарно; topLeakTitle топ-1; в режиме «мало данных» — nil).
- Modify: `StatsWidget/StatsTimelineProvider.swift` `StatsEntry` + население; `LargeView.swift` — строка «Утекает ≈$X/мес · {topLeakTitle}» / «Утечек не видно…» / скрыта; плейсхолдер при `schemaVersion<2` (Task B5).
- Modify: `Tests/StatsAppTests/WidgetSnapshotTests.swift`, `Sync/SyncCoordinatorSnapshotTests.swift` — новые поля и три состояния.

**Steps:**
- [ ] Падающие тесты полей/состояний.
- [ ] Реализовать снапшот-поля + Large-строку.
- [ ] Run → pass; сборка виджета; acceptance Large.
- [ ] Commit: `feat(analytics): строка советника в Large-виджете`.

---

### Task C10: E2E-сверка с прототипом

**Verification:** manual (задокументированный ручной прогон — автоматом не проверить, нужны реальные транскрипты пользователя).

**Steps:**
- [ ] Собрать `.app`, дать ингесту отработать на реальных `~/.claude`/`~/.codex`.
- [ ] Прогнать `scripts/analytics-prototype/experiment3.py` с таймзоной машины (замена `Europe/Moscow` в experiment2/3).
- [ ] Сверить суммы карточки по источникам с выводом прототипа: расхождение ≤5% (критерий приёмки §9.3). Записать факт прогона и числа.
- [ ] Проверить критерий §9.4: gpt-5.6-*/spark ненулевые в топе.
- [ ] Commit (если были правки калибровки): `test(analytics): e2e-сверка карточки с эталонным прототипом`.
