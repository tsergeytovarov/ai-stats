# Redesign: Liquid Glass + Neon Duo (B2)

Дата: 2026-05-23
Статус: draft, ждёт ревью.

## TL;DR

Полная переделка визуального стиля ai-stats под Apple Liquid Glass (macOS 26 Tahoe). Палитра — pink + cyan дуэт на тёмном стекле с внутренним brand-градиентом, не зависящим от обоев. Композиция меняется: переключатели категории и периода объединены в один floating glass island внизу поповера. Виджеты переезжают на тот же визуальный язык.

Функциональность не меняется. Меняется только presentation layer (`DropdownView.swift`, `StatsWidget/Views/*`, новый `StatusItemController.swift` оформление).

## Цели

- Single distinctive visual identity, узнаваемая на скриншоте и работающая на любых обоях.
- Native Liquid Glass — настоящие `NSGlassEffectView` / `.glassEffect()`, а не имитация.
- Меньше chrome, больше данных. Один floating control surface вместо двух segmented pickers.
- Виджеты на том же языке, что и поповер.

## Не-цели

- Перепиливание data layer, sync, pricing, GitHub API. Только UI.
- Light mode. Делаем dark-only (вообще приложение data-heavy и dark смотрится лучше; light оставляем на потом).
- Анимации перехода между вкладками — позже.
- Кастомизация палитры пользователем — позже.

## Технологический выбор

- **Минимум macOS = 26 Tahoe.** В README обновить с 14 Sonoma. На старших OS работать не будет. Это personal MVP, единственный пользователь — автор, поэтому фолбэки не делаем.
- SwiftUI везде где можно. AppKit только там, где он уже есть (`NSStatusItem`).
- Liquid Glass через `.glassEffect()` (SwiftUI Tahoe API) на surface'ах. Кастомные blur слои не нужны.

---

## Визуальное направление

**B2 — Neon Liquid.** Pink + cyan дуэт. Глянцевое тёмное стекло. Главное число — gradient text (белый → светло-розовый). Дельта — cyan с лёгким glow. Selection — pink с pink-glow shadow.

Не Pure Tahoe (слишком сдержанно для personal-tool), не Editorial Bronze (слишком серьёзно). Тот самый дофамин, на котором текущий розовый уже сидит — но осмысленный, с парой и иерархией.

---

## Design tokens

### Colors

| Token | Value | Использование |
|---|---|---|
| `brand.pink` | `#FF2D6D` | primary brand, активный селекшен (категория), главное число (часть gradient) |
| `brand.pink.light` | `#FF5FA0` | top gradient stop для главного числа и активных пилюль |
| `brand.cyan` | `#00B8E6` → `#4FE6FF` | secondary brand, дельта, активный период, GitHub-данные, sparkline-GitHub |
| `surface.base` | `rgba(20,8,30,0.55)` | базовая подложка стекла (видно сквозь blur) |
| `surface.tint.pink` | `radial-gradient(60% 60% at 15% 0%, rgba(255,45,109,0.42), transparent 60%)` | overlay top-left |
| `surface.tint.cyan` | `radial-gradient(70% 70% at 100% 100%, rgba(0,212,255,0.32), transparent 60%)` | overlay bottom-right |
| `text.primary` | `#FFFFFF` | основной текст |
| `text.secondary` | `rgba(255,255,255,0.7)` | метаданные |
| `text.muted` | `rgba(255,255,255,0.5)` | sync timestamp, лейблы 4-го уровня |
| `success` | `#00FF9D` | редко: положительная дельта в случаях когда cyan не подходит |
| `danger` | `#FF453A` | отрицательная дельта, ошибки |
| `border.glass` | `rgba(255,255,255,0.22)` | edge stroke поверхности |
| `divider.subtle` | `rgba(255,255,255,0.08)` | разделители внутри карточек |

### Typography

Шрифты — system только (SF Pro Display + SF Pro Text).

