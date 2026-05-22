# Changelog

Все заметные изменения проекта.
Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

## [Unreleased]

## [0.2.0] — 2026-05-23

### Добавлено
- WidgetKit widget со Small + Medium размерами.
- Период в виджете настраивается через AppIntent (правый клик → Edit Widget): Day / Week / Month.
- Medium показывает топ-4 моделей.
- Миграция базы данных в App Group container (требуется для шаринга с виджетом).
- При успешном sync приложение вызывает WidgetCenter.shared.reloadAllTimelines().

## [0.1.0] — 2026-05-23

### Добавлено
- macOS menu bar app со статус-иконкой и SwiftUI dropdown.
- Сегментированный селектор Day / Week / Month.
- Sparkline-тренд AI-трат за последние 14 дней.
- Shell-out к `ccusage` для агрегатов по Claude Code, Codex и любым другим провайдерам из `enabled_providers`.
- Раздельные DTO под claude и codex (форматы JSON у них разные).
- Свой pricing table — USD за 1M токенов для claude/gpt-5.x. ccusage's costUSD больше не используется (он нулит codex-дни на subscription'е).
- GraphQL-фетчер GitHub-коммитов по всем доступным репозиториям.
- LOC tracking: additions/deletions через Contributor Stats API, недельная гранулярность, exponential backoff 2/4/8/16/16с на 202 Accepted, скип 404/403.
- Локальная SQLite-история с политикой never-decrease — удаление логов агентов не стирает уже накопленную статистику.
- Initial backfill на 365 дней при первом запуске.
- Settings sheet с Export / Import базы данных.
- Создание шаблонного конфига при первом запуске.
