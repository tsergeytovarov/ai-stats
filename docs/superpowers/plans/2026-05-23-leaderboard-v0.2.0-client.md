# Лидерборд v0.2.0 — Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Расширить macOS app `ai-stats` клиентской частью лидерборда: профиль создаётся через UI, snapshot'ы тихо уходят на работающий `aiuse.popovs.tech/api`. Без UI лидерборда, без друзей — это будет v0.3.0.

**Architecture:** `AiuseAPIClient` (тонкая обёртка над `URLSession` с Bearer auth) + `KeychainStore` (Security framework) + новая GRDB-миграция (`my_profile`, `pending_snapshots`) + `SnapshotSyncer` (push, интегрирован в существующий `SyncCoordinator`-тик) + новая вкладка «Аккаунт» в Settings через `TabView`.

**Tech Stack:** Swift 5.9, SwiftUI, GRDB 6.x, URLSession (async/await), Security framework для Keychain, XCTest. Backend уже задеплоен — `https://aiuse.popovs.tech/api/`.

**Связанные документы:**
- Спек: [`docs/superpowers/specs/2026-05-23-leaderboard-design.md`](../specs/2026-05-23-leaderboard-design.md)
- Backend план (закрыт): [`2026-05-23-leaderboard-v0.2.0-backend.md`](2026-05-23-leaderboard-v0.2.0-backend.md)
- Backend репо: https://github.com/tsergeytovarov/ai-stats-api

---

## Важное расхождение со спеком

Спек предполагает **hourly** snapshots, но локальная БД хранит только **daily** агрегаты по AI usage (`ai_usage.UNIQUE(day, source)`). `ccusage` CLI не отдаёт hourly granularity.

**Решение в этом плане:** шлём на сервер **один snapshot в день** с `hour_bucket = polnoch' UTC` для этого дня. Сервер хранит данные с hourly precision (как и было), но clients шлют daily-aligned bucket'ы. Лидерборд по day/week/month работает корректно через `SUM`. Когда позже понадобится hourly precision для виджетов — поднимем гранулярность локального хранения отдельной задачей (не сейчас).

Это решение зафиксировано в плане, серверную схему **не меняем**.

---

## File Structure

```
ai-stats/                           # текущий репо, ветка feat/leaderboard-design
├── Shared/
│   └── Storage/
│       ├── Database.swift          # MODIFY: добавить миграцию v5_aiuse_tables
│       └── Models.swift            # MODIFY: MyProfile, PendingSnapshot структуры
├── StatsApp/
│   ├── Config/
│   │   └── Config.swift            # MODIFY: добавить aiuse_api_base_url, defaults
│   ├── Network/                    # NEW DIR
│   │   ├── AiuseDTO.swift          # NEW: Codable DTO для всех API запросов/ответов
│   │   ├── AiuseAPIClient.swift    # NEW: клиент API с Bearer auth
│   │   ├── AiuseAPIError.swift     # NEW: типизированные ошибки сети
│   │   └── KeychainStore.swift     # NEW: protocol + macOS impl + in-memory impl
│   ├── Sync/
│   │   ├── SnapshotSyncer.swift    # NEW: формирование batch + push + retry
│   │   └── SyncCoordinator.swift   # MODIFY: добавить snapshotSyncer в тик
│   ├── Settings/
│   │   ├── SettingsView.swift      # MODIFY: обернуть в TabView
│   │   ├── GeneralTabView.swift    # NEW: extracted из текущего SettingsView
│   │   ├── AccountTabView.swift    # NEW: вкладка «Аккаунт»
│   │   └── AccountTabViewModel.swift # NEW: state + actions
│   └── AppContainer.swift          # MODIFY: wire AiuseAPIClient + KeychainStore + SnapshotSyncer
└── Tests/StatsAppTests/
    ├── Network/                    # NEW DIR
    │   ├── MockURLProtocol.swift   # NEW: тестовый URLProtocol
    │   ├── AiuseAPIClientTests.swift # NEW: все методы клиента через моки
    │   └── KeychainStoreTests.swift # NEW: через in-memory impl
    ├── Sync/                       # NEW DIR
    │   └── SnapshotSyncerTests.swift # NEW: batch + retry + sharing_enabled=false
    └── Fixtures/                   # MODIFY: + api-* JSON
        ├── api-create-profile.json # NEW
        ├── api-patch-profile.json  # NEW
        ├── api-regenerate.json     # NEW
        └── api-snapshots-response.json # NEW
```

Существующие файлы я не трогаю (sparkline, fetchers, dropdown view) — клиентская часть aiuse — параллельный модуль.

---

## Phase A: Config + GRDB schema

### Task 1: Config — добавить aiuse_api_base_url

**Files:**
- Modify: `StatsApp/Config/Config.swift`
- Modify: `StatsApp/Tests/StatsAppTests/` — если есть ConfigTests (проверю); если нет — пропускаем

- [ ] **Step 1: Прочитать существующий Config.swift**

```bash
cat /Users/sergeytovarov/work/ai-stats/StatsApp/Config/Config.swift
```

Понять текущую схему: ConfigLoader, поля `github_token`, `github_login`, `sync_interval_minutes`, `ccusage_command`, `enabled_providers`.

- [ ] **Step 2: Добавить поле и default**

В struct `Config` добавить:
```swift
let aiuseApiBaseURL: String  // default: https://aiuse.popovs.tech/api
```

В JSON-параметре `Config.init(from decoder:)` или соответствующем decoder'е:
```swift
self.aiuseApiBaseURL = (try? container.decode(String.self, forKey: .aiuseApiBaseURL))
    ?? "https://aiuse.popovs.tech/api"
```

В `CodingKeys` добавить `case aiuseApiBaseURL = "aiuse_api_base_url"`.

В `ConfigLoader.defaultConfig()` (если есть) добавить поле.

- [ ] **Step 3: Собрать через xcodegen + xcodebuild**

```bash
cd /Users/sergeytovarov/work/ai-stats
xcodegen generate
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Коммит**

```bash
git add StatsApp/Config/Config.swift
git commit -m "feat(config): добавить aiuse_api_base_url с дефолтом prod"
```

---

### Task 2: GRDB миграция v5 — my_profile, pending_snapshots

**Files:**
- Modify: `Shared/Storage/Database.swift`

- [ ] **Step 1: Добавить миграцию**

В функцию `migrate(_:)` после `v4_replace_loc_weekly_with_daily` добавить:

```swift
migrator.registerMigration("v5_aiuse_tables") { db in
    // Свой профиль — singleton (id всегда = 1)
    try db.execute(sql: """
        CREATE TABLE my_profile (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            friend_code TEXT NOT NULL,
            display_name TEXT NOT NULL,
            avatar_path TEXT,
            sharing_enabled INTEGER NOT NULL DEFAULT 1,
            server_user_id INTEGER NOT NULL
        )
    """)

    // Очередь snapshot'ов для отправки на сервер
    try db.execute(sql: """
        CREATE TABLE pending_snapshots (
            hour_bucket INTEGER PRIMARY KEY,
            tokens_input INTEGER NOT NULL,
            tokens_output INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT
        )
    """)
}
```

`hour_bucket` хранится как unix timestamp в секундах (Int). Для нашего daily-aligned варианта это будет midnight UTC = unix-timestamp(date * 86400).

- [ ] **Step 2: Сборка**

```bash
xcodegen generate && xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Тест миграции (если есть DatabaseTests)**

```bash
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination "platform=macOS" 2>&1 | tail -20
```

