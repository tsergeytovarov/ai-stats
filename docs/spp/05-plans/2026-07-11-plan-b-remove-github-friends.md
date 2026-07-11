# План B — выпил GitHub-статистики и друзей/лидерборда

> **For agentic workers:** REQUIRED SUB-SKILL: super-puper-powers:subagent-driven-development. Шаги — чекбоксы.

**Goal:** Убрать GitHub-статистику и социальный слой (друзья/лидерборд/blocked), схлопнуть попап в одну вкладку «Расходы», сохранив GitHub-OAuth авторизацию и snapshot-синк.

**Architecture:** Чистое удаление + сжатие. GitHub *fetching* и friends/leaderboard — два переплетённых слоя, делящих SyncCoordinator/WidgetSnapshot/StatsQueries. GitHub *auth* (вход) ортогонален и остаётся. Порядок задач подобран так, чтобы после каждой билд собирался.

**Tech Stack:** Swift/SwiftUI, GRDB, XcodeGen, XCTest. Verify per task: `xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/<Suite>`.

## Global Constraints

- Оставить рабочими: `AuthService`/`GitHubSignInService` (OAuth), `Config.githubToken/githubLogin`, `migrateGithubTokenFromConfig`, `GithubTokenBox`/`GithubLoginBox`, `GithubAvatar` (аватар аккаунта), snapshot-эндпоинты `AiuseAPIClient` (`sendSnapshots`), профиль/удаление аккаунта.
- `friendCode` в DTO (`AuthExchangeResponse`, `ProfileResponse`) остаётся в структурах (серверный контракт), но нигде не показывается и не запрашивается через `regenerateFriendCode`.
- Каждая задача = зелёный билд + зелёные тесты соответствующей группы. Атомарность компиляции: удаление типа и всех его ссылок — в одной задаче.
- Coauthor trailer в каждом коммите: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

### Task B1: Удалить GitHub-fetching

**Verification:** unit (сборка + существующие AI-тесты зелёные; GitHubFetcherTests удаляются).

**Files:**
- Delete: `StatsApp/Sources/GitHubFetcher.swift`, `StatsApp/Sources/GitHubDTO.swift`, `Tests/StatsAppTests/GitHubFetcherTests.swift`, `Tests/StatsAppTests/Fixtures/github-response.json`, `github-commit-history.json`
- Modify: `StatsApp/Sources/FetcherProtocol.swift` — убрать `struct GitHubFetchPayload` (L7-10) и `case github` (L19) из `FetchResult`
- Modify: `StatsApp/AppContainer.swift` — `buildFetchers()` (L232-237) убрать github-источник; `refreshSourcesAfterSignIn()` (L197-204) убрать `"github"`
- Modify: `StatsApp/Sync/SyncCoordinator.swift` — `persist()` (L356-358) убрать `.github` branch
- Modify: `StatsApp/Storage/NeverDecreaseUpserter.swift` — убрать `upsertGitHub`/`upsertGitHubLOCDaily` (L46-49 и тело)
- Modify: `Shared/Storage/Models.swift` — убрать `GitHubRow` (L42), `GitHubLOCDailyRow` (L68)
- Modify: `Shared/Storage/StatsQueries.swift` — убрать `githubTotals`/`githubLOC`/`topRepos`/`dailyAdditionsSeries` и их result-структуры
- Modify: `project.yml` — убрать 2 github-фикстуры из `StatsAppTests` resources
- Modify: `Tests/StatsAppTests/StatsQueriesTests.swift` — убрать `test_githubTotals_*`, `test_githubLOC_*` и их сиды

**Steps:**
- [ ] Удалить файлы и ссылки из списка выше.
- [ ] БД-таблицы `github_activity`/`github_loc_daily` НЕ трогать (миграции v1/v2/v4 остаются — нельзя менять применённые миграции; таблицы становятся мёртвыми).
- [ ] `xcodegen generate` → сборка.
- [ ] Прогнать `StatsAppTests/StatsQueriesTests`, `NeverDecreaseUpserterTests`, `SyncCoordinatorTests` — зелёные.
- [ ] Commit: `refactor(github): убрать сбор статистики коммитов`.

---

### Task B2: Удалить friends/leaderboard/blocked (сеть, синк, кэш)

**Verification:** unit.

