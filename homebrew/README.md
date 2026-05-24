# Homebrew Cask для Burn

Этот файл — шаблон Cask formula. Сам по себе в этом репозитории он не подключается к Homebrew — для этого нужен отдельный tap-репозиторий.

## Как опубликовать релиз

1. **Собрать DMG.**
   ```bash
   ./scripts/build-dmg.sh
   ```
   Скрипт выведет SHA256 готового DMG.

2. **Сделать GitHub Release.**
   ```bash
   gh release create v0.2.0 \
       --title "v0.2.0" \
       --notes-from-tag \
       build/burn-0.2.0.dmg
   ```

3. **Обновить Cask formula.**
   - Поменять `version` на новую (если bumpнули).
   - Поменять `sha256` на тот что выплюнул `build-dmg.sh`.
   - Закоммитить в **отдельный tap-репозиторий** (см. ниже).

## Tap-репозиторий

Homebrew Cask требует чтобы formula лежала в репозитории с префиксом `homebrew-`.

Один раз нужно создать репо `tsergeytovarov/homebrew-tap` (или любое название `homebrew-*`), скопировать туда:

```
Casks/ai-stats.rb   <- этот файл
README.md           <- инструкция установки для юзеров
```

После этого пользователи делают:

```bash
brew tap tsergeytovarov/tap
brew install --cask ai-stats
```

Homebrew скачает DMG, проверит SHA256, распакует Burn.app в `/Applications/`, снимет quarantine-атрибут (без Gatekeeper warning).

## Зачем `homebrew/ai-stats.rb` в основном репо

Чтобы:
- Видеть в одном месте всю distribution-инфру (build script + formula).
- При апдейте версии PR-ить можно сразу в оба репо (или скриптом синхронить).
- Шаблон не теряется если внезапно решишь поменять tap-репо.

В будущем formula должна жить **только** в `homebrew-tap` — этот файл здесь это reference.
