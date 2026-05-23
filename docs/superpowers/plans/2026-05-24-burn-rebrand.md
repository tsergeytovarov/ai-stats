# Burn — Rebrand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Переименовать продукт `ai-stats` → `Burn` на уровне отображения и установить новую иконку (Dock + menu bar) согласно [2026-05-24-naming-and-icon-design.md](../specs/2026-05-24-naming-and-icon-design.md).

**Architecture:** Чисто-presentation работа. Не трогаем bundle ID, target/scheme names, repo, пути в файловой системе, NSLog-теги, User-Agent. Меняется только то, что видит пользователь: иконка приложения, иконка в menu bar, display name в Dock/Spotlight/Settings/About, default filename экспорта DB.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, CoreGraphics (для рендера PNG из Swift-скрипта), xcodegen, GRDB. macOS 26+.

**Branch:** `feat/burn-rebrand` от `main`.

---

## File Structure

**Создаются:**

- `scripts/render-app-icon.swift` — CLI-скрипт на Swift+CoreGraphics, рендерит one ember-squircle в PNG заданного размера. Без внешних зависимостей.
- `scripts/generate-app-icon-set.sh` — bash-обёртка, вызывает `render-app-icon.swift` для каждого требуемого размера, складывает в `Assets.xcassets/AppIcon.appiconset/`.
- `StatsApp/Assets.xcassets/Contents.json` — корневой metadata-файл xcassets каталога.
- `StatsApp/Assets.xcassets/AppIcon.appiconset/Contents.json` — metadata icon-set'а с маппингом размеров.
- `StatsApp/Assets.xcassets/AppIcon.appiconset/*.png` — отрендеренные PNG (всего 10 файлов: 16/32/64/128/256/512 в ×1 и ×2, плюс 1024×1).
- `StatsApp/Status/MiniEmberView.swift` — SwiftUI-компонент mini-ember для capsule. Чистый SwiftUI, без ассета.
- `Tests/StatsAppTests/MiniEmberRenderTests.swift` — pixel-color smoke-тест выхода скрипта.

**Изменяются:**

- `StatsApp/Info.plist` — `CFBundleDisplayName` → `Burn`.
- `project.yml` — `CFBundleDisplayName` для обоих таргетов + добавить `Assets.xcassets` в sources + `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`.
- `StatsApp/Status/MenuBarCapsuleView.swift` — заменить `Image(systemName:)` на `MiniEmberView()`.
- `StatsApp/Settings/SettingsWindowController.swift:32` — window title.
- `StatsApp/Settings/GeneralTabView.swift:35` — About-текст.
- `StatsApp/Settings/DatabaseExporter.swift:9` — default-имя экспорта.
- `README.md` — user-facing заголовок и описание (репо-путь, ccusage-ссылки, code-блоки сборки — не трогаем).
- `CHANGELOG.md` — запись о rebrand.

**Намеренно не меняются** (закреплено спекой):

- `PRODUCT_BUNDLE_IDENTIFIER` (`com.sergeytovarov.aistats`).
- Target/scheme names (`StatsApp`, `StatsWidget`).
- `project.yml` `name: ai-stats`.
- Git remote, директория репозитория.
- Пути в коде: `~/.config/ai-stats/`, `~/Library/Application Support/ai-stats/`.
- `NSLog("ai-stats ...")` теги (внутренние).
- HTTP User-Agent `ai-stats/0.1` (rate-limit identity).

---

## Task 1: Branch setup

**Files:** —

- [ ] **Step 1: Создать ветку и переключиться**

```bash
git checkout -b feat/burn-rebrand
git status
```

Ожидаемый вывод: `On branch feat/burn-rebrand`, рабочее дерево чистое.

---

## Task 2: Render-icon Swift script

Скрипт рендерит ember-squircle в PNG. Spec композиции — раздел 3 [naming-and-icon-design.md](../specs/2026-05-24-naming-and-icon-design.md).

**Files:**
- Create: `scripts/render-app-icon.swift`

- [ ] **Step 1: Создать `scripts/render-app-icon.swift`**

