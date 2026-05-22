# Changelog

Все заметные изменения проекта.
Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

## [Unreleased]

## [0.1.0] — 2026-05-22

### Добавлено
- macOS menu bar app со статус-иконкой и SwiftUI dropdown.
- Сегментированный селектор Day / Week / Month.
- Sparkline-тренд AI-трат за последние 14 дней.
- Shell-out к `ccusage` для агрегатов по Claude Code, Codex и любым другим провайдерам из `enabled_providers`.
- GraphQL-фетчер GitHub-коммитов по всем доступным репозиториям.
- Локальная SQLite-история с политикой never-decrease — удаление логов агентов не стирает уже накопленную статистику.
- Initial backfill на 365 дней при первом запуске.
- Settings sheet с Export / Import базы данных.
- Создание шаблонного конфига при первом запуске.
