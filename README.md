# Burn

macOS menu bar app для статистики использования AI-агентов и активности на GitHub.

Статус: **v0.1 — personal MVP**.

> Бывший `ai-stats`. Внутренние идентификаторы (bundle ID `com.sergeytovarov.aistats`, пути `~/.config/ai-stats/`, `~/Library/Application Support/ai-stats/`, репозиторий и Xcode-проект) пока не переименованы — это запланировано под v1.0 cleanup. На пользователя смотрит уже **Burn**: иконка в Dock, имя в Spotlight/Cmd+Tab, capsule в menu bar.

**Визуал:** редизайн под Apple Liquid Glass — pink+cyan палитра с внутренним brand-градиентом (не зависит от обоев), floating glass island для переключения категорий и периода, виджеты на едином visual language.

## Что показывает

- Сегодняшние / недельные / месячные траты по AI-агентам через `ccusage` + собственный pricing table (USD за 1M токенов на момент мая 2026, вкл. claude-opus/sonnet/haiku 4.x и gpt-5.x).
- Сегодняшние / недельные / месячные коммиты по всем твоим репам через GitHub GraphQL.
- Lines added/deleted по твоим коммитам через GitHub Contributor Stats API (недельная гранулярность).
- 14-дневный sparkline-тренд AI-трат.
- Виджеты на десктопе (Small / Medium / Large): сумма за выбранный период с дельтой vs прошлый период; в Medium — top-моделей; в Large — ещё и лидерборд друзей с дельтой ранга.

## Известные ограничения

- **LOC отстают.** GitHub Contributor Stats API считается лениво на серверной стороне. На «холодном» репо первый запрос отвечает 202 + триггерит фоновое вычисление, которое **может занимать от 30 секунд до нескольких часов**. Наш фетчер ждёт до ~46с на репо и в случае таймаута скипает — данные подтянутся при следующем sync'е (раз в 15 мин по умолчанию). После пары часов работы app'а LOC заполнятся.
- **GitHub PAT scope:** для приватных репов нужен полный `repo`. С `public_repo` только публичные.
- **ChatGPT/Claude.ai web** не поддерживаются — у них нет публичного API использования. Только CLI-агенты (Claude Code, Codex CLI) через [ccusage](https://ccusage.com).
- **$ это «API-equivalent».** Реально на подписках $20-200/мес ты платишь меньше; цифра показывает сколько стоила бы та же нагрузка по API.

## Требования

- macOS 26 Tahoe или новее
- Xcode 15+ для сборки
- Node.js (для `npx ccusage`) или [bun](https://bun.sh/) (`bunx ccusage`)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Сборка

```bash
xcodegen generate
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Release -derivedDataPath build/
open build/Build/Products/Release/StatsApp.app
```

Или открыть `ai-stats.xcodeproj` в Xcode и собрать через GUI.

## Конфиг

При первом запуске app создаст `~/.config/ai-stats/config.json` — заполни `github_token` (PAT с scope `repo` + `read:user`), `github_login` и перезапусти. AI-часть работает без токена.

```json
{
  "github_token": "ghp_xxx",
  "github_login": "your-username",
  "sync_interval_minutes": 15,
  "ccusage_command": ["npx", "-y", "ccusage@latest"],
  "enabled_providers": ["claude", "codex"]
}
```

Менять можно — но имей в виду, что каждый sync запускает `npx ccusage` процесс на 10-30 секунд.

## Где живут файлы

- DB: `~/Library/Application Support/ai-stats/stats.db`
- Config: `~/.config/ai-stats/config.json`

## Спек и план

- Дизайн: [docs/superpowers/specs/2026-05-22-ai-stats-design.md](docs/superpowers/specs/2026-05-22-ai-stats-design.md)
- План реализации v0.1: [docs/superpowers/plans/2026-05-22-ai-stats-v0.1.md](docs/superpowers/plans/2026-05-22-ai-stats-v0.1.md)

## Лицензия

MIT (запланировано к v1.0).