```swift
#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

// MARK: - CLI

guard CommandLine.arguments.count == 3,
      let size = Int(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: render-app-icon.swift <pixel-size> <output.png>\n".utf8))
    exit(2)
}
let outPath = CommandLine.arguments[2]

// MARK: - Rendering

let dim = CGFloat(size)
let cornerRadius = dim * 0.225  // squircle ≈ 22.5 % of side

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("CGContext alloc failed\n".utf8))
    exit(1)
}

// 1. Clip to squircle
let rect = CGRect(x: 0, y: 0, width: dim, height: dim)
let squirclePath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.addPath(squirclePath)
ctx.clip()

// 2. Dark glass base (linear gradient 160°: #1A0A26 → #0A0414)
let baseStart = CGPoint(x: dim * 0.13, y: dim * 0.95)   // 160° in CG-coords (y up)
let baseEnd   = CGPoint(x: dim * 0.87, y: dim * 0.05)
let baseGrad = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(red: 0x1A/255.0, green: 0x0A/255.0, blue: 0x26/255.0, alpha: 1.0),
    CGColor(red: 0x0A/255.0, green: 0x04/255.0, blue: 0x14/255.0, alpha: 1.0)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(baseGrad, start: baseStart, end: baseEnd, options: [])

// 3. Pink tint top-left — radial, center (0.18, 0.04), radius 0.58 of side, alpha .62 → 0
let pinkCenter = CGPoint(x: dim * 0.18, y: dim * (1 - 0.04))
let pinkGrad = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(red: 1.0, green: 45/255.0, blue: 109/255.0, alpha: 0.62),
    CGColor(red: 1.0, green: 45/255.0, blue: 109/255.0, alpha: 0.0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(pinkGrad,
    startCenter: pinkCenter, startRadius: 0,
    endCenter:   pinkCenter, endRadius:   dim * 0.58,
    options: [])

// 4. Cyan tint bottom-right — radial, center (1.0, 1.0), radius 0.70, alpha .50 → 0
let cyanCenter = CGPoint(x: dim, y: 0)
let cyanGrad = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(red: 0.0, green: 184/255.0, blue: 230/255.0, alpha: 0.50),
    CGColor(red: 0.0, green: 184/255.0, blue: 230/255.0, alpha: 0.0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(cyanGrad,
    startCenter: cyanCenter, startRadius: 0,
    endCenter:   cyanCenter, endRadius:   dim * 0.70,
    options: [])

// 5. Ambient bloom on the glass (outside ember core): pink + cyan
ctx.saveGState()
let bloomCenter = CGPoint(x: dim * 0.5, y: dim * 0.5)
let pinkBloom = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(red: 1.0, green: 45/255.0, blue: 109/255.0, alpha: 0.55),
    CGColor(red: 1.0, green: 45/255.0, blue: 109/255.0, alpha: 0.0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(pinkBloom,
    startCenter: bloomCenter, startRadius: dim * 0.26,
    endCenter:   bloomCenter, endRadius:   dim * 0.50,
    options: [])
let cyanBloom = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(red: 0.0, green: 184/255.0, blue: 230/255.0, alpha: 0.35),
    CGColor(red: 0.0, green: 184/255.0, blue: 230/255.0, alpha: 0.0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(cyanBloom,
    startCenter: bloomCenter, startRadius: dim * 0.28,
    endCenter:   bloomCenter, endRadius:   dim * 0.58,
    options: [])
ctx.restoreGState()

// 6. Ember core — sphere with highlight at (0.36, 0.30 relative to ember bounds)
let emberR = dim * 0.26  // radius — diameter ≈ 52% of side
let emberCenter = CGPoint(x: dim * 0.5, y: dim * 0.5)
let highlight = CGPoint(
    x: emberCenter.x + (0.36 - 0.5) * emberR * 2,
    y: emberCenter.y + (0.5 - 0.30) * emberR * 2  // CG y-up: 0.30 from top → above center
)

let emberColors: [CGColor] = [
    CGColor(red: 1.0,        green: 1.0,        blue: 1.0,        alpha: 1.0),  // 0%
    CGColor(red: 1.0,        green: 0xE1/255.0, blue: 0xEC/255.0, alpha: 1.0),  // 6%
    CGColor(red: 1.0,        green: 0x9B/255.0, blue: 0xC1/255.0, alpha: 1.0),  // 16%
    CGColor(red: 1.0,        green: 0x5F/255.0, blue: 0xA0/255.0, alpha: 1.0),  // 32%
    CGColor(red: 1.0,        green: 0x2D/255.0, blue: 0x6D/255.0, alpha: 1.0),  // 52%
    CGColor(red: 0xC0/255.0, green: 0x15/255.0, blue: 0x58/255.0, alpha: 1.0),  // 78%
    CGColor(red: 0x5D/255.0, green: 0x08/255.0, blue: 0x24/255.0, alpha: 1.0),  // 100%
]
let emberLocs: [CGFloat] = [0.00, 0.06, 0.16, 0.32, 0.52, 0.78, 1.00]
let emberGrad = CGGradient(colorsSpace: colorSpace, colors: emberColors as CFArray, locations: emberLocs)!
ctx.drawRadialGradient(emberGrad,
    startCenter: highlight, startRadius: 0,
    endCenter:   emberCenter, endRadius: emberR,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// 7. Hairline inner stroke on ember (subtle 1px white @10%)
ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.10))
ctx.setLineWidth(max(1.0, dim / 1024.0))
ctx.strokeEllipse(in: CGRect(
    x: emberCenter.x - emberR, y: emberCenter.y - emberR,
    width: emberR * 2, height: emberR * 2))

// MARK: - Write PNG

guard let cgImage = ctx.makeImage() else {
    FileHandle.standardError.write(Data("ctx.makeImage() failed\n".utf8))
    exit(1)
}
let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: dim, height: dim))
guard let tiff = nsImage.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("PNG encode failed\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(size)×\(size))")
```

