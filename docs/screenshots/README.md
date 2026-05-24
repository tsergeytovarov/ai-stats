# Скриншоты

Куда заливать кадры для README + release notes + tg-постов.

## Каноничный набор для v0.4.x

Имена файлов фиксированные — на них ссылается корневой `README.md`.

| Файл | Что снять |
|---|---|
| `popover-ai.png` | Popover, секция «AI», период «Неделя» |
| `popover-ai-month.png` | Popover, секция «AI», период «Месяц» |
| `popover-github.png` | Popover, секция «GitHub», виден sparkline и top-репы |
| `popover-leaderboard.png` | Popover на «Друзья» — со стрелками ▲/▼/NEW (см. `scripts/seed-demo-leaderboard.py`) |
| `widgets-overview.png` | Все три виджета вместе на десктопе (Small + Medium + Large) |
| `settings-account.png` | Settings → Аккаунт — со своим friend_code |

## Как снять popover-leaderboard с динамикой

В живой БД у твоих друзей нет `previous_rank` → стрелок ▲/▼ не видно. Плюс fake-друзья без шаринга имеют tokens_total=0 — выглядит плоско. Скрипт подсаживает оба поля так, чтобы каждый кейс был представлен (▲N / ▼N / NEW / без изменений + реалистичные суммы токенов).

**Workflow:**

```bash
# 1. Включить demo_mode в config — иначе при старте Burn пойдёт за свежим
#    лидербордом в aiuse-сервер и затрёт seed за пару секунд.
#    Открой ~/.config/ai-stats/config.json и поставь:
#        "demo_mode": true
#    (поле необязательное, default false)

# 2. Закрыть Burn полностью
killall Burn

# 3. Бэкап текущей БД + seed previous_rank/tokens
./scripts/seed-demo-leaderboard.py --backup --seed

# 4. Запустить app — в demo_mode он НЕ ходит на aiuse-сервер, seed жив
open /Applications/Burn.app

# 5. Делать скриншоты сколько надо — никто cache не трогает

# 6. Когда закончил: restore + убрать demo_mode из config
./scripts/seed-demo-leaderboard.py --restore
# и руками верни "demo_mode": false (или удали поле)
```

Что должно быть видно после `--seed`:

- rank 1 (я) — ▲1 (поднялся с 2-го)
- rank 2 — ▼1 (упал с 1-го)
- rank 3 — без стрелки (не изменился)
- rank 4 — ▲2 (поднялся с 6-го)
- rank 5 — `NEW` (не было в прошлом периоде)
- rank 6 — ▼2 (упал с 4-го)

## Размеры

- Popover: native 400×560. Снимай через cmd+shift+4 + space + click на popover окно — получишь чистый PNG без хрома.
- Widget: cmd+shift+4 + space → клик по widget'у в Notification Center / desktop.
- Menu bar capsule: cmd+shift+4 → выделить полоску menu bar в районе capsule.

## Сжатие

Перед коммитом сжать через `pngquant` (~70% size reduction):

```bash
brew install pngquant
pngquant --quality=80-95 --skip-if-larger --ext=.png --force docs/screenshots/*.png
```