**Files:**
- Delete: `StatsApp/Settings/FriendsTabView.swift` + `FriendsTabViewModel.swift`, `BlockedTabView.swift` + `BlockedTabViewModel.swift`, `StatsApp/Network/FriendCode.swift`, `Shared/Design/FriendRow.swift`, `StatsApp/Sync/FriendsPullSyncer.swift`, `LeaderboardPullSyncer.swift`, `StatsApp/Sync/SnapshotSyncer.swift`? — **НЕТ, SnapshotSyncer оставить** (feeds snapshot-синк, не только лидерборд; перепроверить: если он только для лидерборда — удалить). Delete tests: `Network/FriendCodeTests.swift`, `Status/DropdownViewModelAvatarsTests.swift`, `Sync/SnapshotSyncerTests.swift` (если SnapshotSyncer остаётся — тест оставить/переписать).
- Modify: `StatsApp/Network/AiuseAPIClient.swift` — убрать `addFriend`/`listFriends`/`removeFriend` (L124-158), `getLeaderboard` (L162-170), `listBlocks`/`unblock` (L174-192), `getAvatar` (L203-258), `regenerateFriendCode` (L82-89), `allowedAvatarMimes`/`maxAvatarBytes` (L13-17)
- Modify: `StatsApp/Network/AiuseDTO.swift` — убрать friend/leaderboard/block DTO (L95-179), `RegenerateFriendCodeResponse` (L61-69)
- Modify: `Shared/Storage/Models.swift` — убрать `FriendProfileRow` (L195-225), `LeaderboardCacheRow` (L228-246)
- Modify: `Shared/Storage/StatsQueries.swift` — убрать friend-profile/leaderboard-cache функции (MARK L281, L315)
- Modify: `StatsApp/AppContainer.swift` — убрать props/конструирование/wiring friends/leaderboard syncers (L20-21, L85-88, L96-111), `makeFriendsTabViewModel`/`makeBlockedTabViewModel` (L207-223)
- Modify: `StatsApp/Sync/SyncCoordinator.swift` — убрать props (L14-16), init-параметры (L30-39), tick-вызовы (L152-171 частично: оставить snapshotSyncer если он остаётся), `syncAvatarsToWidgetContainer` (L222-265)
- Modify: `Tests/StatsAppTests/Network/AiuseAPIClientTests.swift` — убрать friend/leaderboard/avatar/regenerate тесты (перечень в карте, area 10)

**Steps:**
- [ ] Решить судьбу `SnapshotSyncer`: `grep` его вызовы — если только для сервер-лидерборда, удалить с тестом; если feeds общий snapshot-синк, оставить. (Спека 3: snapshot-синк остаётся.)
- [ ] Удалить файлы и ссылки.
- [ ] БД friend_profiles/leaderboard_cache — миграции v7 не трогать (мёртвые таблицы).
- [ ] `xcodegen generate` → сборка.
- [ ] Тесты `AiuseAPIClientTests`, `SyncCoordinatorTests` зелёные.
- [ ] Commit: `refactor(social): убрать друзей, лидерборд и blocked`.

---

### Task B3: Friend-code блок из вкладки «Аккаунт»

**Verification:** unit.

**Files:**
- Modify: `StatsApp/Settings/AccountTabView.swift` — убрать «Твой код для друзей» + copy (L142-151), «Шарить статистику» toggle (L155-160), «Показывать в публичном лидерборде» (L162-169), regenerate + confirm (L173-186), `showRegenerateConfirm` (L11); поправить `notCreatedView` копию про лидерборд (L42). Оставить: sign-in, имя, delete-account.
- Modify: `StatsApp/Settings/AccountTabViewModel.swift` — убрать `regenerateFriendCode` (L245-258), `toggleSharing` (L212-228), `toggleGlobalOptIn` (L178-187), `onSharingEnabled` (L20-21, L59, L169, L224). Оставить: `signInWithGitHub`, `createAccount`, `updateName`, `deleteAccount`, token/login box.
- Modify: `Tests/StatsAppTests/Settings/AccountTabViewModelTests.swift` — убрать sharing/avatar-seeding тесты (L100, L156, L190, L217), оставить auth-тесты.

**Steps:**
- [ ] Удалить social-блок из AccountTabView и его VM-методы.
- [ ] Решить судьбу `GithubAvatar` seeding (L150-166 VM): аватар аккаунта остаётся → оставить `GithubAvatar.fetch` и seeding, убрать только friends-avatar sync. Перепроверить, что аватар показывается в Аккаунте.
- [ ] `xcodegen generate` → сборка, `AccountTabViewModelTests` зелёные.
- [ ] Commit: `refactor(account): убрать friend-код и шаринг из настроек`.

---

### Task B4: Схлопнуть попап в одну вкладку «Расходы»

**Verification:** unit + acceptance (нет UI-теста рендера попапа — acceptance: открыть попап, видна одна вкладка «Расходы», island без GitHub/Друзей).

