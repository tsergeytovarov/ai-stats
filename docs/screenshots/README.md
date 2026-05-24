# Скриншоты

Куда заливать кадры для README + release notes + tg-постов.

## Каноничный набор для v0.4.x

Имена файлов фиксированные — на них ссылается корневой `README.md`.

| Файл | Что снять |
|---|---|
| `menubar-capsule.png` | Capsule в menu bar — крупный план, видна цена и ember-иконка |
| `popover-ai.png` | Popover открыт на секции «AI» (период «Д») |
| `popover-github.png` | Popover на секции «GitHub», виден sparkline и top-репы |
| `popover-leaderboard.png` | Popover на «Друзья» — со стрелками ▲/▼/NEW (см. `scripts/seed-demo-leaderboard.py`) |
| `widget-small.png` | Small widget на десктопе |
| `widget-medium.png` | Medium widget |
| `widget-large.png` | Large widget с лидербордом |
| `settings-general.png` | Settings → Общие — видна галочка «Запускать при входе в систему» |
| `settings-account.png` | Settings → Аккаунт — со своим friend_code |

## Как снять popover-leaderboard с динамикой

В живой БД у твоих друзей нет `previous_rank` → стрелок ▲/▼ не видно. Скрипт подсаживает поля так, чтобы каждый ranged-кейс был представлен.

```bash
# 1. Закрыть Burn (иначе перетрёт cache следующим sync'ом)
killall Burn

# 2. Бэкап текущей БД + посев previous_rank
./scripts/seed-demo-leaderboard.py --backup --seed

# 3. Запустить app
open /Applications/Burn.app

# 4. Сразу (~15 сек до следующего sync'а) сделать скриншот.
#    Если не успел — закрой app, повтори с шага 2.

# 5. Восстановить нормальное состояние БД
./scripts/seed-demo-leaderboard.py --restore
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