- [ ] **Step 2: Сделать скрипт исполняемым**

```bash
chmod +x scripts/render-app-icon.swift
```

- [ ] **Step 3: Smoke-запуск с size=1024 во временный файл**

```bash
swift scripts/render-app-icon.swift 1024 /tmp/burn-icon-test.png
file /tmp/burn-icon-test.png
```

Ожидаемый вывод: `/tmp/burn-icon-test.png: PNG image data, 1024 x 1024, 8-bit/color RGBA, non-interlaced`.

- [ ] **Step 4: Открыть превью и убедиться что глаза не врут**

```bash
open /tmp/burn-icon-test.png
```

Должен открыться squircle с тёмно-фиолетовым фоном, pink/cyan тинтами по диагонали и горячим розовым шариком в центре с белым световым ядром сверху-слева. Если ember не видно или squircle не скруглён — STOP и фиксить.

- [ ] **Step 5: Commit**

```bash
git add scripts/render-app-icon.swift
git diff --staged
git commit -m "feat(icons): swift+coregraphics скрипт рендера app-иконки Burn"
```

---

## Task 3: Pixel-color smoke test для скрипта

Простой тест: вызываем скрипт через `Process`, проверяем что выход — валидный PNG с ожидаемыми пиксельными цветами в ключевых точках (центр — белый/розовый highlight, угол — почти чёрный).

**Files:**
- Create: `Tests/StatsAppTests/MiniEmberRenderTests.swift`

- [ ] **Step 1: Написать тест**

```swift
import XCTest
import AppKit

final class MiniEmberRenderTests: XCTestCase {
    func test_renderScript_produces128pxPNG_withEmberAtCenterAndDarkCorner() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("burn-icon-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Find repo root from test bundle — climb until we find scripts/render-app-icon.swift.
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("scripts/render-app-icon.swift").path) {
            let parent = dir.deletingLastPathComponent()
            if parent == dir { XCTFail("repo root not found"); return }
            dir = parent
        }
        let scriptURL = dir.appendingPathComponent("scripts/render-app-icon.swift")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", scriptURL.path, "128", tmp.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "render-app-icon.swift exited non-zero")

        // Verify PNG is valid 128×128
        guard let image = NSImage(contentsOf: tmp),
              let rep = image.representations.first as? NSBitmapImageRep else {
            XCTFail("output is not a valid image")
            return
        }
        XCTAssertEqual(rep.pixelsWide, 128)
        XCTAssertEqual(rep.pixelsHigh, 128)

        // Center pixel should be very light (white-pink core of ember).
        let center = rep.colorAt(x: 64, y: 64)!
        XCTAssertGreaterThan(center.redComponent,   0.85, "ember center should be bright")
        XCTAssertGreaterThan(center.greenComponent, 0.50, "ember center has white highlight")

        // Top-left corner pixel should be dark (deep glass with pink tint, but still dark).
        let corner = rep.colorAt(x: 4, y: 124)!  // CG y-down for NSBitmapImageRep
        XCTAssertLessThan(corner.redComponent + corner.greenComponent + corner.blueComponent, 1.6,
            "top-left corner should be dark glass")
    }
}
```