**Files:**
- Modify: `StatsApp/Status/DropdownViewModel.swift` — `DropdownSection` (L19-32): убрать `.github`/`.leaderboard`, переименовать `.ai`→`.expenses` (title «Расходы»); убрать github/leaderboard state (L62-76), `loadLeaderboard` (L159-217), `reloadAvatars` (L222-239), github-запросы в `reloadSync` (L118-133); `period.didSet` убрать `loadLeaderboard` (L54)
- Modify: `StatsApp/Status/DropdownView.swift` — `content` switch (L44-53) оставить только `.expenses`; убрать `.task { loadLeaderboard }` (L41)
- Modify: `StatsApp/Status/DropdownSections.swift` — удалить `DropdownGitHubSection` (L121-180), `DropdownLeaderboardSection` (L182-228), `RankDelta` (L32-55); `DropdownAISection`→оставить (переименовать при желании)
- Modify: `StatsApp/Status/IslandControl.swift` — `FloatingIsland` (L91-96): оставить одну пилюлю (или период-сегмент без переключателя категорий — решение по дизайну; минимально: одна пилюля «Расходы»). **Примечание:** после Плана C здесь появится вторая пилюля «Аналитика».
- Modify: `Shared/Design/Crumb.swift` — `CrumbCategory` убрать `.github`/`.friends` (L9, L11), оставить `.ai`; убрать `TextColor.crumbGitHub`/`crumbFriends`
- Modify: `Shared/Design/Sparkline.swift` — `SparklineVariant` убрать `.github` (L11, L18), `Color.githubGreen` (L50-53)
- Modify tests: `UI/CrumbCategoryTests.swift` (убрать github/friends), `UI/SparklineVariantTests.swift` (убрать github)

**Steps:**
- [ ] Переименовать `.ai`→`.expenses`, удалить github/leaderboard секции и state.
- [ ] Island — одна пилюля (заготовка под вторую от Плана C).
- [ ] `xcodegen generate` → сборка, тесты `CrumbCategoryTests`/`SparklineVariantTests` зелёные.
- [ ] Acceptance: собрать `.app`, открыть попап → одна вкладка «Расходы», без GitHub/Друзей.
- [ ] Commit: `refactor(popover): одна вкладка Расходы вместо трёх категорий`.

---

### Task B5: Почистить WidgetSnapshot и виджеты от GitHub/друзей

**Verification:** unit (`WidgetSnapshotTests`, `SyncCoordinatorSnapshotTests` переписать).

**Files:**
- Modify: `Shared/WidgetSnapshot.swift` — убрать top-level `githubEnabled`/`myFriendCode`; из `PeriodSlice` — `commits`/`uniqueRepos`/`leaderboard`; удалить `LeaderboardSlice`+`Entry` (L94-138); убрать avatar-хелперы `WidgetSnapshotIO` (L179-214). `aiCost/aiCostPrev/aiTokens/topModels`, `write/read/*URL` — оставить. **Ввести `schemaVersion: Int = 2`** (decodeIfPresent → default 1; при <2 виджет показывает плейсхолдер — см. Task C-widget).
- Modify: `StatsApp/Sync/SyncCoordinator.swift` — `buildSnapshot` (L176-213), `makeSlice` (L267-297), удалить `makeLeaderboardSlice` (L300-341), `syncAvatarsToWidgetContainer`
- Modify: `StatsWidget/StatsTimelineProvider.swift` — `StatsEntry` убрать `commits`/`uniqueRepos`/`githubEnabled`/`leaderboard`/`myFriendCode` (L10-15), их население (L53-57), emptyEntry (L61-68)
- Modify: `StatsWidget/Views/StatsWidgetView.swift` — SmallView `\(entry.commits) c` (L39), MediumView (L91)
- Modify: `StatsWidget/Views/LargeView.swift` — убрать `\(entry.commits) c` (L21), весь leaderboard-блок (L63-84)
- Modify tests: `WidgetSnapshotTests.swift`, `Sync/SyncCoordinatorSnapshotTests.swift` — убрать leaderboard/commits/friendCode, оставить AI/prev-cost

**Steps:**
- [ ] Убрать github/friends поля из снапшота (additive-decode стиль), ввести `schemaVersion`.
- [ ] Почистить виджет-вью и провайдер.
- [ ] Переписать снапшот-тесты под новую схему.
- [ ] `xcodegen generate` → сборка, снапшот-тесты зелёные.
- [ ] Commit: `refactor(widget): убрать коммиты и лидерборд из снапшота и виджетов`.

---

### Task B6: Settings window + финальная зачистка

**Verification:** unit (полный прогон `StatsAppTests`).

**Files:**
- Modify: `StatsApp/Settings/SettingsView.swift` — убрать `friendsViewModel`/`blockedViewModel` (L18-19), их табы (L38-42). Остаются General/Account.
- Modify: `StatsApp/Settings/SettingsWindowController.swift` — убрать передачу friends/blocked VM (L27-28)
- Modify: `Tests/StatsAppTests/DatabaseTests.swift` — `test_migrate_creates_tables_and_indexes` (L6): таблицы остаются (миграции не трогали) — тест не меняется, только проверить. НЕ убирать github/friend таблицы из ассерта (миграции живы).
- Modify: README + строки локализации — убрать GitHub/друзей секции и скриншоты.

**Steps:**
- [ ] Убрать Friends/Blocked табы из окна настроек.
- [ ] Обновить README (убрать разделы GitHub/друзья/лидерборд/скриншоты).
- [ ] `xcodegen generate` → **полный** `xcodebuild test ... -only-testing:StatsAppTests` — вся сюита зелёная.
- [ ] Commit: `refactor(settings): убрать вкладки Друзья и Заблокированные + docs`.
