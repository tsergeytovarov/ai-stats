# Лидерборд друзей + серверная синхронизация — Design Spec

**Дата:** 2026-05-23
**Статус:** Draft v1 — ждёт ревью пользователя
**Автор:** Boris (через брейнсторм с Сергеем)
**Связанный спек:** [2026-05-22-ai-stats-design.md](2026-05-22-ai-stats-design.md) (исходный дизайн локального app'а)

## 1. Цель и контекст

Сделать `ai-stats` чуть более «социальным»: добавить лидерборд использования AI-токенов среди друзей. Минимум фрикций, максимум приватности по умолчанию, прицел на 500 пользователей с возможным развитием в веб-морду и монетизацию.

Это превращает локальный personal-tool в мини-сеть: добавляется серверный компонент, граф дружбы по 10-символьным кодам, и WidgetKit-виджеты для рабочего стола.

### 1.1 Что появляется у юзера

- В Settings — две новые вкладки: «Аккаунт» (свой профиль, friend_code) и «Друзья» (список + добавление по коду + блокировки).
- В dropdown'е menu bar app'а — новая секция «Лидерборд», использует тот же period picker (день/неделя/месяц).
- На рабочем столе — два macOS WidgetKit-виджета:
  - **Personal** (small + medium): свои токены за конфигурируемый период.
  - **Leaderboard** (large): топ друзей.

### 1.2 Что не делаем (явно вырезано)

- Восстановление доступа при потере Keychain — отложено до веб-логина (нужен email/Apple ID).
- Push-нотификации («Вася обогнал тебя!»).
- Веб-морда с детальными графиками — отдельный проект, пока только лендинг.
- Монетизация, премиум-метрики — будущее.
- Offsite-бэкапы в Object Storage — пока pg_dump локально с ротацией 7 дней.
- Реал-тайм / WebSocket'ы — polling раз в 5 минут (синхронно с существующим sync-тиком).
- Лидерборд по другим метрикам (commits, LOC) — schema позволяет, но в API/UI не вытащено.
- Расшаривание через QR-код / deep-link — только текстовый friend_code.
- Лимит на batch больше 168 snapshots (неделя × 24 часа) — если копилось дольше, дроп самых старых.

## 2. Фазировка

| Фаза | Содержание |
|------|------------|
| **v0.2.0** | Серверный фундамент. Профиль + sync snapshot'ов. Settings → «Аккаунт». Без друзей, без лидерборда, без виджетов. |
| **v0.3.0** | Друзья + лидерборд в dropdown. Settings → «Друзья», блокировки, регенерация friend_code, API friends/blocks/leaderboard. |
| **v0.4.0** | WidgetKit extension. Personal (small + medium) + Leaderboard (large). Лендинг на `aiuse.popovs.tech/`. |

Каждая фаза — отдельный план реализации, пишется перед началом фазы (не все три сразу — детали v0.4.0 станут понятнее после v0.2.0/v0.3.0).

Дальнейшее описание относится ко **всему MVP (v0.2 → v0.4)**, если не указано иное.

## 3. Архитектура

### 3.1 Компоненты

```
                 ┌────────────────────────────────────┐
                 │  ai-stats (macOS, существующий)    │
                 │  - main app + WidgetKit extension  │
                 └────────────┬───────────────────────┘
                              │ HTTPS
                              │ POST /api/snapshots
                              │ GET  /api/leaderboard
                              │ Bearer: <api_secret>
                              │
              ┌───────────────▼──────────────────────────┐
              │  aiuse.popovs.tech (новый поддомен)      │
              │                                          │
              │  / ───────────────► landing (статика)    │
              │  /api/* ──────────► FastAPI (контейнер)  │
              │                       │                  │
              │                       ▼                  │
              │                  Postgres (контейнер)    │
              │                                          │
              │  cron: nightly pg_dump → /opt/aiuse/     │
              │        backups/ (ротация 7 дней)         │
              └──────────────────────────────────────────┘
```

### 3.2 Новые артефакты

| Что | Где |
|---|---|
| Новый репо `ai-stats-api` | FastAPI 0.100+, SQLAlchemy 2.0, Alembic, pytest. Шаблон копируется с `ramka` / `tracker` (см. infra README). |
| Поддомен `aiuse.popovs.tech` | A-запись в YC DNS на `93.77.187.42`. Расширение SAN cert через certbot `--expand`. Новый upstream и `server`-блок в `ingress/nginx.conf`. |
| Деплой бэкенда | `git push prod main` (стандартный post-receive хук в `/opt/aiuse/`). |
| Новый target `StatsWidget` | В существующем `project.yml`. WidgetKit extension. App Group `group.com.sergeytovarov.aistats` для shared container с main app. |
| Cron на VM | Одна строка: `0 3 * * * pg_dump ... | gzip > /opt/aiuse/backups/$(date +\%F).sql.gz && find /opt/aiuse/backups -mtime +7 -delete` |
| Лендинг | Статический HTML в `/opt/aiuse/landing/`, ingress nginx раздаёт напрямую (как `/opt/skillaz-proto` сейчас). Линкует на GitHub Releases latest. |

### 3.3 Что НЕ добавляется

- Никакого Object Storage. Аватарки — в Postgres как `bytea` (≤200 KB после сжатия клиентом до 256×256, 500 юзеров × 200 KB = ≤100 MB).
- Никаких очередей / Redis / фоновых воркеров — все операции синхронные.
- Никаких WebSocket'ов / SSE.
- Никаких отдельных тестовых БД-хостов — pytest поднимает Postgres контейнер.

## 4. Метрика и приватность данных

### 4.1 Что считаем

**input_tokens + output_tokens, без кэша.** Это «объём диалога», справедливая прокси активности независимо от модели:

- Cache reads дешёвые и могут раздуть объём в 10–100× на длинных сессиях — несправедливо.
- Output один не показывает полной картины (длинный input = много работы тоже).
- Цена в долларах отражает выбор модели, а не объём работы — для лидерборда не подходит.

Локально `CcusageFetcher` уже отдаёт эти числа отдельно — берём готовые.

### 4.2 Гранулярность

**Hourly** на сервере. Достаточно для day/week/month-агрегатов, не избыточно для трафика.

500 юзеров × 24 часа × 365 дней ≈ 4.4M строк/год. Индекс `(user_id, hour_bucket)` справится годами.

Клиент шлёт **абсолютные значения за час** (а не дельты) → гонок при upsert нет.

### 4.3 Opt-in

Шаринг **выключен по умолчанию** до явного создания аккаунта в Settings → «Аккаунт». Локальная статистика работает всегда независимо от шаринга.

Симметрия: если `sharing_enabled = false` — не шлёшь свои данные **и** не видишь чужой лидерборд (нет free-rider'ов).

## 5. Схема данных

### 5.1 Серверная часть (Postgres 16)

```sql
-- 1. Профиль
CREATE TABLE profiles (
    id               bigserial PRIMARY KEY,
    friend_code      text NOT NULL UNIQUE,   -- 10 chars, base32 без 0/O/1/I/l
    api_secret_hash  text NOT NULL,          -- sha256(api_secret) hex
    display_name     text NOT NULL,
    avatar           bytea,                  -- ≤200 KB
    avatar_mime      text,                   -- 'image/jpeg' | 'image/png'
    sharing_enabled  boolean NOT NULL DEFAULT true,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_profiles_friend_code ON profiles(friend_code);

-- 2. Снапшоты использования (hourly)
CREATE TABLE snapshots (
    user_id        bigint NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    hour_bucket    timestamptz NOT NULL,    -- UTC, floored to hour
    tokens_input   bigint NOT NULL DEFAULT 0,
    tokens_output  bigint NOT NULL DEFAULT 0,
    updated_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, hour_bucket)
);
CREATE INDEX idx_snapshots_hour ON snapshots(hour_bucket);

-- 3. Дружба (симметричная связь, одна строка на пару)
CREATE TABLE friendships (
    user_a_id   bigint NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    user_b_id   bigint NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_a_id, user_b_id),
    CHECK (user_a_id < user_b_id)
);
CREATE INDEX idx_friendships_b ON friendships(user_b_id);

-- 4. Блок-лист
CREATE TABLE blocks (
    blocker_id  bigint NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    blocked_id  bigint NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id != blocked_id)
);
```

**Обоснования:**

- `friend_code`: 10 символов base32 без `0/O/1/I/l` (визуально однозначно). В UI отображается с дефисами: `XK7P-3M9Q-2A`. Пространство ~10^15 — коллизии исключены для 500 юзеров.
- `api_secret_hash`: хэш, не сам секрет. БД-утечка не компрометирует Bearer-токены.
- `snapshots`: композитный PK `(user_id, hour_bucket)` обеспечивает идемпотентный upsert.
- `friendships`: нормализованная связь с `CHECK user_a < user_b` — нельзя случайно создать дубль.
- `blocks`: отдельная таблица, не флаг в `friendships` — блок переживает удаление дружбы.

### 5.2 Клиентская часть (GRDB, локальная)

Добавляется к существующим таблицам в `~/Library/Application Support/ai-stats/stats.db`:

```sql
-- Свой профиль (singleton)
CREATE TABLE my_profile (
    id                  INTEGER PRIMARY KEY CHECK (id = 1),
    friend_code         TEXT NOT NULL,
    display_name        TEXT NOT NULL,
    avatar_path         TEXT,
    sharing_enabled     INTEGER NOT NULL DEFAULT 1,
    server_user_id      INTEGER NOT NULL
);

-- Кэш профилей друзей
CREATE TABLE friend_profiles (
    friend_code      TEXT PRIMARY KEY,
    display_name     TEXT NOT NULL,
    avatar_blob      BLOB,
    avatar_mime      TEXT,
    last_fetched_at  REAL NOT NULL
);

-- Кэш лидерборда (последний снимок с сервера, для виджета)
CREATE TABLE leaderboard_cache (
    period           TEXT NOT NULL,
    fetched_at       REAL NOT NULL,
    payload_json     TEXT NOT NULL,
    PRIMARY KEY (period)
);

-- Очередь snapshot'ов на отправку (буфер при оффлайне)
CREATE TABLE pending_snapshots (
    hour_bucket      INTEGER PRIMARY KEY,
    tokens_input     INTEGER NOT NULL,
    tokens_output    INTEGER NOT NULL,
    attempts         INTEGER NOT NULL DEFAULT 0,
    last_error       TEXT
);
```

**`api_secret` НЕ в GRDB**, а в macOS Keychain (account `aiuse-api-secret`, service `tech.popovs.aiuse`).

### 5.3 App Group shared container (для виджета)

`group.com.sergeytovarov.aistats/`:
- `my_stats.json` — мои числа за периоды (для Personal widget)
- `leaderboard.json` — последний лидерборд (для Leaderboard widget)
- `friend_avatars/<friend_code>.jpg` — аватарки друзей

Виджет читает только эти файлы, в БД не лезет.

## 6. API контракт

Все эндпоинты под `/api/`, base URL `https://aiuse.popovs.tech/api/`. Auth для всех кроме `POST /profiles` — `Authorization: Bearer <api_secret>`.

### 6.1 Эндпоинты

**POST /api/profiles** — регистрация (без auth). Возвращает `friend_code` + `api_secret` (один раз!) + `server_user_id`.

**PATCH /api/profiles/me** — обновление имени / аватарки / sharing_enabled.

**POST /api/profiles/me/regenerate-friend-code** — генерит новый friend_code, рвёт все friendships. `api_secret` НЕ меняется.

**DELETE /api/profiles/me** — каскадно удаляет всё (snapshots, friendships, blocks). 204.

**POST /api/snapshots** — батч snapshot'ов (до 168). Upsert. 200 с количеством принятых. 403 если `sharing_enabled = false`.

**POST /api/friends** — добавить по `friend_code`. 201 / 404 / 409 (уже друзья) / 403 (блок — сообщение неотличимо от 404, чтобы не палить блок).

**GET /api/friends** — список друзей с метаданными.

**DELETE /api/friends/{friend_code}** с body `{ "block": bool }` — удалить связь, опционально заблокировать. 204.

**GET /api/blocks** — мой блок-лист (не «кто меня заблокировал»).

**DELETE /api/blocks/{friend_code}** — разблокировать. Связь сама не восстанавливается.

**GET /api/leaderboard?period={day|week|month|24h}** — топ среди моих друзей + я. Каждая entry: `{ friend_code, display_name, rank, tokens_total, is_me }`.

**GET /api/avatars/{friend_code}** — image bytes с ETag + Cache-Control: max-age=86400.

### 6.2 Лимиты и защиты

- Тело запроса: 256 KB (для аватарки).
- Rate limit: `POST /api/snapshots` 1 req/sec на user. Остальные 60 req/min.
- Лимит друзей: 100 (зашитая константа).
- Batch snapshots: до 168 (неделя × 24).
- Все timestamps UTC. `hour_bucket` floor'ится до часа.

## 7. Sync flow клиента

Три процесса, все живут внутри существующего sync-тика (`sync_interval_minutes` из config.json, default 5 минут).

### 7.1 Bootstrap (один раз на машине)

Аккаунт создаётся **не автоматически**, а по явному действию в Settings → «Аккаунт» (ввёл имя + аватарку, жмёт «Создать»). До этого `sharing_enabled = false` локально и ничего не шлётся.

После `POST /api/profiles`:
- `api_secret` → Keychain
- `friend_code`, `server_user_id` → `my_profile`
- `avatar_path` → файл в Application Support

### 7.2 Push snapshot'ов

Если `sharing_enabled && api_secret в Keychain`:
1. Берём из локальной БД суммы `tokens_input + tokens_output` `GROUP BY hour_bucket` за последние 24 часа.
2. Diff с `last_sent_snapshots` (в памяти процесса) — выявляем изменившиеся часы.
3. Изменения → `pending_snapshots` (idempotent upsert по `hour_bucket`).
4. `POST /api/snapshots` батчем (≤168).
5. На 2xx — `DELETE FROM pending_snapshots WHERE accepted`.
6. На ошибку — `attempts++`, `last_error`, ждём следующего тика. После 5 попыток — лог + дроп часа.

### 7.3 Pull данных для UI и виджета

После успешного push:
1. `GET /api/friends` → upsert `friend_profiles`, скачиваем аватарки по `If-None-Match` ETag.
2. `GET /api/leaderboard` для всех 4 периодов (day, week, month, 24h) → `leaderboard_cache`.
3. Записываем в App Group shared container: `my_stats.json`, `leaderboard.json`, `friend_avatars/*.jpg`.
4. `WidgetCenter.shared.reloadAllTimelines()`.

### 7.4 Сетевой клиент

Новый модуль `Network/AiuseAPIClient.swift`, ~200–300 строк. Один класс с async методами на каждый эндпоинт. `secretProvider: () -> String?` closure — лезет в Keychain, чтобы клиент не зависел от Keychain API напрямую (тестируется с моком).

## 8. Приватность и edge cases

### 8.1 Состояния шаринга

| `sharing_enabled` | Шлёт snapshot'ы? | Профиль виден другим? | Видит лидерборд? |
|---|---|---|---|
| true (default) | да | да | да |
| false | нет | да (имя+аватарка, без статистики) | нет (не шлёт → не получает) |

### 8.2 При выключении шаринга

- Сервер: ставит флаг. Старые snapshot'ы остаются в БД, но не возвращаются в `GET /api/leaderboard` другим юзерам (`WHERE sharing_enabled = true` в JOIN).
- Профиль остаётся в чужих `GET /api/friends` (имя + аватарка), без статистики.
- Если включить обратно — история сразу опять видна.
- Клиент: прекращает push/pull. Чистит `leaderboard_cache` + shared container. Виджет показывает «шаринг выключен».

### 8.3 При удалении аккаунта

Сервер одной транзакцией: `DELETE FROM profiles WHERE id = me` → каскадно snapshots, friendships, blocks, avatar.

Клиент: чистит Keychain, `my_profile`, `friend_profiles`, `leaderboard_cache`, `pending_snapshots`, shared container. **Локальная статистика остаётся** — это твоя история, к серверу не относится.

UI: confirm-диалог: `"Это удалит твой профиль, всю историю на сервере и все связи с друзьями. Локальная статистика останется. Действие необратимо."`

### 8.4 При регенерации friend_code

Сервер: генерит новый friend_code, `DELETE FROM friendships WHERE user_a = me OR user_b = me`. `api_secret` и история snapshot'ов НЕ трогаются.

Клиент: обновляет `friend_code` в `my_profile`, чистит `friend_profiles`.

UI: confirm-диалог с указанием количества разрываемых связей: `"Новый код заменит текущий. Все N друзей будут удалены — им придётся добавить тебя заново. Твоя история использования сохранится."`

### 8.5 Друг удалил аккаунт / выключил шаринг

В `GET /api/friends` его уже нет (если удалил) или есть без статистики (если выключил). Клиент при следующем sync обнаруживает расхождение и удаляет из `friend_profiles` — никаких «битых» друзей в локальном списке.

### 8.6 Блокировка

`DELETE /api/friends/{code}` с `{ "block": true }` → одна транзакция: рвём friendship + INSERT в blocks. Дальнейшая попытка этого юзера снова добавить мой friend_code → 403 с сообщением **неотличимым от «нет такого кода»**. Разблокировать = `DELETE /api/blocks/{code}`, связь сама не восстановится.

### 8.7 Потеря Keychain (новая машина / переустановка)

`api_secret` потерян → нельзя авторизоваться. Единственный путь: создать новый аккаунт. Старый висит «зомби». **Не делаем восстановление в MVP** — это требует email/Apple ID, что ломает zero-friction. Решим на этапе веб-морды.

### 8.8 Таймзоны

Все `hour_bucket` — **UTC**. Клиент агрегирует свою локальную статистику по UTC-часам, не по локальным. Лидерборд «за день» = последние 24 часа UTC, не «с полуночи по Москве». Упрощает на порядок и не вызывает споров «у меня уже сегодня, у тебя ещё вчера».

### 8.9 Бэкапы

`pg_dump` ежедневно в `/opt/aiuse/backups/`, ротация 7 дней. Хранятся на той же VM — слабое место (компрометация VM = компрометация бэкапов). Для MVP приемлемо (масштаб «свои люди», секреты — хэши). Offsite в Object Storage с шифрованием — фаза монетизации.

## 9. UI

### 9.1 Dropdown menu bar

Новая секция «Лидерборд» ПОСЛЕ существующих trend-sparkline'ов, ДО footer'а с `last_sync`. Использует тот же `period picker` сверху.

Содержит top-5 (включая тебя, ты подсвечен). Полный список — в Settings → «Друзья».

Состояния:
- Шаринг выключен / аккаунт не создан → секция скрыта.
- Друзей нет → подсказка «Добавь друга — поделись своим кодом или вставь чужой в [Настройки → Друзья]».
- Есть данные → top-5.
- Кэш устарел (>10 мин) → серая приписка «обновлено N минут назад».

### 9.2 Settings window

Добавляется `TabView` с тремя вкладками: «Общие» (существующее), «Аккаунт», «Друзья».

**Вкладка «Аккаунт»**:
- Состояние «не создан»: форма имя + аватарка + объяснение «зачем» + кнопка «Создать аккаунт».
- Состояние «создан»: аватарка + имя + кнопка «Изменить». Большой блок с friend_code и кнопкой копирования. Toggle «Шарить статистику» с описанием последствий. «Опасная зона» внизу: «Сгенерировать новый код» + «Удалить аккаунт» — каждая с confirm-диалогом и явным текстом последствий.

**Вкладка «Друзья»**:
- Поле «Добавить друга» с textfield для friend_code + кнопка «Добавить».
- Список «Мои друзья (N)»: аватарка + имя + текущая статистика за день + меню `⋯` с «Удалить» / «Удалить и заблокировать».
- Раскрывающийся блок «Заблокированные» (collapsed по умолчанию).

### 9.3 WidgetKit виджеты

Новый target `StatsWidget` в `project.yml`. WidgetBundle с двумя Widget'ами (юзер ставит каждый отдельно).

**PersonalStatsWidget** (`systemSmall` + `systemMedium`):
- Конфиг через `AppIntentConfiguration` (macOS 14+): `period` ∈ `today`/`last24h`/`week`/`month`, default `today`.
- Small: большая цифра токенов + period label + иконка app'а.
- Medium: цифра токенов слева + sparkline по часам (24 точки) справа.
- Источник: `App Group/my_stats.json`.

**LeaderboardWidget** (`systemLarge`):
- Конфиг: `period` ∈ `last24h`/`week`/`month`, default `last24h`. Top N фиксировано 7.
- Список с аватарками, именами, числами, иконкой «← ты» на своей строке.
- Внизу: «обновлено N мин назад».
- Источник: `App Group/leaderboard.json` + `App Group/friend_avatars/*.jpg`.

**Edge cases виджетов:**

| Условие | Поведение |
|---|---|
| main app давно не запускался | показываем stale данные с пометкой «обновлено N часов назад» |
| Прошло >24ч с последнего обновления | placeholder «открой ai-stats для обновления» с deep-link |
| Виджет вставлен до создания аккаунта (personal) | показываем локальные данные (они есть всегда) |
| Виджет вставлен до создания аккаунта (leaderboard) | placeholder «создай аккаунт в ai-stats → Настройки» + deep-link |

### 9.4 Источник данных для виджетов

| Виджет | Откуда | Кто пишет | Частота |
|---|---|---|---|
| Personal | `App Group/my_stats.json` | main app в конце sync-тика | каждые 5 мин |
| Leaderboard | `App Group/leaderboard.json` + аватарки | main app после `GET /api/leaderboard` | каждые 5 мин |

WidgetKit сам пытается просыпаться по своему расписанию (~раз в 15–30 минут), но без main app'а он только перерисует то что уже лежит в shared container.

## 10. Тестирование

### 10.1 Backend (`ai-stats-api`)

Стек: pytest + httpx AsyncClient + Postgres в Docker. **Никакого мокинга БД** — все тесты через настоящий Postgres (testcontainers / отдельная test-БД). Медленнее, зато ловит реальные баги: миграции, констрейнты, гонки, JSON-сериализацию bytea.

```
tests/
├── conftest.py
├── test_profiles.py       # CRUD, регенерация, удаление с каскадом
├── test_snapshots.py      # upsert идемпотентность, sharing_enabled=403, batch лимит
├── test_friendships.py    # симметричность, лимит 100, блокировка
├── test_blocks.py         # повторное добавление = 403, неотличимое сообщение
├── test_leaderboard.py    # SUM по period, фильтрация неактивных, is_me, сортировка
├── test_auth.py           # Bearer валидация
├── test_avatars.py        # bytea отдача, ETag
└── test_e2e_smoke.py      # полный flow Alice→Bob (см. 10.4)
```

**Критические инварианты:**

- Симметричность дружбы (одна строка, видна обоим).
- Каскады при DELETE profile (snapshots, friendships с обеих сторон, blocks с обеих сторон).
- Идемпотентность snapshot'ов (повторный POST с теми же данными → строка одна).
- Регенерация friend_code рвёт friendships, но api_secret не меняется.
- `sharing_enabled=false` фильтрует из leaderboard, профиль в `GET /api/friends` остаётся.

CI: GitHub Actions с postgres service. Workflow `test.yml`, прогон при PR в main.

### 10.2 Клиент (`ai-stats`)

Расширяется существующий `StatsAppTests` (фикстуры в `Tests/StatsAppTests/Fixtures/`).

```
Tests/StatsAppTests/
├── (существующие)
├── Sync/
│   ├── LeaderboardSyncerTests.swift
│   ├── PendingSnapshotsTests.swift
│   └── PullSyncTests.swift
├── Network/
│   └── AiuseAPIClientTests.swift  # через MockURLProtocol
├── Privacy/
│   └── SharingToggleTests.swift
└── Fixtures/
    ├── api-leaderboard-day.json
    ├── api-friends-list.json
    └── api-create-profile.json
```

**Мокаем:** HTTP (`MockURLProtocol`), Keychain (через протокол `KeychainStore` с in-memory impl).
**НЕ мокаем:** GRDB (настоящий SQLite во временном файле), файловую систему shared container.

**Критические инварианты:**

- `sharing_enabled=false` → ноль HTTP запросов из sync'а.
- Batch формируется только из изменившихся часов.
- Retry при 5xx: snapshot остаётся в pending, attempts++.
- После успешного pull — shared container содержит валидный JSON.

### 10.3 Widget extension

Юнит-тесты на чистую логику (форматирование, выбор top-N, stale-state) — в том же `StatsAppTests`. Snapshot-тестов нет в MVP. Визуальная проверка — Xcode Preview + руками на своей машине.

Чек-лист ручного тестирования виджетов (часть релизного чек-листа):
- [ ] Все три размера выглядят норм
- [ ] Конфиг period работает через long-press → Edit Widget
- [ ] Empty state (нет аккаунта)
- [ ] Stale state (>24ч без main app'а)
- [ ] Deep link открывает main app

### 10.4 E2E smoke test

Один интеграционный тест в backend, гоняется в CI:

```python
async def test_full_user_flow(client):
    alice = await create_profile(client, "Alice")
    bob = await create_profile(client, "Bob")

    await add_friend(client, bob, alice["friend_code"])
    await send_snapshot(client, alice, hour="2026-05-23T14:00:00Z", tokens_in=100, tokens_out=200)

    lb = await get_leaderboard(client, bob, period="day")
    assert lb["entries"][0]["friend_code"] == alice["friend_code"]
    assert lb["entries"][0]["tokens_total"] == 300

    await regenerate(client, alice)

    lb = await get_leaderboard(client, bob, period="day")
    assert not any(e["friend_code"] == alice["friend_code"] for e in lb["entries"])
```

### 10.5 Покрытие

Цель — критические инварианты, не процент. Если покрытие <70% потому что нет тестов на DTO-геттеры — норм. Если 95% но нет теста на каскад удаления — не норм.

## 11. Безопасность

### 11.1 Двухтокенная схема auth

- **`friend_code`** — квази-публичный, для дружбы. 10 символов base32. Юзер видит и шарит.
- **`api_secret`** — приватный, для записи на сервер. 32 случайных байта (hex или base64url). Лежит в macOS Keychain, в UI не показывается никогда. Сервер хранит `sha256(api_secret)`.

Разделение защищает от «дал ID другу — он подделывает мои snapshot'ы».

### 11.2 Регенерация vs восстановление

- Регенерация `friend_code` — есть, как защита от «утечки кода знакомым». `api_secret` не меняется.
- Восстановление `api_secret` — НЕТ в MVP. Потерял Keychain = создавай новый аккаунт.

### 11.3 Что попадает в логи / бэкапы

- `api_secret_hash` в БД и в бэкапах — это хэш, ок.
- Имена и аватарки — попадают как есть. PII минимальное (имя — что юзер сам ввёл, аватарка — что сам загрузил).
- В access-логах nginx — IP-адреса. Стандартный риск, не специфический для нашего проекта.

### 11.4 Утечки которые НЕ защищаем

- Компрометация VM → доступ ко всему серверному (БД + бэкапы). Клиентские Keychain'ы не затрагиваются. Считаем приемлемым риском масштаба.
- MITM на HTTPS — защищаем стандартным сертификатом (LE), pin'инг не делаем.
- DoS на `POST /api/snapshots` — защищаем rate limit'ом 1 req/sec/user. На уровень сети не защищаем (это работа nginx / Cloudflare если придёт).

## 12. Деплой и операции

### 12.1 Первичная настройка серверной стороны

1. Создать репо `ai-stats-api` на GitHub.
2. На VM: создать `/opt/aiuse/`, склонировать bare repo для git push, настроить post-receive хук (по шаблону `ramka`).
3. A-запись: `yc dns zone add-records --name popovs-tech-zone --record "aiuse 300 A 93.77.187.42"`.
4. Расширить SAN cert через certbot `--expand` (см. ingress README).
5. Добавить upstream и `server`-блок в `ingress/nginx.conf` для `aiuse.popovs.tech` (proxy `/api/` → backend, `/` → статика).
6. Создать `/opt/aiuse/landing/` с минимальным `index.html` (для v0.2.0 — заглушка-плейсхолдер; полный лендинг с кнопкой скачать — в v0.4.0).
7. Запустить compose: postgres с volume `/opt/aiuse/pgdata/`, api на порту 8000 в docker network `web`.
8. Прогнать миграции Alembic.
9. Добавить cron на VM: `0 3 * * * docker exec aiuse-postgres pg_dump -U aiuse aiuse | gzip > /opt/aiuse/backups/$(date +\%F).sql.gz && find /opt/aiuse/backups -mtime +7 -delete`
10. Добавить домен в Uptime Kuma.

### 12.2 Деплой обновлений

`git push prod main` в `ai-stats-api`. Post-receive хук:
1. Checkout файлов в `/opt/aiuse/`.
2. `docker compose up -d --build api` (postgres не трогаем).
3. `docker exec aiuse-api alembic upgrade head` (миграции).
4. (Если изменился `nginx.conf` для лендинга — отдельно `git push prod main` в `ingress`.)

### 12.3 Мониторинг

Uptime Kuma на `uptime.popovs.tech` уже есть. Добавляются:
- HTTPS check `https://aiuse.popovs.tech/` (200).
- HTTPS check `https://aiuse.popovs.tech/api/health` (требует новый health endpoint в FastAPI: `GET /api/health` → `{"status": "ok"}`).

### 12.4 Расходы

Дополнительные расходы по сравнению с текущей VM: нулевые. Postgres контейнер на той же VM, лендинг — статика, бэкапы — локальные. При росте >5000 юзеров — переезд Postgres на managed (~1000₽/мес в YC) или отдельная VM.

## 13. Чек-лист готовности к v0.2.0

(самый рисковый этап — серверный фундамент без UI лидерборда)

- [ ] Новый репо `ai-stats-api`, FastAPI + SQLAlchemy 2.0 + Alembic skeleton
- [ ] Docker-compose с api + postgres (по шаблону `ramka`/`tracker`)
- [ ] Миграции для всех 4 таблиц
- [ ] Эндпоинты: `POST /profiles`, `PATCH /profiles/me`, `POST /profiles/me/regenerate-friend-code`, `DELETE /profiles/me`, `POST /snapshots`, `GET /health`
- [ ] Auth middleware (Bearer → user lookup через sha256-hash)
- [ ] Тесты на pytest + Postgres контейнер (test_profiles, test_snapshots, test_auth)
- [ ] Поддомен `aiuse.popovs.tech`: A-запись, расширение SAN cert, nginx upstream
- [ ] Лендинг-заглушка по `aiuse.popovs.tech/` (одна страница «coming soon» — полноценный лендинг в v0.4.0)
- [ ] Cron `pg_dump` в `/opt/aiuse/backups/` с ротацией 7 дней
- [ ] Uptime Kuma checks для `/` и `/api/health`
- [ ] Клиент: новый модуль `Network/AiuseAPIClient.swift`
- [ ] Клиент: модуль `Storage/KeychainStore.swift` для api_secret
- [ ] Клиент: расширение `Storage/Models.swift` + GRDB-миграция для `my_profile`, `pending_snapshots`
- [ ] Клиент: `Sync/SnapshotSyncer.swift` интегрируется в существующий sync-тик
- [ ] Клиент: новая вкладка «Аккаунт» в Settings (через TabView)
- [ ] Тесты клиента: `SnapshotSyncerTests`, `AiuseAPIClientTests` с MockURLProtocol
- [ ] E2E smoke-тест в backend (Alice создаёт, Alice шлёт snapshot, snapshot в БД)
- [ ] Запись в CHANGELOG.md (русская, Keep a Changelog)
- [ ] README с описанием серверной части и опциональностью лидерборда (раздел «приватность»)

## 14. Открытые вопросы

Ничего блокирующего на момент написания спека. Возможные уточнения по ходу:

- Конкретный формат отображения `friend_code` в UI (`XK7P-3M9Q-2A` vs `XK7P3M9Q2A` vs другой) — деталь, решим в момент верстки.
- Точная вёрстка лендинга — пока заглушка со ссылкой, дизайн → отдельный спек если понадобится.
- Стратегия миграции при breaking changes в API (версионирование `/api/v1/` vs in-place) — отложено, решим когда понадобится первый breaking change.