| Token | Spec | Использование |
|---|---|---|
| `display.xxl` | SF Pro Display 44pt / 700 / -0.025em | главное число поповера ($ или count) |
| `display.xl` | SF Pro Display 46pt / 700 / -0.025em | Large widget hero |
| `display.l` | SF Pro Display 38pt / 700 / -0.025em | Medium widget hero |
| `display.m` | SF Pro Display 30pt / 700 / -0.025em | Small widget hero |
| `unit.l` | SF Pro Display 18pt / 600 | "коммитов" рядом с числом 28 |
| `delta` | SF Pro Text 12-13pt / 600 | "▲ +$389.69 vs вчера" |
| `body` | SF Pro Text 12-13pt / 400-500 | rows, list items |
| `caption` | SF Pro Text 11pt / 500-590 | metadata, friend rows |
| `crumb` | SF Pro Text 10-11pt / 600 / uppercase / +0.1em tracking | "AI · СЕГОДНЯ" |
| `lbl` | SF Pro Text 9-10pt / 590 / uppercase / +0.12em tracking | section labels ("ТОП МОДЕЛЕЙ") |
| `pill.body` | SF Pro Text 11pt / 590 | "AI", "GitHub", "Друзья" в islands |
| `pill.period` | SF Pro Text 10pt / 590 | "Д", "Н", "М" |

Числа всегда `.font(.system(...).monospacedDigit())` для табулярного выравнивания.

### Spacing

4pt grid. Common spacings: `4 / 6 / 8 / 12 / 14 / 16 / 18 / 22 / 32`.

| Token | Value |
|---|---|
| `pad.surface` | 14-18pt — внутренний padding surface |
| `gap.section` | 12pt — между блоками |
| `gap.row` | 4pt — между строками списка |
| `island.bottom-offset` | 14-16pt |
| `island.padding` | 4pt (между внешней рамкой и пилюлями) |
| `content.bottom-clearance` | 76-78pt — резерв под floating island |

### Radii

| Token | Value | Использование |
|---|---|---|
| `radius.surface` | 22pt | поповер, виджет |
| `radius.island` | 999pt | floating island (capsule) |
| `radius.pill` | 999pt | пилюли категории и периода |
| `radius.button` | 9pt | sync/settings tile |
| `radius.field` | 8-10pt | поля настроек |

### Shadows + glass

| Token | Spec |
|---|---|
| `glass.blur` | 40pt blur + 180% saturate (через `.glassEffect()`) |
| `glass.island.blur` | 28pt blur + 160% saturate (плотнее, чтобы остров читался отдельно) |
| `shadow.surface` | `0 16-24pt 32-50pt rgba(0,0,0,0.55-0.6)` |
| `shadow.island` | `0 12pt 32pt rgba(0,0,0,0.65)` + glow `0 0 28pt rgba(255,45,109,0.14)` |
| `shadow.pill.active.pink` | `0 4pt 12pt rgba(255,45,109,0.45)` + `inset 0 1pt 0 rgba(255,255,255,0.35)` |
| `shadow.pill.active.cyan` | `0 2pt 8pt rgba(0,212,255,0.45)` + `inset 0 1pt 0 rgba(255,255,255,0.4)` |
| `edge.highlight.top` | `inset 0 1pt 0 rgba(255,255,255,0.4-0.45)` — белый блик сверху |
| `edge.highlight.bottom` | `inset 0 -1pt 0 rgba(0,212,255,0.18-0.2)` — cyan reflection снизу |

---

## Material system: 3-layer surface

Каждая «карточка» (поповер, виджет) — это **3 слоя**:

1. **Base glass** — `.glassEffect()` поверх фона. Tahoe рендерит refraction, edge highlights, реакцию на bg.
2. **Brand overlay** — `LinearGradient` или `ZStack { RadialGradient pink top-left; RadialGradient cyan bottom-right }` с opacity ~0.4. Этот слой даёт идентичность независимо от обоев.
3. **Content** — все view'хи поверх.