Expected: existing tests still pass; новых тестов для миграции не нужно — она просто DDL.

- [ ] **Step 4: Коммит**

```bash
git add Shared/Storage/Database.swift
git commit -m "feat(db): миграция v5 — my_profile + pending_snapshots"
```

---

### Task 3: Models.swift — структуры MyProfile, PendingSnapshot

**Files:**
- Modify: `Shared/Storage/Models.swift`

- [ ] **Step 1: Прочитать Models.swift, понять паттерн**

```bash
cat /Users/sergeytovarov/work/ai-stats/Shared/Storage/Models.swift
```

Существующие `AIUsageRow`, `GitHubActivityRow` и т.д. — это `FetchableRecord & PersistableRecord` со статическим `databaseTableName`.

- [ ] **Step 2: Добавить MyProfile и PendingSnapshot**

В конец `Models.swift` добавить:

```swift
struct MyProfileRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "my_profile"

    var id: Int64 = 1
    var friendCode: String
    var displayName: String
    var avatarPath: String?
    var sharingEnabled: Bool
    var serverUserId: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case friendCode = "friend_code"
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case sharingEnabled = "sharing_enabled"
        case serverUserId = "server_user_id"
    }
}

struct PendingSnapshotRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pending_snapshots"

    var hourBucket: Int64        // unix timestamp в секундах
    var tokensInput: Int64
    var tokensOutput: Int64
    var attempts: Int = 0
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case hourBucket = "hour_bucket"
        case tokensInput = "tokens_input"
        case tokensOutput = "tokens_output"
        case attempts
        case lastError = "last_error"
    }

    enum Columns: String, ColumnExpression {
        case hourBucket = "hour_bucket"
        case attempts
    }
}
```

- [ ] **Step 3: Собрать**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Коммит**

```bash
git add Shared/Storage/Models.swift
git commit -m "feat(db): MyProfileRow + PendingSnapshotRow GRDB модели"
```

---

## Phase B: Keychain

### Task 4: KeychainStore — protocol + macOS impl + in-memory

**Files:**
- Create: `StatsApp/Network/KeychainStore.swift`

- [ ] **Step 1: Создать файл с protocol и двумя реализациями**

```swift
import Foundation
import Security

/// Чтение/запись api_secret в Keychain. Тестируется через MemoryKeychainStore.
protocol KeychainStore {
    func get(account: String, service: String) -> String?
    func set(_ value: String, account: String, service: String) throws
    func delete(account: String, service: String) throws
}

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case encodingFailed
}

/// Production-реализация через Security framework.
final class MacOSKeychainStore: KeychainStore {
    func get(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func set(_ value: String, account: String, service: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]
        // Сначала пробуем update; если нет — add.
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// In-memory реализация для тестов.
final class MemoryKeychainStore: KeychainStore {
    private var storage: [String: String] = [:]
    private func key(_ account: String, _ service: String) -> String { "\(service)/\(account)" }

    func get(account: String, service: String) -> String? {
        storage[key(account, service)]
    }
    func set(_ value: String, account: String, service: String) throws {
        storage[key(account, service)] = value
    }
    func delete(account: String, service: String) throws {
        storage.removeValue(forKey: key(account, service))
    }
}

/// Константы для aiuse — где лежит api_secret.
enum AiuseKeychain {
    static let service = "tech.popovs.aiuse"
    static let account = "aiuse-api-secret"
}
```

- [ ] **Step 2: Собрать**

```bash
xcodegen generate && xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Коммит**

```bash
git add StatsApp/Network/KeychainStore.swift
git commit -m "feat(keychain): protocol + macOS impl + in-memory impl"
```

---

### Task 5: KeychainStoreTests через in-memory impl

**Files:**
- Create: `Tests/StatsAppTests/Network/KeychainStoreTests.swift`

- [ ] **Step 1: Создать тесты**

```swift
import XCTest
@testable import StatsApp

final class KeychainStoreTests: XCTestCase {
    var store: KeychainStore!

    override func setUp() {
        super.setUp()
        store = MemoryKeychainStore()
    }

    func testSetAndGetRoundtrip() throws {
        try store.set("secret-value", account: "test", service: "test-service")
        XCTAssertEqual(store.get(account: "test", service: "test-service"), "secret-value")
    }

    func testGetReturnsNilWhenMissing() {
        XCTAssertNil(store.get(account: "missing", service: "test-service"))
    }

    func testSetOverwritesExisting() throws {
        try store.set("old", account: "test", service: "svc")
        try store.set("new", account: "test", service: "svc")
        XCTAssertEqual(store.get(account: "test", service: "svc"), "new")
    }

    func testDeleteRemovesValue() throws {
        try store.set("v", account: "test", service: "svc")
        try store.delete(account: "test", service: "svc")
        XCTAssertNil(store.get(account: "test", service: "svc"))
    }

    func testDeleteMissingDoesNotThrow() throws {
        try store.delete(account: "never-existed", service: "svc")
    }

    func testDifferentServicesAreIsolated() throws {
        try store.set("a", account: "user", service: "svc-1")
        try store.set("b", account: "user", service: "svc-2")
        XCTAssertEqual(store.get(account: "user", service: "svc-1"), "a")
        XCTAssertEqual(store.get(account: "user", service: "svc-2"), "b")
    }
}
```

- [ ] **Step 2: Запустить**

```bash
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp \
  -destination "platform=macOS" -only-testing:StatsAppTests/KeychainStoreTests 2>&1 | tail -15
```

Expected: 6 tests PASS.

- [ ] **Step 3: Коммит**

```bash
git add Tests/StatsAppTests/Network/KeychainStoreTests.swift
git commit -m "test(keychain): покрытие in-memory impl"
```

---

## Phase C: API Client

### Task 6: AiuseDTO — Codable DTO

**Files:**
- Create: `StatsApp/Network/AiuseDTO.swift`

- [ ] **Step 1: Создать файл со всеми DTO**

```swift
import Foundation

// MARK: - profiles

struct ProfileCreateRequest: Codable {
    let displayName: String
    let avatarB64: String?
    let avatarMime: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarB64 = "avatar_b64"
        case avatarMime = "avatar_mime"
    }
}

struct ProfileCreateResponse: Codable {
    let friendCode: String
    let apiSecret: String
    let serverUserId: Int64

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case apiSecret = "api_secret"
        case serverUserId = "server_user_id"
    }
}

struct ProfileUpdateRequest: Codable {
    let displayName: String?
    let avatarB64: String?
    let avatarMime: String?
    let sharingEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarB64 = "avatar_b64"
        case avatarMime = "avatar_mime"
        case sharingEnabled = "sharing_enabled"
    }
}

struct ProfileResponse: Codable {
    let friendCode: String
    let displayName: String
    let sharingEnabled: Bool
    let createdAt: String  // ISO 8601

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case displayName = "display_name"
        case sharingEnabled = "sharing_enabled"
        case createdAt = "created_at"
    }
}

struct RegenerateFriendCodeResponse: Codable {
    let friendCode: String
    let friendshipsDropped: Int

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case friendshipsDropped = "friendships_dropped"
    }
}

// MARK: - snapshots

struct SnapshotItem: Codable {
    let hourBucket: String  // ISO 8601, UTC
    let tokensInput: Int64
    let tokensOutput: Int64

    enum CodingKeys: String, CodingKey {
        case hourBucket = "hour_bucket"
        case tokensInput = "tokens_input"
        case tokensOutput = "tokens_output"
    }
}