- [ ] **Step 2: Перегенерировать xcodeproj (xcodegen подхватит новый тестовый файл) и запустить тест**

```bash
xcodegen generate
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp \
  -destination 'platform=macOS' \
  -only-testing:StatsAppTests/MiniEmberRenderTests 2>&1 | tail -20
```

Ожидание: `** TEST SUCCEEDED **`. Скрипт из Task 2 уже работает, тест должен пройти с первого запуска. Если падает — смотреть на координаты пикселей: NSBitmapImageRep использует y-down, а CGContext — y-up. Center точно `(64, 64)`, corner возможно нужен другой угол (попробовать `(4, 4)` если top-left в y-up).

- [ ] **Step 3: Commit**

```bash
git add Tests/StatsAppTests/MiniEmberRenderTests.swift
git diff --staged
git commit -m "test(icons): pixel-color smoke-тест рендера app-иконки"
```

---

## Task 4: Сгенерировать AppIcon set

**Files:**
- Create: `scripts/generate-app-icon-set.sh`
- Create: `StatsApp/Assets.xcassets/Contents.json`
- Create: `StatsApp/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `StatsApp/Assets.xcassets/AppIcon.appiconset/icon_*.png` (10 файлов)

- [ ] **Step 1: Создать корневой xcassets metadata-файл**

```bash
mkdir -p StatsApp/Assets.xcassets/AppIcon.appiconset
```

Файл `StatsApp/Assets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 2: Создать `StatsApp/Assets.xcassets/AppIcon.appiconset/Contents.json`**

Маппинг стандартного macOS app icon set (16/32/128/256/512 ×1/×2 + 1024×1):

```json
{
  "images" : [
    { "size" : "16x16",   "idiom" : "mac", "filename" : "icon_16x16.png",     "scale" : "1x" },
    { "size" : "16x16",   "idiom" : "mac", "filename" : "icon_16x16@2x.png",  "scale" : "2x" },
    { "size" : "32x32",   "idiom" : "mac", "filename" : "icon_32x32.png",     "scale" : "1x" },
    { "size" : "32x32",   "idiom" : "mac", "filename" : "icon_32x32@2x.png",  "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128.png",   "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128@2x.png","scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256.png",   "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256@2x.png","scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512.png",   "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512@2x.png","scale" : "2x" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Написать `scripts/generate-app-icon-set.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$DIR/StatsApp/Assets.xcassets/AppIcon.appiconset"
SCRIPT="$DIR/scripts/render-app-icon.swift"

