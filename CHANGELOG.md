# Changelog

Все заметные изменения проекта.
Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

## [Unreleased]

### Fix: ccusage из GUI снова работает (env PATH для child-процесса)

- ccusage не запускался: `processFailed(exitCode: 127, stderr: "env: node: No such file or directory")`. GUI-приложение наследует PATH = `/usr/bin:/bin` без brew/nvm, `npx` через shebang `#!/usr/bin/env node` ищет node в этом голом PATH и валится.
- `CcusageFetcher` теперь явно задаёт `process.environment` с расширенным PATH (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.bun/bin` плюс существующий). Логика `extraSearchPaths` общая для `resolveExecutable` и env'а child-процесса.
- Тесты на pure-функцию `enrichedEnvironment`: prepend brew к чистому PATH, no-dup при повторе, обработка пустого PATH, сохранение прочих ключей.
- Симптом: виджеты по нулям, новые данные не накапливались. Это и было причиной сегодняшних "$0" в Small/Medium и "Пока никого" в Large.

### Аватарка профиля — отображение и смена

- Свой аватар хранится локально как BLOB в `my_profile` (поля `avatar_blob`, `avatar_mime`, `avatar_etag`, миграция v8) — по аналогии с `friend_profiles`. `avatar_path` остаётся как legacy-колонка, удалю позже.
- В Settings/Аккаунт у созданного профиля теперь рисуется реальный аватар вместо хардкод-символа `person.crop.circle`. Появилась кнопка «Сменить аватарку» — PATCH `/profiles/me` + локальный апдейт через `StatsQueries.updateMyAvatar`.
- При создании аккаунта BLOB сохраняется сразу после ответа сервера — до этого аватарка отправлялась на сервер, но локально не кэшировалась и не показывалась.
- `FriendsPullSyncer` после цикла друзей догружает свой аватар тем же conditional GET с ETag — это backfill для аккаунтов, созданных до v8.
- В превью при создании виден сам файл (через `AvatarView`), а не только размер в байтах.
- В popover-лидерборде (`FriendRow`) вместо градиентного кружка рисуется реальный аватар при наличии blob. Свой код подмешивается в `DropdownViewModel.friendAvatars` из `my_profile`. Large widget остаётся на градиенте — таскать blob'ы в JSON-snapshot нерационально.

### Rebrand → Burn

- Продукт переименован: `ai-stats` → **Burn**. Затронуты только user-facing surfaces — display name в Dock/Spotlight/Cmd+Tab, заголовок окна Settings, About-строка, default-имя экспорта DB (`burn-YYYYMMDD.db`), имя виджета в Apple Widget Gallery, локализованный alert "failed to start" (en + ru).
- Новая иконка приложения: тёмное glass-squircle + горячий уголёк (pink core, double pink/cyan glow). Рендерится из Swift+CoreGraphics-скрипта `scripts/render-app-icon.swift` для 10 размеров AppIcon.appiconset через `scripts/generate-app-icon-set.sh`.
- Mini-ember в menu bar capsule вместо SF-символа `chart.line.uptrend.xyaxis`. Pure SwiftUI (`MiniEmberView`), цвета из `BrandColor`-токенов.
- Внутренние идентификаторы (bundle ID `com.sergeytovarov.aistats`, target names, пути в файловой системе `~/.config/ai-stats/`, `~/Library/Application Support/ai-stats/`, NSLog-теги, User-Agent, git repo) сохранены. Их renaming — отдельный шаг под v1.0 open-source cleanup.

### Полная переделка визуала — Liquid Glass + Neon Duo (B2)
- Поповер: единый floating glass island внизу объединяет категорию (AI / GitHub / Друзья) и период (Д/Н/М). Два отдельных segmented picker удалены. Цвет crumb меняется по вкладке: pink / cyan / нейтрал.
- Главное число — gradient text (white → pink/cyan), фон каждой поверхности — 3-слойный (Tahoe `.glassEffect()` + внутренний radial pink top-left + radial cyan bottom-right), идентичность держится на любых обоях.
- Виджеты Small/Medium/Large переведены на единый visual language с поповером (общий `BrandSurface`, `HeroNumber`, `FriendRow`, `Crumb`). Цены в виджетах округляются до доллара, в поповере — с копейками.
- Menu bar item — capsule с pink→cyan градиентом и SF Symbol `chart.line.uptrend.xyaxis` вместо plain title.
- Sync/⚙ кнопки — квадраты 28×28 в glass-tile с hover.
- Sparkline получил variant API (`.ai` pink / `.github` cyan) и gradient stroke + area fill.
- Дизайн-токены (Color, Font, Spacing, Radius) вынесены в `Shared/Design/Tokens.swift`.
- Лейбл «Лидерборд» в UI заменён на «Друзья» (в коде сущность остаётся `Leaderboard`).

### Удалено
- Поддержка macOS 14/15. Минимум — **macOS 26 Tahoe** (для нативных Liquid Glass API).

### Large виджет + дельта в виджетах поменьше
- Новый Large виджет на десктопе: совмещённый экран «мои траты + лидерборд». Слева — сумма с дельтой и top-3 моделей за период, справа — топ-8 лидерборда с дельтой ранга (`▲N` / `▼N` / `NEW`), моя строка подсвечена. Если меня нет в топ-8 — добавляется отдельной строкой ниже после `⋯`. Без аккаунта sharing — справа подсказка «Включи sharing в Настройках».
- Дельта трат vs прошлый период в Small и Medium виджетах: под суммой появляется строка вида `▲ +$27.60 vs prev day` (зелёная — рост, красная — падение). Скрывается при отсутствии данных за прошлый период или при разнице меньше копейки.
- Технически: `WidgetSnapshot` расширен полями `aiCostPrev`, `leaderboard`, `myFriendCode` (back-compat decoder); `SyncCoordinator.buildAndWriteWidgetSnapshot` считает prev-cost вторым вызовом `aiTotals` и парсит `leaderboard_cache.payload_json` в `LeaderboardSlice`. `DropdownFormat` (форматтеры дельт и токенов) переехал в `Shared/Util/Formatters.swift`, используется и app, и виджетом.

### UI — динамика в дропдауне
- AI-секция: под крупной цифрой трат показывается дельта vs предыдущий период (день → вчера, неделя → прошлая неделя, месяц → прошлый месяц). Зелёный — больше потратил, красный — меньше.
- Лидерборд: рядом с рангом каждой строки — стрелка `▲N` (поднялся в рейтинге, зелёный) / `▼N` (опустился, красный) / `NEW` (не было в прошлом периоде).
- Серверный контракт: `/api/leaderboard` отдаёт `previous_rank: int | null` в каждой entry. Пока бэк не раскатан — клиент тихо показывает `NEW` всем, не ломается.

### Client v0.3.0 — friends + leaderboard + blocked в app
- Новая вкладка «Друзья» в Settings: добавить по коду, список с аватарками, удалить / удалить+заблокировать.
- Новая вкладка «Заблокированные»: список + разблокировка.
- Новая секция «Лидерборд» в menu bar dropdown — top-5, аватарки, твоя строка bold.
- Лидерборд автоматически переключается при смене period (день/неделя/месяц).
- Локальный кэш: `friend_profiles` (миграция v7) с avatar_blob + ETag, `leaderboard_cache` за все 4 периода. Оффлайн-фолбэк.
- `FriendsPullSyncer` + `LeaderboardPullSyncer` интегрированы в общий sync-тик (после snapshot push).
- `AiuseAPIClient.getAvatar` с conditional GET по If-None-Match.
- Memory-cache для `api_secret` в `SecretBox` — один Keychain prompt за сессию вместо потока (unsigned-app проблема).

### Backend v0.3.0 — friends + blocks + leaderboard + avatars endpoints
- `POST /api/friends`, `GET /api/friends`, `DELETE /api/friends/{code}` (с опц. block).
- `GET /api/blocks`, `DELETE /api/blocks/{code}`.
- `GET /api/leaderboard?period={day|week|month|24h}` — SUM tokens среди друзей + я, фильтрация неактивных профилей.
- `GET /api/avatars/{code}` — отдача bytea с ETag/304.
- Симметричная friendship одной строкой `(min(a,b), max(a,b))`, JOIN через `or_`.
- Блок маскируется под 404 (не палим факт блокировки).
- Backend `ai-stats-api` 0.3.0 задеплоен на aiuse.popovs.tech, 58 тестов passed.

### Добавлено — aiuse backend integration (v0.2.0 leaderboard client)
- `AiuseAPIClient` и `KeychainStore` для взаимодействия с `aiuse.popovs.tech/api`.
- Новая вкладка «Аккаунт» в Settings: создание профиля, friend_code с копированием, шаринг toggle, регенерация ID, удаление аккаунта.
- `SnapshotSyncer` интегрирован в `SyncCoordinator` — после ccusage-тика шлёт daily-агрегаты на сервер.
- Локальные таблицы `my_profile` и `pending_snapshots` (миграция v5).
- Тесты: `KeychainStoreTests`, `AiuseAPIClientTests` (через MockURLProtocol), `SnapshotSyncerTests` (happy path, sharing off, retry, sum по providers).

Известное расхождение: шлём один snapshot/день с `hour_bucket = midnight UTC` (локальная БД хранит daily, ccusage не даёт hourly). Сервер хранит данные с hourly precision — `SUM` по day/week/month работает корректно.

## [0.2.0] — 2026-05-23

### Добавлено
- WidgetKit widget со Small + Medium размерами.
- Период в виджете настраивается через AppIntent (правый клик → Edit Widget): Day / Week / Month.
- Medium показывает топ-4 моделей.
- Миграция базы данных в App Group container (требуется для шаринга с виджетом).
- При успешном sync приложение вызывает WidgetCenter.shared.reloadAllTimelines().

## [0.1.0] — 2026-05-23

### Добавлено
- macOS menu bar app со статус-иконкой и SwiftUI dropdown.
- Сегментированный селектор Day / Week / Month.
- Sparkline-тренд AI-трат за последние 14 дней.
- Shell-out к `ccusage` для агрегатов по Claude Code, Codex и любым другим провайдерам из `enabled_providers`.
- Раздельные DTO под claude и codex (форматы JSON у них разные).
- Свой pricing table — USD за 1M токенов для claude/gpt-5.x. ccusage's costUSD больше не используется (он нулит codex-дни на subscription'е).
- GraphQL-фетчер GitHub-коммитов по всем доступным репозиториям.
- LOC tracking: additions/deletions через Contributor Stats API, недельная гранулярность, exponential backoff 2/4/8/16/16с на 202 Accepted, скип 404/403.
- Локальная SQLite-история с политикой never-decrease — удаление логов агентов не стирает уже накопленную статистику.
- Initial backfill на 365 дней при первом запуске.
- Settings sheet с Export / Import базы данных.
- Создание шаблонного конфига при первом запуске.
