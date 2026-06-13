cask "ai-stats" do
  version "0.6.5"

  # SHA256 высчитывается на каждый релиз. Подставляется build-dmg.sh-скриптом
  # после создания DMG. Для разработки можно временно использовать :no_check,
  # но НЕ публиковать с ним — потеряешь integrity-проверку.
  sha256 "951aa35da317f7f9afaf474c2c28d228624697e2ef3f14dc9c6ecd369840c529"

  url "https://github.com/tsergeytovarov/ai-stats/releases/download/v#{version}/burn-#{version}.dmg"
  name "Burn"
  desc "macOS menu bar app для статистики использования AI-агентов и активности на GitHub"
  homepage "https://github.com/tsergeytovarov/ai-stats"

  # В DMG лежит Burn.app — Homebrew Cask делает symlink в /Applications.
  app "Burn.app"

  # Очистка при `brew uninstall --cask --zap ai-stats`. Keychain-запись
  # (tech.popovs.aistats.github) НЕ удаляется — для этого нужен pre-uninstall
  # скрипт, который cask не поддерживает напрямую. Юзер может вычистить вручную
  # через Keychain Access (поиск по "tech.popovs.aistats" → delete).
  zap trash: [
    "~/Library/Application Support/ai-stats",
    "~/.config/ai-stats",
    "~/Library/Containers/com.sergeytovarov.aistats.widget",
    "~/Library/Preferences/com.sergeytovarov.aistats.plist",
    "~/Library/Saved Application State/com.sergeytovarov.aistats.savedState",
  ]
end
