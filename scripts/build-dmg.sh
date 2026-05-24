#!/usr/bin/env bash
#
# Сборка release-DMG для distribution.
#
# Что делает:
#   1. xcodegen generate (если изменился project.yml)
#   2. xcodebuild Release с ad-hoc signing (из project.yml — CODE_SIGN_IDENTITY: "-")
#   3. create-dmg упаковывает Burn.app в DMG с drag-to-Applications layout
#   4. Печатает SHA256 готового DMG — для использования в Cask formula
#
# Что НЕ делает:
#   - Не нотаризует. Для notarization нужен Apple Developer Program ($99/год),
#     иностранная карта (РФ-карты не работают с Apple billing с 2022).
#     Если когда-нибудь оплатишь — добавь шаг notarytool submit в конце.
#   - Не подписывает Developer ID cert'ом (у нас ad-hoc).
#     Последствие: при двойном клике на DMG из браузера юзер увидит alert
#     "Apple cannot verify". Через `brew install --cask` этого alert'а нет
#     (cask делает xattr -dr com.apple.quarantine после install).
#
# Требования:
#   - macOS, Xcode CLI tools
#   - xcodegen (brew install xcodegen)
#   - create-dmg (brew install create-dmg)
#
# Использование:
#   ./scripts/build-dmg.sh
#   ./scripts/build-dmg.sh --skip-build   # если .app уже собран

set -euo pipefail

# --- config ---
SCHEME="StatsApp"
PRODUCT_NAME="Burn"            # PRODUCT_NAME в project.yml
PROJECT="ai-stats.xcodeproj"
BUILD_DIR="build"
CONFIGURATION="Release"
DERIVED_DATA="$BUILD_DIR"
APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/$PRODUCT_NAME.app"

# --- args ---
SKIP_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=1 ;;
        -h|--help)
            grep '^#' "$0" | head -40
            exit 0
            ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

# --- tools check ---
command -v xcodebuild >/dev/null || { echo "xcodebuild not found"; exit 1; }
command -v xcodegen >/dev/null   || { echo "xcodegen not found (brew install xcodegen)"; exit 1; }
command -v create-dmg >/dev/null || { echo "create-dmg not found (brew install create-dmg)"; exit 1; }

# --- version from project.yml ---
# Парсим версию из строки `CFBundleShortVersionString: "0.2.0"` — единственный источник правды.
VERSION=$(awk -F'"' '/CFBundleShortVersionString:/{print $2; exit}' project.yml)
if [[ -z "$VERSION" ]]; then
    echo "Could not read CFBundleShortVersionString from project.yml" >&2
    exit 1
fi
echo ">>> Version: $VERSION"

# --- build ---
if [[ "$SKIP_BUILD" -eq 0 ]]; then
    echo ">>> xcodegen generate"
    xcodegen generate

    echo ">>> xcodebuild $CONFIGURATION"
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" \
        clean build \
        | xcbeautify 2>/dev/null || \
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" \
        clean build
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "Build product not found at: $APP_PATH" >&2
    exit 1
fi
echo ">>> Built: $APP_PATH"

# --- verify ad-hoc signing ---
# codesign --verify не пройдёт для ad-hoc, но --display покажет что что-то подписано.
codesign --display --verbose=2 "$APP_PATH" 2>&1 | head -5 || true

# --- DMG ---
# Lowercase product name через tr — system bash 3.2 не поддерживает `${var,,}`.
DMG_NAME=$(echo "$PRODUCT_NAME" | tr '[:upper:]' '[:lower:]')
DMG="$BUILD_DIR/${DMG_NAME}-${VERSION}.dmg"
rm -f "$DMG"

echo ">>> create-dmg → $DMG"
create-dmg \
    --volname "$PRODUCT_NAME $VERSION" \
    --window-pos 200 120 \
    --window-size 600 320 \
    --icon-size 96 \
    --icon "$PRODUCT_NAME.app" 175 130 \
    --app-drop-link 425 130 \
    --hide-extension "$PRODUCT_NAME.app" \
    --no-internet-enable \
    "$DMG" \
    "$APP_PATH"

# --- summary ---
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
SIZE=$(du -h "$DMG" | awk '{print $1}')

echo ""
echo "==============================="
echo "DMG:    $DMG"
echo "Size:   $SIZE"
echo "SHA256: $SHA"
echo "==============================="
echo ""
echo "Для Cask formula в homebrew/ai-stats.rb замени sha256 на:"
echo "  $SHA"
