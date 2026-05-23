# Naming & Icon — Design Spec

**Дата:** 2026-05-24
**Статус:** Draft v1 — ждёт ревью.
**Автор:** Boris (через брейнсторм с Сергеем)

## 1. Цель

Зафиксировать продуктовое имя и визуальную идентичность приложения (Dock-иконка + menu bar). До этого момента приложение жило под рабочим именем `ai-stats` и использовало generic SF-символ `chart.line.uptrend.xyaxis`. Это placeholder, не выдерживающий публичный релиз (open source, v1.0 по фазировке базового [spec](2026-05-22-ai-stats-design.md)).

Не-цели:

- Не переименовываем git-репозиторий, bundle ID, target-имена и пути в коде. Это отдельная работа, она войдёт в implementation plan.
- Не редизайним popup / виджеты — у них уже есть свой [Liquid Glass spec](2026-05-23-redesign-design.md), эта работа надстраивается над ним.
- Не делаем альтернативные темы / кастомные палитры — позже.

## 2. Имя

**Продуктовое имя: `Burn`.**

### Обоснование

- Однословное, brand-forward — соответствует уже агрессивно-неоновому визуалу (pink #FF2D6D + cyan #00B8E6).
- Метафора «жечь токены» точно ложится на основной use case: AI-расходы как ежедневный burn-rate. Одновременно покрывает и вторую половину продукта — темп активности на GitHub («burning through commits today»).
- Один слог, легко вбить в Spotlight.
- В App Store и в menu bar разговорно работает: «глянь Burn — сколько я сегодня сжёг».

### Отклонённые варианты

| Вариант | Почему нет |
|---|---|
| `ai-stats` (текущее) | Утилитарный placeholder, не для маркета. Не сообщает характер. |
| `BurnRate` | Устоявшийся финансовый термин — конкуренция в App Store с трекерами runway. SEO утоплено. |
| `Token Burn` / `AI Burn` / `aBurnAI` | Два слова → плохая discoverability. Модификатор AI/Token однобок — приложение не только про AI. Camel-case с маленькой `a` визуально кривое. |
| `Burnt` | Past participle: статика вместо движения. Намёк на burnout — противоречит дофаминовому тону приложения. |
| `Ember` / `Cinder` / `Furnace` | Та же burn-семья, но мягче. `Ember` коллизия с Ember.js. Решено оставить как метафору иконки, а не имя. |

## 3. App icon (Dock / Finder / Launchpad)

### Концепция

**Уголёк в тёмном стекле.** Одна горячая капля внутри squircle, окружённая ambient-свечением.

Концепция дистиллирует уже существующий Liquid Glass-язык приложения в одну точку. Связь «иконка ↔ UI» прямая: вся UI — это тёмное стекло с pink/cyan тинтами, иконка — тоже.

### Композиция

1. **Squircle base.** Стандартный macOS squircle (corner-radius ≈22.5% от стороны).
2. **Подложка (тёмное стекло):**
   - Базовый цвет: linear-gradient(160°, #1A0A26 → #0A0414).
   - Pink tint top-left: radial-gradient(58% 58% at 18% 4%, rgba(255,45,109,0.62), transparent 60%).
   - Cyan tint bottom-right: radial-gradient(70% 70% at 100% 100%, rgba(0,184,230,0.50), transparent 62%).
   - Внутренний highlight: inset 0 1px 0 rgba(255,255,255,0.20).
   - Внутренний edge: inset 0 0 0 1px rgba(255,255,255,0.08).
3. **Ember core (центр).** Сферический шарик, диаметр ≈52% от стороны squircle.
   - Градиент (radial, центр в 36% / 30% — top-left highlight):
     - 0% — #FFFFFF (белое световое ядро)
     - 6% — #FFE1EC
     - 16% — #FF9BC1
     - 32% — #FF5FA0
     - 52% — #FF2D6D (brand pink)
     - 78% — #C01558
     - 100% — #5D0824 (тёмно-малиновый край)
   - Subtle inner stroke: inset 0 0 0 1px rgba(255,255,255,0.10).
4. **Ambient bloom (снаружи ядра, на стекле).** Двойное свечение:
   - Pink: radial, rgba(255,45,109,0.55) → 0 в 55%.
   - Cyan: radial, rgba(0,184,230,0.35) → 0 в 70%.
   - Blur ≈14px на 1024 размере (линейно скейлится).

### Размеры (.icns set)

Стандартный macOS-набор: 16, 32, 64, 128, 256, 512, 1024 (×1 и ×2 в Assets.xcassets).

На размерах ≤32px ambient-glow упрощается до одного pink-halo, чтобы ядро не сливалось с подложкой. На 16px белое световое ядро уменьшается до 1px-пикселя — проверено визуально, читается.

### Производство

Исходник — векторный (SVG или Figma). Из него экспортируется растровый набор для `Assets.xcassets/AppIcon.appiconset`. Genertion-скрипт описывается в implementation plan.

## 4. Menu bar capsule

### Текущее состояние

`MenuBarCapsuleView.swift` (см. [Status/MenuBarCapsuleView.swift](../../../StatsApp/Status/MenuBarCapsuleView.swift:3)):

- HStack: SF-символ `chart.line.uptrend.xyaxis` (10pt) + price text (11pt, semibold, monospaced digits).
- Background: linear-gradient `BrandColor.pink.opacity(0.25)` → `BrandColor.cyan.opacity(0.25)`, clipped в `Capsule`.
- Stroke: `Color.white.opacity(0.3)`, lineWidth 0.5.
- Padding: vertical 2, horizontal 8.

### Изменение

**Заменить SF-символ на mini-ember.** Капсула остаётся той же — это и есть бренд в баре, ломать незачем.

Mini-ember:

- Размер: 12pt (вписывается в высоту капсулы).
- Те же градиентные стопы, что у Dock-иконки, но highlight в 34% / 28% (чуть смещён).
- Box-shadow (свечение): `0 0 6px rgba(255,45,109,0.85)` + `0 0 12px rgba(0,184,230,0.35)`.
- Реализация: либо SwiftUI Circle + RadialGradient + .shadow, либо PDF-ассет в Assets.xcassets (template = NO, потому что capsule цветная — system-recoloring не применяется).

Остальные элементы (price text, capsule background, stroke) — без изменений.

### Отклонённые варианты

| Вариант | Почему нет |
|---|---|
| Template image (монохромный кружок) | Капсула уже цветная — system-recoloring не сработает. Это был мой косяк раннее в брейншторме. |
| Капсула + ember + period chip (D/W/M) | Информативнее, но шире — занимает больше места в menu bar, а текущее поведение (период переключается в popup) уже работает. Можно вернуться к этому отдельно, если pain будет реальным. |
| Naked (без капсулы) | Менее очевидная кликабельность. Капсула — узнаваемый CTA-объект, отказываться от неё ради ~6px экономии не стоит. |

## 5. Связь между двумя иконками

Метафора одна — **уголёк**. Меняется только обвязка и масштаб:

| Контекст | Размер ember | Подложка |
|---|---|---|
| Dock / Finder / Launchpad | ≈52% от squircle | Тёмное glass-squircle |
| Menu bar | 12pt | Pink/cyan градиент-capsule |

Пользователь, видевший Dock-иконку, мгновенно опознаёт ту же сущность в menu bar и наоборот.

## 6. Что выезжает в implementation plan

1. Создать векторный исходник (Figma или SVG) с обеими композициями.
2. Сгенерировать растровый AppIcon-set и заменить в `Assets.xcassets/AppIcon.appiconset`.
3. Реализовать mini-ember в `MenuBarCapsuleView.swift` — либо чистый SwiftUI Circle + gradient + shadow, либо ассет.
4. Обновить product display name: `CFBundleDisplayName = Burn` в `Info.plist` (и/или соответствующий ключ в `project.yml` под xcodegen). **Не трогая** target names, scheme names, bundle ID, git remote и пути в коде — это отдельный шаг под v1.0 open-source-cleanup.
5. Обновить README.md (заголовок, описание, скриншоты), CHANGELOG.md (запись о переименовании).
6. Smoke-проверка: Spotlight, Dock, App Switcher, menu bar в светлой и тёмной системной теме.

Renaming bundle ID, git remote, путей в коде, npm/brew-метаданных — отдельная задача под open-source-релиз v1.0, в этот spec не входит.

## 7. Open questions

Открытых вопросов нет. Имя зафиксировано, обе композиции зафиксированы, объём scope явно ограничен.
