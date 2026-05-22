# ai-stats

macOS menu bar app для статистики использования AI-агентов и активности на GitHub.

Статус: **v0.1 — personal MVP**.

## Что показывает

- Сегодняшние / недельные / месячные траты по AI-агентам (через `ccusage`).
- Сегодняшние / недельные / месячные коммиты по всем твоим репам (через GitHub GraphQL).
- 14-дневный sparkline-тренд AI-трат.

## Требования

- macOS 14 Sonoma или новее
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
  "sync_interval_minutes": 5,
  "ccusage_command": ["npx", "-y", "ccusage@latest"],
  "enabled_providers": ["claude", "codex"]
}
```

## Где живут файлы

- DB: `~/Library/Application Support/ai-stats/stats.db`
- Config: `~/.config/ai-stats/config.json`

## Спек и план

- Дизайн: [docs/superpowers/specs/2026-05-22-ai-stats-design.md](docs/superpowers/specs/2026-05-22-ai-stats-design.md)
- План реализации v0.1: [docs/superpowers/plans/2026-05-22-ai-stats-v0.1.md](docs/superpowers/plans/2026-05-22-ai-stats-v0.1.md)

## Лицензия

MIT (запланировано к v1.0).