declare -a SIZES=(
  "16   icon_16x16.png"
  "32   icon_16x16@2x.png"
  "32   icon_32x32.png"
  "64   icon_32x32@2x.png"
  "128  icon_128x128.png"
  "256  icon_128x128@2x.png"
  "256  icon_256x256.png"
  "512  icon_256x256@2x.png"
  "512  icon_512x512.png"
  "1024 icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
  size="${entry%% *}"
  name="${entry##* }"
  swift "$SCRIPT" "$size" "$OUT/$name"
done

echo "Done. $(ls -1 "$OUT"/*.png | wc -l) PNGs generated."
```

- [ ] **Step 4: Запустить генерацию**

```bash
chmod +x scripts/generate-app-icon-set.sh
./scripts/generate-app-icon-set.sh
ls -la StatsApp/Assets.xcassets/AppIcon.appiconset/
```

Ожидание: 10 PNG-файлов + `Contents.json`. Финальная строка скрипта: `Done. 10 PNGs generated.`

- [ ] **Step 5: Открыть один PNG для проверки**

```bash
open StatsApp/Assets.xcassets/AppIcon.appiconset/icon_512x512.png
```

Глазами: squircle, ember, glow. Если плохо — STOP, корректировать скрипт из Task 2 и перегенерировать.

- [ ] **Step 6: Commit**

```bash
git add scripts/generate-app-icon-set.sh StatsApp/Assets.xcassets
git diff --staged
git commit -m "feat(icons): сгенерировать app icon set из скрипта"
```

---

## Task 5: Подключить Assets.xcassets к таргету через project.yml

`project.yml` пока не упоминает `Assets.xcassets`. По умолчанию xcodegen подхватывает всё содержимое `sources: path: StatsApp`, но `AppIcon` обозначение надо задать явно.

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Добавить настройку `ASSETCATALOG_COMPILER_APPICON_NAME` в settings таргета StatsApp**

В файле `project.yml`, внутри `targets.StatsApp.settings.base`, рядом с существующими ключами добавить:

```yaml
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

После правки секция выглядит так:

```yaml
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.sergeytovarov.aistats
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_ENTITLEMENTS: StatsApp/StatsApp.entitlements
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

- [ ] **Step 2: Перегенерировать xcodeproj**

```bash
xcodegen generate
```

Ожидание: `Created project at ai-stats.xcodeproj`.

- [ ] **Step 3: Сборка релизного бинаря и проверка наличия иконки**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Release -derivedDataPath build/ 2>&1 | tail -10
ls build/Build/Products/Release/StatsApp.app/Contents/Resources/ | grep -i icon
```

Ожидание: `BUILD SUCCEEDED` и файл `AppIcon.icns` среди ресурсов.

- [ ] **Step 4: Открыть собранный .app в Finder для визуальной проверки**

```bash
open -R build/Build/Products/Release/StatsApp.app
```

В Finder должна быть видна новая иконка (если cache не обновился — `killall Finder` или перезагрузить иконку через `touch build/Build/Products/Release/StatsApp.app`).

- [ ] **Step 5: Commit**

```bash
git add project.yml ai-stats.xcodeproj
git diff --staged
git commit -m "build: подключить AppIcon в Assets.xcassets к таргету StatsApp"
```

---

## Task 6: MiniEmberView (SwiftUI)

**Files:**
- Create: `StatsApp/Status/MiniEmberView.swift`

- [ ] **Step 1: Написать компонент**

```swift
import SwiftUI

/// Mini-ember для menu bar capsule. Та же метафора, что и app-иконка в Dock,
/// уменьшенная до глифа высотой ≈12pt.
///
/// Реализация — pure SwiftUI: Circle + RadialGradient (highlight в top-left
/// сегменте) + двойная shadow для ambient bloom. Цвета берутся из BrandColor
/// токенов, чтобы редизайн палитры подхватывался автоматически.
struct MiniEmberView: View {
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white,                                                       location: 0.00),
                        .init(color: Color(red: 1.0,   green: 0xE1/255.0, blue: 0xEC/255.0),       location: 0.06),
                        .init(color: Color(red: 1.0,   green: 0x9B/255.0, blue: 0xC1/255.0),       location: 0.16),
                        .init(color: BrandColor.pinkLight,                                          location: 0.32),
                        .init(color: BrandColor.pink,                                               location: 0.52),
                        .init(color: Color(red: 0xC0/255.0, green: 0x15/255.0, blue: 0x58/255.0),  location: 0.78),
                        .init(color: Color(red: 0x5D/255.0, green: 0x08/255.0, blue: 0x24/255.0),  location: 1.00),
                    ]),
                    center: UnitPoint(x: 0.34, y: 0.28),
                    startRadius: 0,
                    endRadius: size * 0.55
                )
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            .frame(width: size, height: size)
            .shadow(color: BrandColor.pink.opacity(0.85), radius: size * 0.5)
            .shadow(color: BrandColor.cyan.opacity(0.35), radius: size * 1.0)
    }
}

#Preview("MiniEmber on dark") {
    HStack(spacing: 12) {
        MiniEmberView(size: 12)
        MiniEmberView(size: 16)
        MiniEmberView(size: 24)
    }
    .padding(20)
    .background(Color(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x20/255.0))
}
```

- [ ] **Step 2: Перегенерировать xcodeproj (xcodegen подхватит новый файл)**

```bash
xcodegen generate
```

- [ ] **Step 3: Сборка — должна пройти**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -5
```

Ожидание: `BUILD SUCCEEDED`.

- [ ] **Step 4: Открыть `MiniEmberView.swift` в Xcode и проверить SwiftUI Preview**

```bash
open ai-stats.xcodeproj
```

В Xcode открыть `StatsApp/Status/MiniEmberView.swift`, дождаться сборки превью, убедиться что три кружочка отрисовываются с pink-cyan свечением на тёмном фоне.

- [ ] **Step 5: Commit**

```bash
git add StatsApp/Status/MiniEmberView.swift ai-stats.xcodeproj
git diff --staged
git commit -m "feat(menubar): mini-ember SwiftUI view для capsule"
```

---

## Task 7: Замена SF-символа в MenuBarCapsuleView

**Files:**
- Modify: `StatsApp/Status/MenuBarCapsuleView.swift`

- [ ] **Step 1: Заменить `Image(systemName: ...)` на `MiniEmberView()`**

Целевое состояние `StatsApp/Status/MenuBarCapsuleView.swift`:

```swift
import SwiftUI

struct MenuBarCapsuleView: View {
    let priceText: String   // "$1,602.78"

    var body: some View {
        HStack(spacing: 4) {
            MiniEmberView(size: 12)
            Text(priceText)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(
            LinearGradient(
                colors: [BrandColor.pink.opacity(0.25), BrandColor.cyan.opacity(0.25)],
                startPoint: .leading, endPoint: .trailing
            )
            .clipShape(Capsule())
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
    }
}

#Preview("Capsule on menubar") {
    MenuBarCapsuleView(priceText: "$4.82")
        .padding(20)
        .background(Color(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x20/255.0))
}
```

- [ ] **Step 2: Сборка и запуск приложения**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -5
open build/Build/Products/Debug/StatsApp.app
```

В menu bar должен появиться capsule с горящим розовым шариком вместо chart-стрелочки. Если SF-символ всё ещё там — не пересобралось, killall StatsApp и пересобрать.

- [ ] **Step 3: Существующие тесты должны проходить (sanity)**

```bash
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp \
  -destination 'platform=macOS' 2>&1 | tail -10
```

Ожидание: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add StatsApp/Status/MenuBarCapsuleView.swift
git diff --staged
git commit -m "feat(menubar): заменить chart-глиф на mini-ember в capsule"
```

---

## Task 8: Display name → Burn

Меняется только то, что показывается пользователю. Bundle ID, target/scheme names, paths — не трогаем.

**Files:**
- Modify: `project.yml`
- Modify: `StatsApp/Info.plist`
- Modify: `StatsApp/Settings/SettingsWindowController.swift`
- Modify: `StatsApp/Settings/GeneralTabView.swift`
- Modify: `StatsApp/Settings/DatabaseExporter.swift`

- [ ] **Step 1: Обновить `project.yml`**

В блоке `targets.StatsApp.info.properties`:

```yaml
        CFBundleDisplayName: Burn
```

(было: `ai-stats`)

В блоке `targets.StatsWidget.info.properties`:

```yaml
        CFBundleDisplayName: Burn Widget
```

(было: `ai-stats Widget`)

- [ ] **Step 2: Обновить `StatsApp/Info.plist`**

Заменить:

```xml
	<key>CFBundleDisplayName</key>
	<string>ai-stats</string>
```

на:

```xml
	<key>CFBundleDisplayName</key>
	<string>Burn</string>
```

- [ ] **Step 3: Обновить `StatsApp/Settings/SettingsWindowController.swift:32`**

Заменить:

```swift
        win.title = "ai-stats Settings"
```

на:

```swift
        win.title = "Burn Settings"
```

- [ ] **Step 4: Обновить `StatsApp/Settings/GeneralTabView.swift:35`**

Заменить:

```swift
            Text("ai-stats \(version)").font(.caption).foregroundStyle(.secondary)
```

на:

```swift
            Text("Burn \(version)").font(.caption).foregroundStyle(.secondary)
```

- [ ] **Step 5: Обновить `StatsApp/Settings/DatabaseExporter.swift:9`**

Заменить:

```swift
        panel.nameFieldStringValue = "ai-stats-\(DateUtils.isoDayCompact(Date())).db"
```

на:

```swift
        panel.nameFieldStringValue = "burn-\(DateUtils.isoDayCompact(Date())).db"
```

- [ ] **Step 6: Перегенерировать xcodeproj и собрать**

```bash
xcodegen generate
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -5
```

Ожидание: `BUILD SUCCEEDED`.

- [ ] **Step 7: Проверка — display name в собранном .app**

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" \
  build/Build/Products/Debug/StatsApp.app/Contents/Info.plist
```

Ожидание: `Burn`.

- [ ] **Step 8: Sanity — внутренние пути и NSLog-теги остались `ai-stats`**

```bash
grep -rn '"ai-stats' StatsApp Shared StatsWidget 2>/dev/null | grep -v "build/" | wc -l
```

Должно быть **>0** — это намеренно (NSLog-теги, пути, User-Agent). Если 0 — мы переусердствовали, надо откатить лишнее.

- [ ] **Step 9: Запустить app и пройтись по UI**

```bash
open build/Build/Products/Debug/StatsApp.app
```

Проверить:
- Title окна Settings — `Burn Settings`.
- About-секция в General-таб — `Burn 0.2.0`.
- Cmd+Tab переключатель показывает `Burn`.
- Spotlight ⌘+Пробел → "Burn" находит приложение.

- [ ] **Step 10: Commit**

```bash
git add project.yml StatsApp/Info.plist StatsApp/Settings ai-stats.xcodeproj
git diff --staged
git commit -m "feat: переименовать display name в Burn (UI и Dock)"
```

---

## Task 9: README и CHANGELOG

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Прочитать текущий README перед правкой**

```bash
wc -l README.md
```

- [ ] **Step 2: Обновить заголовок и первый абзац `README.md`**

Заменить первую строку:

```markdown
# ai-stats
```

на:

```markdown
# Burn

> Бывший `ai-stats`. Внутренние пути (`~/.config/ai-stats/`, `~/Library/Application Support/ai-stats/`) и репозиторий пока не переименованы — это запланировано под v1.0 cleanup.
```

И обновить второй абзац с описанием. Было:

```markdown
macOS menu bar app для статистики использования AI-агентов и активности на GitHub.
```

Оставить как есть (название продукта в этой фразе не упоминается).

Пройтись по остальному файлу `rg "ai-stats" README.md` и принять решение по каждому случаю — пути в коде/командах не трогать, только places где это product name.

- [ ] **Step 3: Добавить запись в `CHANGELOG.md`**

Открыть `CHANGELOG.md`. В верхней секции (Unreleased или новая 0.3.0) добавить:

```markdown
### Изменено

- Переименовать продукт в **Burn**. Display name в Dock/Spotlight/Settings обновлён, иконка приложения и иконка в menu bar — новые (ember на тёмном стекле, pink+cyan glow). Внутренние идентификаторы (bundle ID, пути в файловой системе, NSLog-теги) сохранены до v1.0.
```

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git diff --staged
git commit -m "docs: rebrand → Burn в README и changelog"
```

---

## Task 10: Финальный smoke test

**Files:** —

- [ ] **Step 1: Полная пересборка релизной версии**

```bash
rm -rf build/
xcodegen generate
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Release -derivedDataPath build/ 2>&1 | tail -5
```

Ожидание: `BUILD SUCCEEDED`.

- [ ] **Step 2: Прогнать все тесты**

```bash
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp \
  -destination 'platform=macOS' 2>&1 | tail -5
```

Ожидание: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Установить .app и проверить везде**

```bash
killall StatsApp 2>/dev/null || true
cp -R build/Build/Products/Release/StatsApp.app /Applications/
open /Applications/StatsApp.app
```

Чек-лист (отметить руками):
- [ ] Иконка в Dock — squircle с ember.
- [ ] Cmd+Tab — иконка и название `Burn`.
- [ ] Menu bar — capsule с горящим ember + ценой.
- [ ] Переключиться в светлую тему системы (System Settings → Appearance → Light): capsule всё ещё контрастно читается.
- [ ] Переключиться обратно в тёмную: capsule стабилен.
- [ ] Spotlight (Cmd+Space) → "Burn" → находится первым результатом.
- [ ] Открыть Settings из popover — title окна `Burn Settings`.
- [ ] В General-табе — `Burn 0.2.0`.
- [ ] Export DB — default-имя файла `burn-YYYYMMDD.db`.

- [ ] **Step 4: Прогнать pixel-color smoke-тест ещё раз**

```bash
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp \
  -destination 'platform=macOS' \
  -only-testing:StatsAppTests/MiniEmberRenderTests 2>&1 | tail -5
```

Ожидание: `Test Suite 'MiniEmberRenderTests' passed`.

- [ ] **Step 5: Если все галки — merge или PR**

```bash
git checkout main
git merge --no-ff feat/burn-rebrand
git log --oneline -5
```

Или, если предпочтительнее PR:

```bash
git push -u origin feat/burn-rebrand
gh pr create --fill
```