struct SnapshotsBatch: Codable {
    let snapshots: [SnapshotItem]
}

struct SnapshotsResponse: Codable {
    let accepted: Int
}
```

- [ ] **Step 2: Собрать**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Коммит**

```bash
git add StatsApp/Network/AiuseDTO.swift
git commit -m "feat(api): Codable DTO для aiuse-api"
```

---

### Task 7: AiuseAPIError + AiuseAPIClient skeleton

**Files:**
- Create: `StatsApp/Network/AiuseAPIError.swift`
- Create: `StatsApp/Network/AiuseAPIClient.swift`

- [ ] **Step 1: AiuseAPIError**

```swift
import Foundation

enum AiuseAPIError: Error, Equatable {
    case missingSecret           // нет в Keychain
    case invalidURL
    case transport(String)       // network failure
    case http(status: Int, body: String)
    case decoding(String)
    case unexpected
}
```

- [ ] **Step 2: AiuseAPIClient skeleton — init и helper'ы**

```swift
import Foundation

final class AiuseAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let secretProvider: () -> String?

    init(baseURL: URL,
         secretProvider: @escaping () -> String?,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.secretProvider = secretProvider
        self.session = session
    }

    /// Базовый helper. authed=true прикладывает Bearer.
    private func request<R: Decodable>(
        path: String,
        method: String,
        body: Encodable? = nil,
        authed: Bool = true,
        decodeAs: R.Type
    ) async throws -> R {
        var url = baseURL
        url.append(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authed {
            guard let secret = secretProvider() else { throw AiuseAPIError.missingSecret }
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            let encoder = JSONEncoder()
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AiuseAPIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AiuseAPIError.unexpected
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AiuseAPIError.http(status: http.statusCode, body: body)
        }

        // 204 No Content
        if R.self == EmptyResponse.self {
            return EmptyResponse() as! R
        }

        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            throw AiuseAPIError.decoding(error.localizedDescription)
        }
    }
}

/// Маркер для эндпоинтов с пустым ответом (204).
struct EmptyResponse: Decodable {}

/// Type-erased wrapper для Encodable (нужен потому что у JSONEncoder.encode сигнатура generic).
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        _encode = wrapped.encode
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
```

- [ ] **Step 3: Собрать**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Коммит**

```bash
git add StatsApp/Network/AiuseAPIError.swift StatsApp/Network/AiuseAPIClient.swift
git commit -m "feat(api): AiuseAPIError + AiuseAPIClient skeleton с Bearer auth"
```

---

### Task 8: AiuseAPIClient — createProfile

**Files:**
- Modify: `StatsApp/Network/AiuseAPIClient.swift`

- [ ] **Step 1: Добавить метод**

В конец класса `AiuseAPIClient`:

```swift
func createProfile(displayName: String,
                   avatar: Data? = nil,
                   avatarMime: String? = nil) async throws -> ProfileCreateResponse {
    let body = ProfileCreateRequest(
        displayName: displayName,
        avatarB64: avatar?.base64EncodedString(),
        avatarMime: avatarMime
    )
    return try await request(
        path: "/profiles",
        method: "POST",
        body: body,
        authed: false,
        decodeAs: ProfileCreateResponse.self
    )
}
```

- [ ] **Step 2: Собрать**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Коммит**

```bash
git add StatsApp/Network/AiuseAPIClient.swift
git commit -m "feat(api): AiuseAPIClient.createProfile"
```

---

### Task 9: AiuseAPIClient — patchProfile, regenerate, deleteAccount

**Files:**
- Modify: `StatsApp/Network/AiuseAPIClient.swift`

- [ ] **Step 1: Добавить три метода**

```swift
func patchProfile(displayName: String? = nil,
                  avatar: Data? = nil,
                  avatarMime: String? = nil,
                  sharingEnabled: Bool? = nil) async throws -> ProfileResponse {
    let body = ProfileUpdateRequest(
        displayName: displayName,
        avatarB64: avatar?.base64EncodedString(),
        avatarMime: avatarMime,
        sharingEnabled: sharingEnabled
    )
    return try await request(
        path: "/profiles/me",
        method: "PATCH",
        body: body,
        authed: true,
        decodeAs: ProfileResponse.self
    )
}

func regenerateFriendCode() async throws -> RegenerateFriendCodeResponse {
    return try await request(
        path: "/profiles/me/regenerate-friend-code",
        method: "POST",
        authed: true,
        decodeAs: RegenerateFriendCodeResponse.self
    )
}

func deleteAccount() async throws {
    _ = try await request(
        path: "/profiles/me",
        method: "DELETE",
        authed: true,
        decodeAs: EmptyResponse.self
    )
}
```

- [ ] **Step 2: Собрать**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Коммит**

```bash
git add StatsApp/Network/AiuseAPIClient.swift
git commit -m "feat(api): AiuseAPIClient.patchProfile, regenerate, deleteAccount"
```

---

### Task 10: AiuseAPIClient — sendSnapshots

**Files:**
- Modify: `StatsApp/Network/AiuseAPIClient.swift`

- [ ] **Step 1: Добавить метод**

```swift
func sendSnapshots(_ batch: [SnapshotItem]) async throws -> SnapshotsResponse {
    let body = SnapshotsBatch(snapshots: batch)
    return try await request(
        path: "/snapshots",
        method: "POST",
        body: body,
        authed: true,
        decodeAs: SnapshotsResponse.self
    )
}
```

- [ ] **Step 2: Собрать**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Коммит**

```bash
git add StatsApp/Network/AiuseAPIClient.swift
git commit -m "feat(api): AiuseAPIClient.sendSnapshots"
```

---

### Task 11: MockURLProtocol + AiuseAPIClientTests

**Files:**
- Create: `Tests/StatsAppTests/Network/MockURLProtocol.swift`
- Create: `Tests/StatsAppTests/Network/AiuseAPIClientTests.swift`

- [ ] **Step 1: MockURLProtocol**

```swift
import Foundation

/// Тестовый URLProtocol — подменяет ответ для любого URLRequest.
/// Использование:
///   MockURLProtocol.responder = { req in
///     return (HTTPURLResponse(...), Data(...))
///   }
///   let config = URLSessionConfiguration.ephemeral
///   config.protocolClasses = [MockURLProtocol.self]
///   let session = URLSession(configuration: config)
final class MockURLProtocol: URLProtocol {
    /// (response, data) — оба обязательны.
    static var responder: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Заглядывание для тестов (последний запрос).
    static var lastRequest: URLRequest?
    static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        MockURLProtocol.lastBody = request.httpBody ?? request.bodyStreamData()

