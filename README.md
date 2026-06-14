# Burn

[![Release](https://img.shields.io/github/v/release/tsergeytovarov/ai-stats?label=release&color=ff2d6d)](https://github.com/tsergeytovarov/ai-stats/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-26%2B-blue)](https://www.apple.com/macos/)
[![Install](https://img.shields.io/badge/install-brew%20tap%20tsergeytovarov%2Ftap-orange?logo=homebrew)](https://github.com/tsergeytovarov/homebrew-tap)
[![License](https://img.shields.io/github/license/tsergeytovarov/ai-stats)](LICENSE)

macOS menu bar app для статистики использования AI-агентов и активности на GitHub.

```bash
brew tap tsergeytovarov/tap
brew trust --cask tsergeytovarov/tap/ai-stats
brew install --cask ai-stats
```

> **Статус:** personal MVP. Внутренние идентификаторы (bundle ID `com.sergeytovarov.aistats`, пути `~/.config/ai-stats/`) пока не переименованы под Burn — это запланировано к v1.0. На пользователя смотрит уже **Burn**: capsule в menu bar и имя Burn в Spotlight. Иконки в Dock и в Cmd+Tab нет — это menu-bar-only приложение.

**Визуал:** редизайн под Apple Liquid Glass — pink+cyan палитра с внутренним brand-градиентом (не зависит от обоев), floating glass island для переключения категорий и периода, виджеты на едином visual language.

## Что показывает

- Сегодняшние / недельные / месячные траты по AI-агентам через `ccusage` + собственный pricing table (USD за 1M токенов, актуально на 2026 год, вкл. claude-opus/sonnet/haiku 4.x и gpt-5.x).
- Сегодняшние / недельные / месячные коммиты по всем твоим репам через GitHub GraphQL.
- Lines added/deleted по твоим коммитам через GitHub Contributor Stats API (недельная гранулярность).
- 14-дневный sparkline-тренд AI-трат.
- Виджеты на десктопе (Small / Medium / Large): сумма за выбранный период с дельтой vs прошлый период; в Medium — top-моделей; в Large — ещё и лидерборд друзей с дельтой ранга.

## Скриншоты

**Popover** — клик по capsule в menu bar открывает дроп с детализацией. Floating island внизу переключает категорию (AI / GitHub / Друзья) и период (День / Неделя / Месяц):

| AI · неделя | AI · месяц | GitHub · день |
|---|---|---|
| ![ai week](docs/screenshots/popover-ai.png) | ![ai month](docs/screenshots/popover-ai-month.png) | ![github](docs/screenshots/popover-github.png) |

**Лидерборд друзей** — секция «Друзья» в popover'е, со стрелками ▲/▼/NEW для динамики ранга:

![leaderboard](docs/screenshots/popover-leaderboard.png)

**Виджеты** на десктопе — Small, Medium, Large вместе:

![widgets overview](docs/screenshots/widgets-overview.png)

**Settings → Аккаунт** — свой friend-код, аватарка, шаринг статистики:

![account](docs/screenshots/settings-account.png)

## Требования

- macOS 26 Tahoe или новее.
- Node.js (для `npx ccusage`) или [bun](https://bun.sh/) (`bunx ccusage`) — иначе не будет AI-статистики.

## Установка

### Через Homebrew Cask (рекомендуется)

```bash
brew tap tsergeytovarov/tap
brew trust --cask tsergeytovarov/tap/ai-stats
brew install --cask ai-stats
```

`brew` скачает DMG, проверит SHA256, поставит `Burn.app` в `/Applications/`. Никакого Gatekeeper warning'а — cask автоматически снимает quarantine-атрибут.

> **Шаг `brew trust`.** Homebrew вводит обязательный trust для сторонних (не official) тапов: opt-out `HOMEBREW_NO_REQUIRE_TAP_TRUST` помечен deprecated и будет удалён в одном из следующих релизов. `brew trust --cask tsergeytovarov/tap/ai-stats` доверяет каск один раз (запись в `~/.homebrew/trust.json`); `brew untrust` отменяет. Команда появилась в Homebrew 5.1.15 — на более старых brew её ещё нет, там шаг можно пропустить.

Обновления:

```bash
brew upgrade --cask ai-stats
```

### Прямым скачиванием DMG

1. Скачать последний DMG из [Releases](https://github.com/tsergeytovarov/ai-stats/releases/latest).
2. **Важно:** при первом открытии macOS покажет alert «Apple не может проверить разработчика» — приложение подписано ad-hoc, без Apple Developer ID. Чтобы запустить:
   - **Способ 1:** Right-click на `Burn.app` в Finder → Open → Open. Один раз.
   - **Способ 2 (CLI):** `xattr -dr com.apple.quarantine /Applications/Burn.app`

После этого `Burn.app` запускается двойным кликом как обычно.

## Первый запуск

Запусти Burn из `/Applications` или через Spotlight. Иконки в Dock нет — приложение живёт только в menu bar: ищи capsule с суммой трат в правом верхнем углу экрана. Клик по нему открывает popover с детализацией.

При первом старте Burn создаёт `~/.config/ai-stats/config.json` и показывает алерт «Конфиг создан» с кнопкой «Открыть конфиг». GitHub-токен в конфиге заполнять необязательно — статистика по AI-агентам работает и без него, а для GitHub и синка удобнее войти через GitHub (см. [Аккаунт и вход](#аккаунт-и-вход)).

## Разрешения и пароли

Burn не в App Sandbox и не просит доступ к камере, микрофону или контактам. Что реально потребуется:

### Пароль на старте (Keychain)

При первом запуске после установки (и после каждого апдейта) macOS показывает диалог «`Burn` хочет получить доступ к `Local Items` keychain — введите пароль». Жми **Always Allow** один раз — больше не спросит до следующего апдейта.

Причина: app подписан ad-hoc (без $99/год Apple Developer ID). macOS определяет «доверенность» app'а через подпись бинаря; для ad-hoc это означает, что **любая пересборка** = новая identity = invalidated trust → новый prompt. Что сделано, чтобы prompt'ов было меньше:

- Оба секрета (aiuse api_secret + GitHub PAT) лежат в одном Keychain item'е (`tech.popovs.aistats.secrets`). До v0.4.0 было два item'а → два prompt'а. Теперь один на запуск.
- Все Keychain reads делаются разово на старте + кешируются в памяти процесса. Синки каждые 15 минут Keychain не дёргают.

Полностью без prompt'ов — только если подписать app настоящим Developer ID cert'ом, что упирается в Apple Developer Program ($99/год + иностранная карта для оплаты из РФ).

### Доступ к файлам

Burn читает свой конфиг (`~/.config/ai-stats/`), локальную БД и историю CLI-агентов, которую считает `ccusage`. Ничего из этого не требует системного prompt'а. Без логина на сервер не уходит ничего (см. [Приватность](#приватность)).

### Подтверждение автозапуска

Если включишь «Запускать при входе» — macOS может попросить разрешение в System Settings → General → Login Items (см. [Автозапуск](#автозапуск)).

## Аккаунт и вход

Ручной PAT больше не обязателен. Settings → «Аккаунт» → **«Войти через GitHub»** проводит OAuth-вход: откроется браузер, авторизуешься на GitHub, и Burn вернётся по ссылке `burn://`. Токен для коммитов/LOC выдаётся автоматически (вместо ручного `github_token`), заодно создаётся аккаунт для синка. PAT через `config.json` остаётся как legacy-путь.

- **Приватные репы.** По умолчанию запрашиваются только публичные. Нужны приватные — отметь «Включая приватные репозитории» перед входом (GitHub попросит scope `repo`).
- **Синк между устройствами.** Залогинься тем же GitHub на втором компьютере — статистика суммируется автоматически (учёт по устройствам на сервере). Отдельных «привязок» делать не надо.

## Друзья

Лидерборд друзей строится из людей, которых вы добавили друг к другу по коду.

1. **Свой код** — Settings → «Аккаунт» → «Твой код для друзей» (вид `XK7P-3M9Q-2A`). Кнопка «Копировать» кладёт его в буфер **с дефисами** — отправь другу как есть.
2. **Добавить друга** — Settings → «Друзья» → вставь его код в поле «Код» и нажми «Добавить». Дефисы, пробелы и регистр не важны, код нормализуется.
3. **Взаимность.** Друг должен добавить тебя так же — связь двусторонняя, иначе в лидерборде вы друг друга не увидите.

В списке друзей у каждого видно имя, код и пометку «шаринг выключен», если человек не делится статистикой. Меню `⋯` у строки — «Удалить» или «Удалить и заблокировать». Максимум — 100 друзей.

Сменить свой код можно в «Аккаунт» → «Сгенерировать новый код», но тогда все текущие друзья отвалятся и придётся обменяться кодами заново. История использования при этом сохраняется.

## Приватность

Без логина Burn работает полностью локально — на сервер не уходит ничего. Логин нужен только для синка и лидербордов. Два тумблера в Settings → «Аккаунт»:

- **Шарить статистику.** Выключено — ты не отправляешь свои цифры и не видишь чужие (лидерборд друзей для тебя пустой). Включено — отправляешь снапшоты и видишь друзей. После входа через GitHub этот тумблер **выключен по умолчанию** — включи его, если хочешь попасть в лидерборд.
- **Показывать в публичном лидерборде.** Выключен по умолчанию. Включив, светишь handle, аватар и цифры публично на сайте. Лидерборд друзей при этом остаётся приватным, внутри приложения.

## Виджет

Burn даёт виджеты Small / Medium / Large. Добавить: right-click по рабочему столу → «Редактировать виджеты» (или открой Notification Center → «Изменить виджеты»), найди **Burn**, перетащи нужный размер. Период (День / Неделя / Месяц) меняется в настройках виджета — right-click по нему → «Изменить виджет».

- **Small** — сумма за период с дельтой vs прошлый период.
- **Medium** — то же плюс топ моделей.
- **Large** — ещё и лидерборд друзей с дельтой ранга.

## Автозапуск

Settings → «Общие» → «Запускать Burn при входе в систему». Toggle регистрирует app в macOS Login Items через `SMAppService.mainApp`; управлять можно и из System Settings → General → Login Items.

При первом включении macOS может попросить approval — тогда переключатель отобьёт обратно, и в системных настройках появится pending-запись, которую надо разрешить руками.

## Если что-то не так

- **macOS просит пароль при каждом запуске.** Это ad-hoc подпись, не баг — см. [Разрешения и пароли](#разрешения-и-пароли). Лечится только настоящим Developer ID.
- **Лидерборд пустой или ошибка доступа.** После входа через GitHub «Шарить статистику» выключено по умолчанию — включи в Settings → «Аккаунт». Плюс друзья должны быть добавлены взаимно и тоже шарить статистику.
- **AI-траты по нулям.** Нужен Node.js (или bun) в PATH — Burn зовёт `npx ccusage`. Проверь `npx ccusage` в терминале. Считаются только CLI-агенты (Claude Code, Codex CLI); web ChatGPT/Claude.ai — нет.
- **Коммиты есть, а LOC пустые.** GitHub считает LOC лениво: на «холодном» репо первый запрос уходит в фон и тянется от 30 секунд до часов. Подтянутся при следующих синках.
- **GitHub-статистики нет вообще.** Без логина и без `github_token` Burn не видит твой GitHub — войди через GitHub в Settings → «Аккаунт».

---

## Конфиг (справочник)

При первом запуске app создаст `~/.config/ai-stats/config.json` (с правами `0600`). Заполни `github_token` (PAT с scope `repo` + `read:user`), `github_login` и перезапусти. AI-часть работает без токена.

```json
{
  "github_token": "ghp_xxx",
  "github_login": "your-username",
  "sync_interval_minutes": 15,
  "ccusage_command": ["npx", "-y", "ccusage@20"],
  "enabled_providers": ["claude", "codex"],
  "aiuse_api_base_url": "https://aiuse.popovs.tech/api"
}
```

**Где живёт PAT.** При старте app перенесёт `github_token` в Keychain (`tech.popovs.aistats.secrets`, account `combined-v1` — туда же кладётся aiuse api_secret, оба в одном JSON-blob'е) и затрёт поле в JSON — plaintext-токен не остаётся на диске. Менять токен → впиши новое значение, перезапусти, повторится миграция. Удалить — Keychain Access → найди запись `tech.popovs.aistats.secrets`.

**Безопасность `aiuse_api_base_url`.** Только `https://`. Любая другая схема — app откажется стартовать (Bearer-токен из Keychain не должен утечь plain-text'ом).

**Версия `ccusage` запиннена** (`ccusage@20`, не `@latest`) — supply-chain protection. Менять руками когда выйдет major 21+ и захочешь обновиться. `npx -y` всё ещё резолвит patch'и внутри 20.x.x.

Менять остальные поля можно — но имей в виду, что каждый sync запускает `npx ccusage` процесс на 10-30 секунд.

## Где живут файлы

- DB: `~/Library/Group Containers/group.com.sergeytovarov.aistats/stats.db` (app-group-контейнер — базу шарит виджет)
- Config: `~/.config/ai-stats/config.json`
- Keychain: `tech.popovs.aistats.secrets` / `combined-v1` (aiuse + github в одном JSON)

## Известные ограничения

- **LOC отстают.** GitHub Contributor Stats API считается лениво на серверной стороне. На «холодном» репо первый запрос отвечает 202 + триггерит фоновое вычисление, которое **может занимать от 30 секунд до нескольких часов**. Наш фетчер ждёт до ~46с на репо и в случае таймаута скипает — данные подтянутся при следующем sync'е (раз в 15 мин по умолчанию). После пары часов работы app'а LOC заполнятся.
- **GitHub PAT scope:** для приватных репов нужен полный `repo`. С `public_repo` только публичные.
- **ChatGPT/Claude.ai web** не поддерживаются — у них нет публичного API использования. Только CLI-агенты (Claude Code, Codex CLI) через [ccusage](https://ccusage.com).
- **$ это «API-equivalent».** Реально на подписках $20-200/мес ты платишь меньше; цифра показывает сколько стоила бы та же нагрузка по API.

## Для разработчиков

Требования для сборки: Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), [create-dmg](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`, только если собираешь DMG).

### Сборка из исходников

```bash
xcodegen generate
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Release -derivedDataPath build/
open build/Build/Products/Release/Burn.app
```

Или открыть `ai-stats.xcodeproj` в Xcode и собрать через GUI.

Готовый DMG:

```bash
./scripts/build-dmg.sh
# build/burn-X.Y.Z.dmg + SHA256 в выводе
```

### Спек и план

- Дизайн: [docs/superpowers/specs/2026-05-22-ai-stats-design.md](docs/superpowers/specs/2026-05-22-ai-stats-design.md)
- План реализации v0.1: [docs/superpowers/plans/2026-05-22-ai-stats-v0.1.md](docs/superpowers/plans/2026-05-22-ai-stats-v0.1.md)

## Лицензия

[MIT](LICENSE). Copyright © 2026 Sergey Tovarov.
