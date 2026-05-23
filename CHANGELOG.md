# Changelog

Все заметные изменения проекта.
Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

## [Unreleased]

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
