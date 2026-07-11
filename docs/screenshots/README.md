# Скриншоты

Куда заливать кадры для README + release notes + tg-постов.

## Каноничный набор

Имена файлов фиксированные — на них ссылается корневой `README.md`.

| Файл | Что снять |
|---|---|
| `popover-ai.png` | Popover, вкладка «Расходы», период «Неделя» |
| `popover-ai-month.png` | Popover, вкладка «Расходы», период «Месяц» |
| `popover-analytics.png` | Popover, вкладка «Аналитика» — советник, топ моделей по токенам, шпаргалка |
| `widgets-overview.png` | Все три виджета вместе на десктопе (Small + Medium + Large) |
| `settings-account.png` | Settings → Аккаунт — вход через GitHub |

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