        guard let responder = MockURLProtocol.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try responder(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// httpBodyStream → Data (URLSession превращает body в stream при отправке).
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
```

- [ ] **Step 2: AiuseAPIClientTests — createProfile**

```swift
import XCTest
@testable import StatsApp

final class AiuseAPIClientTests: XCTestCase {
    var client: AiuseAPIClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        client = AiuseAPIClient(
            baseURL: URL(string: "https://test.local/api")!,
            secretProvider: { "test-secret" },
            session: session
        )
        MockURLProtocol.responder = nil
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.lastBody = nil
    }

    func testCreateProfile_sendsBodyWithoutAuthHeader() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles")!,
                statusCode: 201, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = #"{"friend_code":"XK7P3M9Q2A","api_secret":"deadbeef","server_user_id":42}"#
            return (resp, json.data(using: .utf8)!)
        }
        let result = try await client.createProfile(displayName: "Серёжа")
        XCTAssertEqual(result.friendCode, "XK7P3M9Q2A")
        XCTAssertEqual(result.apiSecret, "deadbeef")
        XCTAssertEqual(result.serverUserId, 42)

        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.url?.path, "/api/profiles")
        XCTAssertNil(req?.value(forHTTPHeaderField: "Authorization"))

        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        let decoded = try JSONDecoder().decode([String: String?].self, from: body)
        XCTAssertEqual(decoded["display_name"], "Серёжа")
    }

    func testCreateProfile_with4xx_throwsHTTPError() async {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles")!,
                statusCode: 422, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("validation failed".utf8))
        }
        do {
            _ = try await client.createProfile(displayName: "")
            XCTFail("expected error")
        } catch let AiuseAPIError.http(status, _) {
            XCTAssertEqual(status, 422)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSendSnapshots_putsBearerAndBody() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/snapshots")!,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data(#"{"accepted":1}"#.utf8))
        }
        let result = try await client.sendSnapshots([
            SnapshotItem(hourBucket: "2026-05-23T00:00:00Z", tokensInput: 100, tokensOutput: 200)
        ])
        XCTAssertEqual(result.accepted, 1)
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer test-secret")
    }

    func testRegenerateFriendCode_returnsNewCode() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(url: URL(string: "https://test.local/api/profiles/me/regenerate-friend-code")!,
                                       statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data(#"{"friend_code":"NEW1234567","friendships_dropped":3}"#.utf8))
        }
        let result = try await client.regenerateFriendCode()
        XCTAssertEqual(result.friendCode, "NEW1234567")
        XCTAssertEqual(result.friendshipsDropped, 3)
    }

    func testDeleteAccount_sendsDelete() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(url: URL(string: "https://test.local/api/profiles/me")!,
                                       statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        try await client.deleteAccount()
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "DELETE")
    }

    func testMissingSecret_throwsImmediately() async {
        let session = URLSession(configuration: { let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [MockURLProtocol.self]; return c }())
        let clientNoSecret = AiuseAPIClient(
            baseURL: URL(string: "https://test.local/api")!,
            secretProvider: { nil },
            session: session
        )
        do {
            _ = try await clientNoSecret.sendSnapshots([])
            XCTFail("expected missingSecret")
        } catch AiuseAPIError.missingSecret {
            // OK
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}
```

- [ ] **Step 3: Запустить**

```bash
xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp \
  -destination "platform=macOS" -only-testing:StatsAppTests/AiuseAPIClientTests 2>&1 | tail -15
```

Expected: 6 tests PASS.

- [ ] **Step 4: Коммит**

```bash
git add Tests/StatsAppTests/Network/
git commit -m "test(api): AiuseAPIClient — 6 тестов с MockURLProtocol"
```

---

## Phase D: Snapshot syncer

### Task 12: StatsQueries — функции для pending_snapshots

**Files:**
- Modify: `Shared/Storage/StatsQueries.swift`

- [ ] **Step 1: Прочитать существующий StatsQueries.swift**

```bash
cat /Users/sergeytovarov/work/ai-stats/Shared/Storage/StatsQueries.swift
```

Понять паттерн (наверняка функции вида `func aiUsageDaily(db: Database, from: Date, to: Date) -> [...]`).

- [ ] **Step 2: Добавить функции для pending_snapshots и my_profile**

В конец `StatsQueries.swift`:

```swift
import Foundation
import GRDB

extension StatsQueries {  // если есть существующая namespace; иначе сделать в module-level

    // MARK: - My profile

    static func loadMyProfile(_ db: Database) throws -> MyProfileRow? {
        try MyProfileRow.fetchOne(db, key: 1)
    }

    static func saveMyProfile(_ db: Database, _ profile: MyProfileRow) throws {
        try profile.save(db)
    }

    static func deleteMyProfile(_ db: Database) throws {
        _ = try MyProfileRow.deleteOne(db, key: 1)
    }

    // MARK: - Pending snapshots

    static func upsertPendingSnapshot(_ db: Database,
                                      hourBucket: Int64,
                                      tokensInput: Int64,
                                      tokensOutput: Int64) throws {
        let row = PendingSnapshotRow(
            hourBucket: hourBucket,
            tokensInput: tokensInput,
            tokensOutput: tokensOutput,
            attempts: 0,
            lastError: nil
        )
        try row.save(db)
    }

    static func loadReadyPendingSnapshots(_ db: Database, maxAttempts: Int = 5, limit: Int = 168) throws -> [PendingSnapshotRow] {
        try PendingSnapshotRow
            .filter(PendingSnapshotRow.Columns.attempts < maxAttempts)
            .order(PendingSnapshotRow.Columns.hourBucket.desc)
            .limit(limit)
            .fetchAll(db)
    }

    static func deletePendingSnapshots(_ db: Database, hourBuckets: [Int64]) throws {
        guard !hourBuckets.isEmpty else { return }
        _ = try PendingSnapshotRow
            .filter(hourBuckets.contains(PendingSnapshotRow.Columns.hourBucket))
            .deleteAll(db)
    }

    static func incrementAttempts(_ db: Database, hourBuckets: [Int64], lastError: String) throws {
        guard !hourBuckets.isEmpty else { return }
        for bucket in hourBuckets {
            if var row = try PendingSnapshotRow.fetchOne(db, key: bucket) {
                row.attempts += 1
                row.lastError = lastError
                try row.update(db)
            }
        }
    }
}
```

Если в проекте `StatsQueries` не enum/struct namespace — оборачивающие функции просто на module-level или внутри уже существующей структуры. Адаптировать к существующему стилю.

- [ ] **Step 3: Собрать**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Коммит**

```bash
git add Shared/Storage/StatsQueries.swift
git commit -m "feat(db): queries для my_profile и pending_snapshots"
```

---

### Task 13: SnapshotSyncer — формирование batch + push

**Files:**
- Create: `StatsApp/Sync/SnapshotSyncer.swift`

- [ ] **Step 1: Создать SnapshotSyncer**

```swift
import Foundation
import GRDB

/// Тянет суммы tokens (input+output без кэша) из локальной БД и шлёт на сервер.
/// Daily-aligned bucket'ы: один snapshot на день, hour_bucket = midnight UTC.
@MainActor
final class SnapshotSyncer {
    private let db: any DatabaseWriter
    private let api: AiuseAPIClient
    private let now: () -> Date

    init(db: any DatabaseWriter,
         api: AiuseAPIClient,
         now: @escaping () -> Date = Date.init) {
        self.db = db
        self.api = api
        self.now = now
    }

    /// Один тик: обновить pending_snapshots из локальной БД и отправить.
    /// Возвращает количество принятых сервером snapshot'ов.
    func runOnce() async throws -> Int {
        // 1. Только если есть профиль и шаринг включен — иначе ничего не делаем.
        let profile = try await db.read { try StatsQueries.loadMyProfile($0) }
        guard let profile, profile.sharingEnabled else {
            return 0
        }

        // 2. Обновить pending_snapshots из ai_usage за последние 7 дней.
        try await refreshPendingFromLocalDB()

        // 3. Прочитать pending, отправить, отметить accepted.
        let pending = try await db.read { try StatsQueries.loadReadyPendingSnapshots($0) }
        guard !pending.isEmpty else { return 0 }

        let items = pending.map { row in
            SnapshotItem(
                hourBucket: Self.iso8601(from: row.hourBucket),
                tokensInput: row.tokensInput,
                tokensOutput: row.tokensOutput
            )
        }

        do {
            let result = try await api.sendSnapshots(items)
            let buckets = pending.map { $0.hourBucket }
            try await db.write { try StatsQueries.deletePendingSnapshots($0, hourBuckets: buckets) }
            return result.accepted
        } catch {
            let buckets = pending.map { $0.hourBucket }
            let message = "\(error)"
            try await db.write { try StatsQueries.incrementAttempts($0, hourBuckets: buckets, lastError: message) }
            throw error
        }
    }

    private func refreshPendingFromLocalDB() async throws {
        // Берём агрегаты ai_usage за последние 7 дней.
        // ВАЖНО: ai_usage хранит daily, и hour_bucket = midnight UTC соответствующего дня.
        // Это решение зафиксировано в плане v0.2.0-client (расхождение со спеком).
        let cutoff = now().addingTimeInterval(-7 * 24 * 3600)
        let isoDay = ISO8601DateFormatter()
        isoDay.formatOptions = [.withFullDate]

        try await db.write { db in
            // Запрашиваем sum tokens_input/output GROUP BY day за последние 7 дней
            let cutoffDay = isoDay.string(from: cutoff)
            let rows = try Row.fetchAll(db, sql: """
                SELECT day,
                       SUM(input_tokens) AS sum_input,
                       SUM(output_tokens) AS sum_output
                FROM ai_usage
                WHERE day >= ?
                GROUP BY day
                """, arguments: [cutoffDay])

            for row in rows {
                let day: String = row["day"]
                let input: Int64 = row["sum_input"] ?? 0
                let output: Int64 = row["sum_output"] ?? 0
                guard let bucket = Self.midnightUTCUnixTimestamp(fromIsoDay: day) else { continue }
                try StatsQueries.upsertPendingSnapshot(
                    db, hourBucket: bucket, tokensInput: input, tokensOutput: output
                )
            }
        }
    }

    /// "2026-05-23" → unix timestamp полночи UTC.
    static func midnightUTCUnixTimestamp(fromIsoDay day: String) -> Int64? {
        var components = DateComponents()
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.timeZone = TimeZone(identifier: "UTC")
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return nil }
        return Int64(date.timeIntervalSince1970)
    }

    /// unix timestamp → "2026-05-23T00:00:00Z" (полная ISO 8601 UTC).
    static func iso8601(from unixSeconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 2: Собрать**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -15
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Коммит**

```bash
git add StatsApp/Sync/SnapshotSyncer.swift
git commit -m "feat(sync): SnapshotSyncer с daily-aligned bucket'ами"
```

---

### Task 14: SnapshotSyncerTests

**Files:**
- Create: `Tests/StatsAppTests/Sync/SnapshotSyncerTests.swift`

- [ ] **Step 1: Создать тесты**

```swift
import XCTest
import GRDB
@testable import StatsApp

final class SnapshotSyncerTests: XCTestCase {
    var db: DatabaseQueue!
    var apiCalls: [SnapshotItem] = []
    var apiResponse: Result<SnapshotsResponse, Error> = .success(SnapshotsResponse(accepted: 0))

    override func setUp() async throws {
        try await super.setUp()
        db = try DatabaseQueue()
        try Database.migrate(db)
        apiCalls = []
    }

    private func makeSyncer() -> SnapshotSyncer {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let captureCalls = self
        MockURLProtocol.responder = { req in
            // Захватываем body
            if let body = req.httpBody ?? req.bodyStreamDataIfPossible(),
               let batch = try? JSONDecoder().decode(SnapshotsBatch.self, from: body) {
                captureCalls.apiCalls.append(contentsOf: batch.snapshots)
            }
            switch captureCalls.apiResponse {
            case .success(let resp):
                let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                let data = try JSONEncoder().encode(resp)
                return (http, data)
            case .failure(let err):
                throw err
            }
        }
        let api = AiuseAPIClient(
            baseURL: URL(string: "https://test.local/api")!,
            secretProvider: { "secret" },
            session: session
        )
        return SnapshotSyncer(db: db, api: api, now: { Date(timeIntervalSince1970: 1747958400) }) // 2026-05-23
    }

    /// helper для вставки фиктивной usage-записи
    private func insertUsage(day: String, input: Int64, output: Int64, source: String = "claude") throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO ai_usage (day, source, models_json, input_tokens, output_tokens, cost_usd, updated_at)
                VALUES (?, ?, '[]', ?, ?, 0.0, '2026-05-23T00:00:00Z')
                """, arguments: [day, source, input, output])
        }
    }

    /// helper для вставки my_profile
    private func insertMyProfile(sharingEnabled: Bool = true) throws {
        try db.write { db in
            let p = MyProfileRow(
                id: 1, friendCode: "TESTCODE12",
                displayName: "Test", avatarPath: nil,
                sharingEnabled: sharingEnabled, serverUserId: 1
            )
            try p.save(db)
        }
    }

    // MARK: - Tests

    func testNoProfile_skipsSync() async throws {
        try insertUsage(day: "2026-05-22", input: 100, output: 200)
        apiResponse = .success(SnapshotsResponse(accepted: 1))

        let syncer = makeSyncer()
        let accepted = try await syncer.runOnce()

        XCTAssertEqual(accepted, 0)
        XCTAssertEqual(apiCalls.count, 0, "should not call API without profile")
    }

    func testSharingDisabled_skipsSync() async throws {
        try insertMyProfile(sharingEnabled: false)
        try insertUsage(day: "2026-05-22", input: 100, output: 200)

        let syncer = makeSyncer()
        let accepted = try await syncer.runOnce()

        XCTAssertEqual(accepted, 0)
        XCTAssertEqual(apiCalls.count, 0)
    }

    func testHappyPath_sendsDailySnapshots() async throws {
        try insertMyProfile()
        try insertUsage(day: "2026-05-22", input: 100, output: 200)
        try insertUsage(day: "2026-05-23", input: 50, output: 80)
        apiResponse = .success(SnapshotsResponse(accepted: 2))

        let syncer = makeSyncer()
        let accepted = try await syncer.runOnce()

        XCTAssertEqual(accepted, 2)
        XCTAssertEqual(apiCalls.count, 2)
        let buckets = Set(apiCalls.map { $0.hourBucket })
        XCTAssertTrue(buckets.contains("2026-05-22T00:00:00Z"))
        XCTAssertTrue(buckets.contains("2026-05-23T00:00:00Z"))

        // После успеха pending должен быть пуст
        let remaining = try await db.read { try StatsQueries.loadReadyPendingSnapshots($0) }
        XCTAssertEqual(remaining.count, 0)
    }

    func testMultipleProvidersSummed() async throws {
        try insertMyProfile()
        try insertUsage(day: "2026-05-22", input: 100, output: 200, source: "claude")
        try insertUsage(day: "2026-05-22", input: 10, output: 20, source: "codex")

        apiResponse = .success(SnapshotsResponse(accepted: 1))
        let syncer = makeSyncer()
        _ = try await syncer.runOnce()

        XCTAssertEqual(apiCalls.count, 1)
        XCTAssertEqual(apiCalls.first?.tokensInput, 110)
        XCTAssertEqual(apiCalls.first?.tokensOutput, 220)
    }

    func testApiFailure_incrementsAttempts() async throws {
        try insertMyProfile()
        try insertUsage(day: "2026-05-22", input: 100, output: 200)
        apiResponse = .failure(AiuseAPIError.http(status: 500, body: "boom"))

        let syncer = makeSyncer()
        do {
            _ = try await syncer.runOnce()
            XCTFail("expected error")
        } catch {
            // OK
        }

        let pending = try await db.read { try StatsQueries.loadReadyPendingSnapshots($0) }
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.attempts, 1)
        XCTAssertNotNil(pending.first?.lastError)
    }

    func testRetryAfterFailure_succeeds() async throws {
        try insertMyProfile()
        try insertUsage(day: "2026-05-22", input: 100, output: 200)

        // 1-й call: fail
        apiResponse = .failure(AiuseAPIError.http(status: 503, body: ""))
        let syncer = makeSyncer()
        _ = try? await syncer.runOnce()

        // 2-й call: success
        apiResponse = .success(SnapshotsResponse(accepted: 1))
        let accepted = try await syncer.runOnce()
        XCTAssertEqual(accepted, 1)

        // pending очищен
        let remaining = try await db.read { try StatsQueries.loadReadyPendingSnapshots($0) }
        XCTAssertEqual(remaining.count, 0)
    }
}

private extension URLRequest {
    func bodyStreamDataIfPossible() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: 4096)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}
```

- [ ] **Step 2: Запустить**

```bash
xcodegen generate && xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp \
  -destination "platform=macOS" -only-testing:StatsAppTests/SnapshotSyncerTests 2>&1 | tail -15
```

Expected: 6 tests PASS.

- [ ] **Step 3: Коммит**

```bash
git add Tests/StatsAppTests/Sync/SnapshotSyncerTests.swift
git commit -m "test(sync): SnapshotSyncer — happy path, sharing off, retry, sum по providers"
```

---

### Task 15: SyncCoordinator — добавить snapshotSyncer в тик

**Files:**
- Modify: `StatsApp/Sync/SyncCoordinator.swift`

- [ ] **Step 1: Изменить SyncCoordinator чтобы он держал опционально SnapshotSyncer**

В существующий класс добавить:

```swift
private let snapshotSyncer: SnapshotSyncer?

init(db: any DatabaseWriter,
     snapshotSyncer: SnapshotSyncer? = nil,
     now: @escaping () -> Date = Date.init) {
    self.db = db
    self.snapshotSyncer = snapshotSyncer
    self.now = now
}
```

(Сохрани совместимость — `snapshotSyncer = nil` по умолчанию.)

В `startTimer(...)`, в Timer-callback'е после прохода по существующим sources добавить:

```swift
Task { @MainActor in
    for (name, fetchers) in sources {
        try? await self.runOnce(source: name, fetchers: fetchers)
    }
    // После основного sync — пушим snapshot'ы на сервер (если syncer wired).
    if let syncer = self.snapshotSyncer {
        do {
            _ = try await syncer.runOnce()
        } catch {
            NSLog("ai-stats aiuse sync error: \(error)")
        }
    }
}
```

В `runOnce(source:fetchers:)` — единичный вызов из `start()` (initial sync) тоже после неё добавить snapshot push:

```swift
// (после существующих строк WidgetCenter.reload и т.д.)
if source == "ccusage", let syncer = snapshotSyncer {
    do {
        _ = try await syncer.runOnce()
    } catch {
        NSLog("ai-stats aiuse sync error after ccusage: \(error)")
    }
}
```

(Чтобы snapshot'ы pushились сразу после fresh ccusage data — а не через 5 минут.)

- [ ] **Step 2: Собрать**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Коммит**

```bash
git add StatsApp/Sync/SyncCoordinator.swift
git commit -m "feat(sync): интеграция SnapshotSyncer в SyncCoordinator-тик"
```

---

## Phase E: Settings UI

### Task 16: SettingsView — обернуть в TabView, выделить GeneralTabView

**Files:**
- Modify: `StatsApp/Settings/SettingsView.swift`
- Create: `StatsApp/Settings/GeneralTabView.swift`

- [ ] **Step 1: Прочитать существующий SettingsView**

```bash
cat /Users/sergeytovarov/work/ai-stats/StatsApp/Settings/SettingsView.swift
```

- [ ] **Step 2: Создать GeneralTabView с текущим содержимым**

Переименовать содержимое body существующего `SettingsView` в новый `GeneralTabView`. То есть `GeneralTabView.body` = то что сейчас рендерится в `SettingsView.body`.

Если у `SettingsView` есть зависимости (config-binding, exporter), пробросить их в `GeneralTabView` через init.

- [ ] **Step 3: Переписать SettingsView через TabView**

```swift
import SwiftUI

struct SettingsView: View {
    // (передаём все зависимости в обе вкладки)
    let configBinding: Binding<Config>   // или существующие зависимости
    let api: AiuseAPIClient
    let keychain: KeychainStore
    let db: any DatabaseReader

    var body: some View {
        TabView {
            GeneralTabView(/* ... */)
                .tabItem { Label("Общие", systemImage: "gear") }

            AccountTabView(viewModel: AccountTabViewModel(
                api: api, keychain: keychain, db: db
            ))
                .tabItem { Label("Аккаунт", systemImage: "person.crop.circle") }
        }
        .frame(width: 520, height: 480)
    }
}
```

(точные параметры и зависимости — адаптировать к реальной сигнатуре существующего `SettingsView`.)

- [ ] **Step 4: Собрать**

```bash
xcodegen generate && xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Коммит**

```bash
git add StatsApp/Settings/SettingsView.swift StatsApp/Settings/GeneralTabView.swift
git commit -m "feat(ui): обернуть Settings в TabView с двумя вкладками"
```

---

### Task 17: AccountTabViewModel — состояние и actions

**Files:**
- Create: `StatsApp/Settings/AccountTabViewModel.swift`

- [ ] **Step 1: Создать viewmodel**

```swift
import Foundation
import GRDB

@MainActor
final class AccountTabViewModel: ObservableObject {
    enum State {
        case loading
        case notCreated
        case created(MyProfileRow)
    }

    @Published var state: State = .loading
    @Published var errorMessage: String?
    @Published var isWorking: Bool = false

    private let api: AiuseAPIClient
    private let keychain: KeychainStore
    private let db: any DatabaseWriter

    init(api: AiuseAPIClient, keychain: KeychainStore, db: any DatabaseWriter) {
        self.api = api
        self.keychain = keychain
        self.db = db
    }

    func reload() async {
        state = .loading
        do {
            if let profile = try await db.read({ try StatsQueries.loadMyProfile($0) }) {
                state = .created(profile)
            } else {
                state = .notCreated
            }
        } catch {
            errorMessage = "\(error)"
            state = .notCreated
        }
    }

    func createAccount(displayName: String, avatar: Data?, avatarMime: String?) async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil

        do {
            let resp = try await api.createProfile(
                displayName: displayName, avatar: avatar, avatarMime: avatarMime
            )
            try keychain.set(resp.apiSecret, account: AiuseKeychain.account, service: AiuseKeychain.service)

            let row = MyProfileRow(
                id: 1,
                friendCode: resp.friendCode,
                displayName: displayName,
                avatarPath: nil,
                sharingEnabled: true,
                serverUserId: resp.serverUserId
            )
            try await db.write { try StatsQueries.saveMyProfile($0, row) }
            state = .created(row)
        } catch {
            errorMessage = "Не удалось создать профиль: \(error.localizedDescription)"
        }
    }

    func toggleSharing(_ enabled: Bool) async {
        guard case let .created(profile) = state else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.patchProfile(sharingEnabled: enabled)
            var updated = profile
            updated.sharingEnabled = enabled
            try await db.write { try StatsQueries.saveMyProfile($0, updated) }
            state = .created(updated)
        } catch {
            errorMessage = "Не удалось переключить шаринг: \(error.localizedDescription)"
        }
    }

    func updateName(_ newName: String) async {
        guard case let .created(profile) = state else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.patchProfile(displayName: newName)
            var updated = profile
            updated.displayName = newName
            try await db.write { try StatsQueries.saveMyProfile($0, updated) }
            state = .created(updated)
        } catch {
            errorMessage = "Не удалось обновить имя: \(error.localizedDescription)"
        }
    }

    func regenerateFriendCode() async {
        guard case let .created(profile) = state else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let resp = try await api.regenerateFriendCode()
            var updated = profile
            updated.friendCode = resp.friendCode
            try await db.write { try StatsQueries.saveMyProfile($0, updated) }
            state = .created(updated)
        } catch {
            errorMessage = "Не удалось сгенерировать новый код: \(error.localizedDescription)"
        }
    }

    func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await api.deleteAccount()
            try keychain.delete(account: AiuseKeychain.account, service: AiuseKeychain.service)
            try await db.write { try StatsQueries.deleteMyProfile($0) }
            state = .notCreated
        } catch {
            errorMessage = "Не удалось удалить аккаунт: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: Собрать**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Коммит**

```bash
git add StatsApp/Settings/AccountTabViewModel.swift
git commit -m "feat(ui): AccountTabViewModel — стейт + actions"
```

---

### Task 18: AccountTabView — UI обеих веток

**Files:**
- Create: `StatsApp/Settings/AccountTabView.swift`

- [ ] **Step 1: Создать UI**

```swift
import SwiftUI

struct AccountTabView: View {
    @StateObject var viewModel: AccountTabViewModel
    @State private var newName: String = ""
    @State private var pickedAvatar: Data? = nil
    @State private var pickedAvatarMime: String? = nil
    @State private var showRegenerateConfirm = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch viewModel.state {
                case .loading:
                    ProgressView()
                case .notCreated:
                    notCreatedView
                case .created(let profile):
                    createdView(profile: profile)
                }

                if let err = viewModel.errorMessage {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await viewModel.reload() }
    }

    @ViewBuilder
    private var notCreatedView: some View {
        Text("Создать аккаунт").font(.title2).bold()
        Text("Без аккаунта недоступен лидерборд и виджет с лидербордом. Локальная статистика работает как и раньше.")
            .foregroundStyle(.secondary).font(.callout)

        TextField("Имя", text: $newName)
            .textFieldStyle(.roundedBorder)

        // Аватарка: упрощённый picker, можно расширить
        Button("Выбрать аватарку") {
            pickAvatar()
        }
        if pickedAvatar != nil {
            Text("Выбрано: \(pickedAvatar?.count ?? 0) байт").font(.caption).foregroundStyle(.secondary)
        }

        Button("Создать аккаунт") {
            Task {
                await viewModel.createAccount(
                    displayName: newName,
                    avatar: pickedAvatar,
                    avatarMime: pickedAvatarMime
                )
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(newName.isEmpty || viewModel.isWorking)
    }

    @ViewBuilder
    private func createdView(profile: MyProfileRow) -> some View {
        HStack {
            Image(systemName: "person.crop.circle")
                .resizable().frame(width: 48, height: 48)
            VStack(alignment: .leading) {
                Text(profile.displayName).font(.headline)
            }
        }

        Divider()

        Text("Твой код для друзей").font(.headline)
        HStack {
            Text(formatFriendCode(profile.friendCode))
                .font(.system(.title3, design: .monospaced))
            Spacer()
            Button("Копировать") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(profile.friendCode, forType: .string)
            }
        }

        Divider()

        Toggle("Шарить статистику", isOn: Binding(
            get: { profile.sharingEnabled },
            set: { newVal in Task { await viewModel.toggleSharing(newVal) } }
        ))
        Text("Если выключено: ты не отправляешь свои данные и не видишь чужие.")
            .font(.caption).foregroundStyle(.secondary)

        Divider()

        Text("Опасная зона").font(.headline).foregroundStyle(.red)
        Button("Сгенерировать новый код") {
            showRegenerateConfirm = true
        }
        .confirmationDialog(
            "Новый код заменит текущий. Все друзья будут удалены — им придётся добавить тебя заново. Твоя история использования сохранится.",
            isPresented: $showRegenerateConfirm,
            titleVisibility: .visible
        ) {
            Button("Сгенерировать", role: .destructive) {
                Task { await viewModel.regenerateFriendCode() }
            }
            Button("Отмена", role: .cancel) {}
        }

        Button("Удалить аккаунт") {
            showDeleteConfirm = true
        }
        .foregroundStyle(.red)
        .confirmationDialog(
            "Это удалит твой профиль, всю историю на сервере и все связи с друзьями. Локальная статистика останется. Действие необратимо.",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить аккаунт", role: .destructive) {
                Task { await viewModel.deleteAccount() }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    /// "XK7P3M9Q2A" → "XK7P-3M9Q-2A"
    private func formatFriendCode(_ raw: String) -> String {
        guard raw.count == 10 else { return raw }
        let i1 = raw.index(raw.startIndex, offsetBy: 4)
        let i2 = raw.index(raw.startIndex, offsetBy: 8)
        return "\(raw[..<i1])-\(raw[i1..<i2])-\(raw[i2...])"
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let data = (try? Data(contentsOf: url)) ?? Data()
            // Лимит 200 KB
            guard data.count <= 200 * 1024 else {
                viewModel.errorMessage = "Аватарка слишком большая (\(data.count) байт). Максимум 200 KB."
                return
            }
            pickedAvatar = data
            pickedAvatarMime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
        }
    }
}
```

- [ ] **Step 2: Собрать**

```bash
xcodegen generate && xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -15
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Коммит**

```bash
git add StatsApp/Settings/AccountTabView.swift
git commit -m "feat(ui): AccountTabView — создание + управление аккаунтом"
```

---

## Phase F: Wiring

### Task 19: AppContainer — wire всё вместе

**Files:**
- Modify: `StatsApp/AppContainer.swift`

- [ ] **Step 1: Изменить AppContainer**

Добавить fields:

```swift
let keychain: KeychainStore
let api: AiuseAPIClient
let snapshotSyncer: SnapshotSyncer
```

В `init()` после создания `dbPool`:

```swift
self.keychain = MacOSKeychainStore()
let baseURL = URL(string: cfg.aiuseApiBaseURL) ?? URL(string: "https://aiuse.popovs.tech/api")!
let keychainRef = self.keychain
self.api = AiuseAPIClient(
    baseURL: baseURL,
    secretProvider: { keychainRef.get(account: AiuseKeychain.account, service: AiuseKeychain.service) }
)
self.snapshotSyncer = SnapshotSyncer(db: dbPool, api: self.api)

// Передать в SyncCoordinator
let coordinator = SyncCoordinator(db: dbPool, snapshotSyncer: self.snapshotSyncer)
self.syncCoordinator = coordinator
```

(существующее присваивание `coordinator` заменить.)

- [ ] **Step 2: Обновить SettingsWindowController/SettingsView чтобы передавал зависимости**

Нужно убедиться что `SettingsView(...)` получает `api`, `keychain`, `db` из `AppContainer`. Это правится в том месте где `SettingsView` создаётся — обычно в `SettingsWindowController`.

```swift
// (где-то в SettingsWindowController или подобном)
let hostingController = NSHostingController(rootView: SettingsView(
    api: container.api,
    keychain: container.keychain,
    db: container.dbPool,
    // + существующие зависимости общей вкладки
))
```

- [ ] **Step 3: Собрать**

```bash
xcodegen generate && xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Debug -derivedDataPath build/ 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Коммит**

```bash
git add StatsApp/AppContainer.swift StatsApp/Settings/SettingsWindowController.swift
git commit -m "feat(app): wire AiuseAPIClient + KeychainStore + SnapshotSyncer в AppContainer"
```

---

## Phase G: E2E ручная проверка

### Task 20: Manual E2E test против prod

**Files:** — (только инструкция, никаких файлов не пишем)

- [ ] **Step 1: Прогнать все unit-тесты**

```bash
xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp \
  -destination "platform=macOS" 2>&1 | tail -25
```

Expected: все existing + новые тесты PASS.

- [ ] **Step 2: Собрать релиз-билд и запустить**

```bash
xcodebuild -project ai-stats.xcodeproj -scheme StatsApp \
  -configuration Release -derivedDataPath build/ 2>&1 | tail -5
open build/Build/Products/Release/StatsApp.app
```

App запустится в menu bar.

- [ ] **Step 3: Создать аккаунт через UI**

1. Открыть menu bar app, нажать ⚙ (Settings) — должно открыться окно с TabView.
2. Перейти на вкладку «Аккаунт» — должна показаться форма создания.
3. Ввести имя (например «Test User»), нажать «Создать аккаунт».
4. Должен появиться friend_code в формате `XXXX-XXXX-XX`.

- [ ] **Step 4: Проверить что snapshot ушёл**

Подождать минимум 5 минут (sync_interval) или перезапустить app (запустит initial sync). Затем на VM:

```bash
ssh meridian "docker exec aiuse-postgres psql -U aiuse aiuse -c 'SELECT * FROM snapshots ORDER BY hour_bucket DESC LIMIT 5;'"
```

Expected: видно строку с tokens_input/output от созданного профиля. user_id совпадает с тем `server_user_id` который вернулся при создании.

- [ ] **Step 5: Проверить toggle шаринга**

В UI выключить «Шарить статистику» → выждать тик → убедиться что запрос идёт но возвращает 403, snapshot не появляется новый. Включить обратно → следующий snapshot пушится.

- [ ] **Step 6: Проверить регенерацию ID**

Жмём «Сгенерировать новый код» → confirm → код в UI должен поменяться. На сервере:

```bash
ssh meridian "docker exec aiuse-postgres psql -U aiuse aiuse -c 'SELECT friend_code FROM profiles WHERE id = <your_server_user_id>;'"
```

Expected: новый код.

- [ ] **Step 7: Удалить тестовый аккаунт**

«Удалить аккаунт» → confirm → state UI должно вернуться в «notCreated». На сервере:

```bash
ssh meridian "docker exec aiuse-postgres psql -U aiuse aiuse -c 'SELECT count(*) FROM profiles;'"
ssh meridian "docker exec aiuse-postgres psql -U aiuse aiuse -c 'SELECT count(*) FROM snapshots;'"
```

Expected: 0 profiles, 0 snapshots (всё каскадно удалилось).

- [ ] **Step 8: Записать в CHANGELOG.md**

В существующий CHANGELOG.md добавить раздел `## v0.2.0 — client`:

```markdown
### v0.2.0 — client

- Добавить `AiuseAPIClient` и `KeychainStore` для взаимодействия с `aiuse.popovs.tech/api`.
- Новая вкладка «Аккаунт» в Settings: создание профиля, friend_code, шаринг toggle, регенерация ID, удаление.
- `SnapshotSyncer` интегрирован в `SyncCoordinator` — раз в `sync_interval_minutes` шлёт daily-агрегаты на сервер.
- Локальные таблицы `my_profile` и `pending_snapshots` (миграция v5).
- Покрытие: KeychainStore, AiuseAPIClient (через MockURLProtocol), SnapshotSyncer.

Известное расхождение: шлём один snapshot/день с `hour_bucket = midnight UTC` (локальная БД хранит daily). Hourly precision — в будущей задаче.
```

- [ ] **Step 9: Коммит**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): v0.2.0 client"
```

---

## Self-Review

### Spec coverage

| Спек | Покрыто? |
|---|---|
| §3.1 Компоненты — клиент использует API на aiuse.popovs.tech | ✓ (Task 19: baseURL из config) |
| §5.2 Клиентская GRDB схема: my_profile, pending_snapshots | ✓ (Task 2 миграция v5, Task 3 модели) |
| §5.3 App Group shared container — leaderboard.json, my_stats.json | ⚠ **не делаем** в v0.2.0 (это для виджета leaderboard — v0.4.0) |
| §6.1 API — все 5 endpoint'ов (create, patch, regenerate, delete, snapshots) | ✓ (Tasks 8-10) |
| §6.2 Auth Bearer | ✓ (Task 7 skeleton) |
| §7.1 Bootstrap — аккаунт создаётся по явному действию в Settings | ✓ (Task 18 createdView) |
| §7.2 Push snapshot'ов с pending_snapshots буфером, retry, attempts | ✓ (Tasks 12-14) |
| §7.3 Pull данных (friends, leaderboard) | ⚠ **не делаем** в v0.2.0 (это v0.3.0) |
| §7.4 AiuseAPIClient как отдельный модуль | ✓ (Tasks 7-10) |
| §8.1 sharing_enabled = false → не шлём | ✓ (Task 13 + тест в Task 14) |
| §8.2-8.4 удаление, регенерация — обновление локального профиля | ✓ (Task 17 actions) |
| §8.7 Keychain потерян → новый аккаунт | ✓ (через создание заново, ничего специального) |
| §9.2 SettingsView TabView + Аккаунт | ✓ (Tasks 16, 18) |
| §11.1 api_secret в Keychain | ✓ (Tasks 4, 17) |
| §11.4 не защищаемся от компромета | ✓ (нет специальной логики) |

**Разрешённые гэпы (явно not in scope of v0.2.0 client):** Pull данных, App Group leaderboard.json, friends UI, blocks. Эти кодируются в v0.3.0 и v0.4.0 планах.

### Placeholder scan

- ✗ «TODO», «TBD» в плане — отсутствует.
- ✓ Все code блоки содержат рабочий код.
- ✓ Все команды показывают expected результат.
- Один момент — в Task 1 и Task 16 я говорю «прочитать существующий файл». Это **не** placeholder, это инструкция engineer'у сначала открыть файл чтобы адаптировать к точному текущему виду (потому что у меня нет полного diff'а Config.swift и SettingsView в момент написания плана).

### Type consistency

- `MyProfileRow.serverUserId: Int64` — соответствует `ProfileCreateResponse.serverUserId: Int64`. ✓
- `friend_code` — везде String. ✓
- `hour_bucket`: локально Int64 (unix seconds), на API — String (ISO 8601 UTC). Преобразование явное в `SnapshotSyncer.iso8601(from:)`. ✓
- `sharingEnabled: Bool` — везде Bool. ✓
- `AiuseKeychain.service/account` — используются и в AppContainer (Task 19) и в AccountTabViewModel (Task 17). ✓

Всё консистентно.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-23-leaderboard-v0.2.0-client.md`.

Два варианта исполнения:

1. **Subagent-Driven (recommended)** — диспатчу свежего сабагента на каждый task, ревью между ними, фастер итерация.
2. **Inline Execution** — исполняю задачи в этой же сессии через `executing-plans`, батчем с чекпоинтами на ревью.

Какой?