```swift
ZStack {
    Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))

    LinearGradient(
        gradient: Gradient(stops: [
            .init(color: .brand.pink.opacity(0.42), location: 0),
            .init(color: .clear, location: 0.6)
        ]),
        startPoint: .topLeading,
        endPoint: .center
    )
    .blendMode(.plusLighter)

    RadialGradient(...) // cyan bottom-right
    .blendMode(.plusLighter)

    content
}
.clipShape(RoundedRectangle(cornerRadius: 22))
```

(псевдокод — точные API уточняются по Tahoe doc'ам в момент имплементации)

---

## Components

### Surface (общая поверхность)

Применяется ко всем «карточкам». Параметры: `cornerRadius`, `tintIntensity` (0-1), `showIslandClearance` (bool — резервирует 76pt снизу под floating island).

### FloatingIsland

Полупрозрачная капсула, прибитая к низу surface через `bottom: 14pt`. Внутри — горизонтальная HStack:

```
[ AI ] [ GitHub ] [ Друзья ] | [ Д ][ Н ][ М ]
```

- Категория-пилюли: pink active, белые-неактивные на opacity 0.6.
- Разделитель `width: 0.5pt, height: 18pt, color: rgba(255,255,255,0.18)`.
- Period segment: cyan active, mini-capsule.
- Тап по пилюле меняет category. Свайп влево/вправо по острову — то же. (Не первый приоритет.)

### CategoryPill

```
state:    inactive | active
content:  text
padding:  7pt vertical, 11-12pt horizontal
font:     SF Pro Text 11pt / 590
active:   linear-gradient(180deg, brand.pink.light, brand.pink) + shadow.pill.active.pink
inactive: opacity 0.6, color white
```

### PeriodSegment

Mini-capsule с 3 пилюлями (Д/Н/М).
- Background капсулы: `rgba(255,255,255,0.06)`.
- Active: linear-gradient cyan + `shadow.pill.active.cyan`, цвет текста `#00282E` (dark на cyan).
- Inactive: opacity 0.55, color white.

### SyncIconButton

Квадрат `28×28pt`, radius `9pt`, fill `rgba(255,255,255,0.08)`, stroke `0.5pt rgba(255,255,255,0.12)`. Иконка SF Symbol `15pt`.
- Hover: fill → `rgba(255,255,255,0.12)`.
- Active (pressed): fill → `rgba(255,255,255,0.18)`.

Два варианта: `arrow.clockwise` (refresh) и `gearshape` (settings).

### Crumb

Маленький header сверху контентной зоны. `AI · СЕГОДНЯ` / `GITHUB · СЕГОДНЯ` / `ДРУЗЬЯ · СЕГОДНЯ`. Цвет зависит от категории:
- AI: `#FF8FB8` (lighter pink, opacity 0.9)
- GitHub: `#4FE6FF` (cyan, opacity 0.9)
- Друзья: `rgba(255,255,255,0.7)` (нейтральный)

### HeroNumber

Главное число поповера и виджетов. SF Pro Display 30-46pt / 700, gradient fill:
- Default (AI): white → `#FFD4E3` (top→bottom)
- GitHub: white → `#D4F3FF`

Для GitHub-варианта рядом — `unit.l` пилюля «коммитов» в cyan, baseline-aligned.

### FriendRow

Один ряд лидерборда. Grid `[18 | 22 | 1fr | auto]` со столбцами: ранг / аватар / имя / значение.

```
.rk      → SF Pro Text 11-13pt, opacity 0.5
.av      → 22×22pt circle. Default — gradient pink→cyan, opacity 0.8.
            "Я" — pure pink gradient + glow shadow rgba(255,45,109,0.5)
.nm      → SF Pro Text 13-14pt / 500, ellipsis при overflow
            "Я" — color brand.pink.light + weight 600
.vl      → SF Pro Text 12-13pt / 500, monospacedDigit, opacity 0.78
```

### Sparkline

Высота: 28-38pt в поповере, 22pt в Small widget, 28pt в Large widget bottom row.

- AI variant: stroke = linear-gradient `#FF5FA0` → `#FF2D6D`. Fill: linear-gradient `rgba(255,95,160,0.3)` → transparent.
- GitHub variant: stroke = linear-gradient `#4FE6FF` → `#00B8E6`. Fill: `rgba(79,230,255,0.28)` → transparent.
- Stroke width: 1.5-1.6pt, `stroke-linecap: round`.
- Подпись сверху: SF Pro Text 8-10pt, opacity 0.5, label like «Дневные траты · 30 дней» или «Добавленные строки · 30 дней».

### MenuBarItem

Текущий: `↗ $1602.78`.

Новый:
- Capsule с blur, background `linear-gradient(90deg, rgba(255,45,109,0.25), rgba(0,212,255,0.25))` + `0.5pt rgba(255,255,255,0.3)` border.
- SF Symbol `chart.line.uptrend.xyaxis` + цена с копейками.
- Font: SF Pro Text 11pt / 590, color white.

Реализация — `NSStatusItem` с кастомным NSView (или SwiftUI hosted view).

---

## Popover composition

### Размер

- Width: `400pt` (как сейчас).
- Height: динамический по контенту, max ~600pt.

### Структура

```
+--------------------------------+
| content (padding 16-18)        |
|   crumb                        |
|   hero number                  |
|   delta                        |
|   secondary metadata           |
|                                |
|   label                        |
|   row · row · row              |
|                                |
|   ↑ margin-top: auto           |
|   sparkline                    |
|   ─── divider ───              |
|   sync line + icons            |
|                                |
|   (76pt clearance for island)  |
+--------------------------------+
|     [floating island]          |  ← absolute, bottom: 14
+--------------------------------+
```

### Контент по вкладкам

**AI (default):**
- crumb: "AI · {period}" pink
- hero: `$1 602.78` (gradient pink)
- delta: "▲ +$389.69 vs вчера" cyan
- meta: "903.6M tokens" cyan/muted
- label: "Топ моделей" cyan
- rows: model name → cost. Max 5 рядов.
- sparkline: «Дневные AI траты · 30 дней» pink stroke.

**GitHub:**
- crumb: "GitHub · {period}" cyan
- hero: `28` + cyan "коммитов" inline
- delta: "+2 623 / −39 строк" cyan
- meta: "1 репозиторий активен" muted
- label: "Топ репозиториев" cyan
- rows: repo name → "Nc · +K". Max 5 рядов.
- sparkline: «Добавленные строки · 30 дней» cyan stroke.

**Друзья:**
- crumb: "Друзья · {period}" нейтрал
- (НЕТ hero — список занимает всё)
- label: "Рейтинг по токенам" cyan
- friend rows: до 10 строк.
- (НЕТ sparkline)

### Состояния

- **Loading:** content прозрачен на 0.4, под цифрами `ProgressView()` (system circular spinner, cyan tint). Crumb остаётся ярким.
- **Empty (AI без данных):** crumb + строка «ccusage ещё не запускался» + кнопка «Запустить sync».
- **Empty (GitHub без токена):** crumb + строка «GitHub PAT не настроен» + кнопка «Открыть настройки».
- **Empty (Друзья без peers):** crumb + строка «Ты пока один в команде» + ссылка на friend-code в settings.
- **Error:** замена hero на icon `exclamationmark.triangle.fill` + короткое сообщение + retry-кнопка.

---

## Widgets

### Общие принципы

- Тот же 3-слойный surface, что и в поповере (через общий `BrandSurface` view).
- В виджетах нет переключателей. Период берётся из `WidgetConfiguration` (стандартный WidgetKit picker).
- Цена и дельта без копеек (`$1 602`, `+$389`) — экономия места.
- Sparkline опционален и зависит от размера.

### Small · 170×170pt

```
crumb
hero ($30pt)
delta (11pt)
meta (10pt)
↑ margin-top: auto
mini sparkline (22pt)
```

### Medium · 364×170pt

```
+---------------+----------------+
| crumb         | label          |
| hero ($38pt)  | row            |
| delta         | row            |
| meta          | row            |
| ↑ margin-auto | row            |
| sparkline     |                |
+---------------+----------------+
```

Левая половина = срез Small с большим hero. Правая = «Топ моделей» (до 4 рядов). Разделитель `0.5pt rgba(255,255,255,0.1)`.

### Large · 364×382pt

```
+---------------+----------------+
| left          | right          |  ← top row, same as Medium top
| crumb         | label          |
| hero ($46pt)  | rows × 4       |
| delta         |                |
| meta          |                |
+---------------+----------------+
| ─── divider ───────────────── |
| sparkline · 30 дней (28pt)     |
| ─── divider ───────────────── |
| label "Друзья · {period}"      |
| friend rows × 5                |
+--------------------------------+
```

### Реализация виджетов

- Все три размера зарегистрированы в `StatsWidget.swift` (уже).
- Общий `BrandSurface` view в `Shared/` (новый файл) — используется и поповером, и виджетами.
- `LargeView.swift`, `StatsWidgetView.swift` переписать под новые layout'ы.

---

## Реализация: где что

| Что | Где |
|---|---|
| Дизайн-токены (Color, Font, Spacing, Radius) | новый `Shared/Design/Tokens.swift` |
| Общий BrandSurface (3-layer glass+gradient) | новый `Shared/Design/BrandSurface.swift` |
| FloatingIsland + CategoryPill + PeriodSegment | новый `StatsApp/Status/IslandControl.swift` |
| SyncIconButton | внутри `DropdownView.swift` или `Shared/Design/Buttons.swift` |
| FriendRow | переписать `Shared/AvatarView.swift` или новый `Shared/Design/FriendRow.swift` |
| Sparkline | обновить существующий `StatsApp/Status/Sparkline.swift` (gradient stroke, variant API) |
| DropdownView | переписать целиком — крупная переработка |
| DropdownAISection / GitHub / Leaderboard | переписать под новый layout |
| StatusItemController | обновить NSStatusItem rendering (capsule с gradient) |
| StatsWidgetView (Small/Medium) | переписать |
| LargeView | переписать |
| Renaming "Лидерборд" → "Друзья" | **только в локализованных строках**. Код keeps `leaderboard` / `Leaderboard`. |
| README minOS | bump 14 → 26 |
| project.yml | bump deployment target |

---

## Открытые вопросы / не сейчас

- Лёгкая haptic feedback при tap на категорию (Tahoe API существует?). — не сейчас.
- Анимация перехода между категориями (cross-dissolve, slide). — не сейчас, делаем мгновенный switch.
- Light mode. — не сейчас.
- Кастомизация палитры через настройки. — не сейчас.
- Tooltip с full repo name при hover на обрезанные имена в виджете. — не сейчас.
- Виджет на Lock Screen (если Tahoe появилось). — не сейчас, проверить позже.

## Не делаем в этом редизайне

- Не трогаем data layer.
- Не трогаем sync.
- Не трогаем pricing table.
- Не меняем порядок и логику секций.
- Не добавляем новых табов / метрик.

---

## Acceptance

Редизайн считается завершённым, когда:

1. Поповер открывается в новом виде, все три вкладки работают.
2. Все три виджета (Small/Medium/Large) перерисованы.
3. Menu bar item — capsule с gradient.
4. На скриншоте без обоев (через прозрачный фон или solid color desktop) идентичность узнаваема: pink+cyan видно.
5. На macOS 26 Tahoe всё рендерится через native Liquid Glass API.
6. README обновлён (минимум OS, скриншоты).
7. CHANGELOG entry: `feat(ui): полная переделка визуала под Liquid Glass + Neon duo`.
