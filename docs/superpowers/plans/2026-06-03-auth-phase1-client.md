# Авторизация — Фаза 1, Client (Swift) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дать macOS-клиенту `Burn` вход через GitHub OAuth — один device_token на устройство (multi-device через повторный логин), автоматический GitHub data-токен вместо ручного PAT, и переключатель публичного лидерборда (`global_opt_in`).

**Architecture:** Сервер брокерит OAuth. Клиент открывает `…/api/auth/start?provider=github` в `ASWebAuthenticationSession`, ловит редирект `burn://auth/callback?code=…`, меняет `code` (+ PKCE-style `verifier`) на `device_token`/`github_token`/`github_login` через `POST /api/auth/exchange`. Секреты пишутся в существующий combined Keychain item (`SecretsStore`), GitHub-логин едет вместе с токеном. Существующий `api_secret`-аккаунт **не мигрируется** — GitHub-логин создаёт фрешевый профиль (решение пользователя, YAGNI).

**Tech Stack:** Swift 5.9, AppKit (menu bar app, `LSUIElement`), `AuthenticationServices` (`ASWebAuthenticationSession`), CryptoKit (SHA256), GRDB, XCTest + `MockURLProtocol`. App **не sandboxed** (`com.apple.security.app-sandbox: false`).

**Репозиторий реализации:** этот репо (`ai-stats`). Пути — относительно корня.

**Зависит от:** backend-план `2026-06-03-auth-phase1-backend.md` должен быть **задеплоен** (эндпоинты `/api/auth/start`, `/api/auth/cb/github`, `/api/auth/exchange`, поле `global_opt_in`, `github_login` в ответе exchange). До деплоя тесты с `MockURLProtocol` проходят (сеть замокана), но ручная проверка входа — только против живого сервера.

**Конвенции репо (соблюдать):**
- Тесты — `Tests/StatsAppTests/...`, XCTest, `func test…() async throws`, сеть через `MockURLProtocol` + `URLSessionConfiguration.ephemeral`.
- Keychain в тестах — `MemoryKeychainStore`.
- Генерация проекта после правки `project.yml`: `xcodegen generate`.
- Сборка/тесты: `xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS'` (можно сузить `-only-testing:StatsAppTests/<Class>/<test>`).
- Память-кэши секретов: `SecretBox` (device_token), `GithubTokenBox` (github-токен) — нужны, т.к. unsigned-сборка триггерит Keychain-prompt на каждый `SecItemCopyMatching`.

---

## File Structure

| Файл | Создаём/меняем | Ответственность |
|---|---|---|
| `project.yml` | Modify | Зарегистрировать URL scheme `burn` (`CFBundleURLTypes`) |
| `StatsApp/Network/AuthError.swift` | Create | Ошибки OAuth-флоу |
| `StatsApp/Network/AuthDTO.swift` | Create | `AuthExchangeRequest`/`AuthExchangeResponse` |
| `StatsApp/Network/AiuseDTO.swift` | Modify | `global_opt_in` в `ProfileUpdateRequest`/`ProfileResponse` |
| `StatsApp/Util/Crypto.swift` | Create | SHA256-hex + генерация verifier |
| `StatsApp/Network/AiuseAPIClient.swift` | Modify | `exchange(code:verifier:)`, `globalOptIn` в `patchProfile` |
| `StatsApp/Network/WebAuthenticating.swift` | Create | Протокол + `ASWebAuthenticator` (обёртка `ASWebAuthenticationSession`) |
| `StatsApp/Network/AuthService.swift` | Create | `GitHubSignInService` протокол + `AuthService` (start URL → web auth → exchange) |
| `StatsApp/Network/SecretsStore.swift` | Modify | Поле `githubLogin` в `Secrets` + `setGithubAuth(token:login:)` |
| `StatsApp/Network/KeychainStore.swift` | Modify | `GithubLoginBox` memory-кэш |
| `StatsApp/AppContainer.swift` | Modify | Wiring: login box, fetcher из box, `AuthService`, deps в `makeAccountTabViewModel` |
| `StatsApp/Settings/AccountTabViewModel.swift` | Modify | `signInWithGitHub`, `toggleGlobalOptIn`, новые deps в init |
| `StatsApp/Settings/AccountTabView.swift` | Modify | Кнопка «Войти через GitHub» + тогл публичного лидерборда |
| `Tests/StatsAppTests/Util/CryptoTests.swift` | Create | Тесты SHA256-hex |
| `Tests/StatsAppTests/Network/AuthServiceTests.swift` | Create | OAuth-флоу с fake web-auth + mock exchange |
| `Tests/StatsAppTests/Network/AiuseAPIClientTests.swift` | Modify | Тест `exchange` |
| `Tests/StatsAppTests/Network/SecretsStoreTests.swift` | Modify | Round-trip `githubLogin` |
| `Tests/StatsAppTests/Settings/AccountTabViewModelTests.swift` | Modify | Тест `signInWithGitHub` (fake AuthService) + починка init |

---

## Task 1: URL scheme `burn` + AuthError

**Files:**
- Modify: `project.yml`
- Create: `StatsApp/Network/AuthError.swift`

- [ ] **Step 1: Зарегистрировать scheme в project.yml**

В `project.yml`, target `StatsApp` → `info.properties`, добавить `CFBundleURLTypes` рядом с существующими ключами (`LSUIElement` и т.д.):

```yaml
        CFBundleURLTypes:
          - CFBundleURLName: tech.popovs.burn.auth
            CFBundleURLSchemes: [burn]
```

- [ ] **Step 2: Перегенерировать проект**

Run: `xcodegen generate`
Expected: без ошибок; в `StatsApp/Info.plist` появился `CFBundleURLTypes` со схемой `burn`.

- [ ] **Step 3: Создать AuthError**

Создать `StatsApp/Network/AuthError.swift`:

```swift
import Foundation

enum AuthError: Error, LocalizedError, Equatable {
    case cancelled
    case cannotStart
    case noCodeInCallback
    case badCallbackURL(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Вход отменён"
        case .cannotStart: return "Не удалось запустить вход"
        case .noCodeInCallback: return "Сервер вернул некорректный ответ авторизации"
        case .badCallbackURL(let s): return "Некорректный callback: \(s)"
        }
    }
}
```

- [ ] **Step 4: Сборка**

Run: `xcodebuild build -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add project.yml StatsApp/Info.plist StatsApp/Network/AuthError.swift
git commit -m "feat(auth): зарегистрировать URL scheme burn и AuthError"
```

---

## Task 2: DTO авторизации + global_opt_in

**Files:**
- Create: `StatsApp/Network/AuthDTO.swift`
- Modify: `StatsApp/Network/AiuseDTO.swift`

- [ ] **Step 1: Создать AuthDTO**

Создать `StatsApp/Network/AuthDTO.swift`:

```swift
import Foundation

struct AuthExchangeRequest: Codable {
    let code: String
    let verifier: String
}

struct AuthExchangeResponse: Codable, Equatable {
    let deviceToken: String
    let githubToken: String?
    let githubLogin: String?
    let friendCode: String
    let serverUserId: Int64

    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
        case githubToken = "github_token"
        case githubLogin = "github_login"
        case friendCode = "friend_code"
        case serverUserId = "server_user_id"
    }
}
```

- [ ] **Step 2: Добавить global_opt_in в AiuseDTO**

В `StatsApp/Network/AiuseDTO.swift`:

`ProfileUpdateRequest` — добавить поле и ключ:

```swift
struct ProfileUpdateRequest: Codable {
    let displayName: String?
    let avatarB64: String?
    let avatarMime: String?
    let sharingEnabled: Bool?
    let globalOptIn: Bool?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarB64 = "avatar_b64"
        case avatarMime = "avatar_mime"
        case sharingEnabled = "sharing_enabled"
        case globalOptIn = "global_opt_in"
    }
}
```

`ProfileResponse` — добавить поле и ключ:

```swift
struct ProfileResponse: Codable {
    let friendCode: String
    let displayName: String
    let sharingEnabled: Bool
    let globalOptIn: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case displayName = "display_name"
        case sharingEnabled = "sharing_enabled"
        case globalOptIn = "global_opt_in"
        case createdAt = "created_at"
    }
}
```

- [ ] **Step 3: Сборка**

Run: `xcodebuild build -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED (ошибки в `AiuseAPIClient.patchProfile`, который конструирует `ProfileUpdateRequest` без нового поля, исправим в Task 4 — если компилятор ругается на missing argument, временно передать `globalOptIn: nil` в существующем вызове; финально — в Task 4).

> Чтобы не ломать сборку между задачами: в `AiuseAPIClient.patchProfile` сразу добавь `globalOptIn: nil` в инициализатор `ProfileUpdateRequest`. Полную поддержку параметра добавим в Task 4.

- [ ] **Step 4: Commit**

```bash
git add StatsApp/Network/AuthDTO.swift StatsApp/Network/AiuseDTO.swift StatsApp/Network/AiuseAPIClient.swift
git commit -m "feat(auth): DTO exchange и поле global_opt_in"
```

---

## Task 3: Crypto-хелпер (SHA256-hex + verifier)

PKCE-style: клиент шлёт `challenge = sha256hex(verifier)` в `/auth/start`, потом сам `verifier` в `/auth/exchange`. Бэкенд сверяет `sha256_hex(verifier) == challenge` (hex, lowercase) — формат должен совпасть.

**Files:**
- Create: `StatsApp/Util/Crypto.swift`
- Create: `Tests/StatsAppTests/Util/CryptoTests.swift`

- [ ] **Step 1: Падающий тест**

Создать `Tests/StatsAppTests/Util/CryptoTests.swift`:

```swift
import XCTest
@testable import StatsApp

final class CryptoTests: XCTestCase {
    func test_sha256Hex_knownVector() {
        // sha256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
        XCTAssertEqual(
            Crypto.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func test_randomVerifier_isHex64() {
        let v = Crypto.randomVerifier()
        XCTAssertEqual(v.count, 64)
        XCTAssertTrue(v.allSatisfy { $0.isHexDigit })
    }
}
```

- [ ] **Step 2: Запустить — падает**

Run: `xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/CryptoTests`
Expected: FAIL — `Crypto` не существует (ошибка компиляции).

- [ ] **Step 3: Реализовать Crypto**

Создать `StatsApp/Util/Crypto.swift`:

```swift
import Foundation
import CryptoKit

enum Crypto {
    /// SHA256 от UTF-8 байт строки, hex lowercase. Совпадает с серверным sha256_hex.
    static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 32 случайных байта в hex (64 символа) — PKCE verifier.
    static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Запустить — проходит**

Run: `xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/CryptoTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add StatsApp/Util/Crypto.swift Tests/StatsAppTests/Util/CryptoTests.swift
git commit -m "feat(auth): Crypto — sha256hex и генерация verifier"
```

---

## Task 4: AiuseAPIClient.exchange + globalOptIn в patchProfile

**Files:**
- Modify: `StatsApp/Network/AiuseAPIClient.swift`
- Modify: `Tests/StatsAppTests/Network/AiuseAPIClientTests.swift`

- [ ] **Step 1: Падающий тест exchange**

В `Tests/StatsAppTests/Network/AiuseAPIClientTests.swift` добавить (следуя существующему стилю файла — `MockURLProtocol.responder` + ephemeral session):

```swift
func test_exchange_postsCodeAndVerifier_returnsTokens() async throws {
    MockURLProtocol.responder = { req in
        let url = req.url!.absoluteString
        XCTAssertTrue(url.hasSuffix("/auth/exchange"))
        let body = """
        {"device_token":"dt","github_token":"ght","github_login":"octocat",
         "friend_code":"AAAA-BBBB-CC","server_user_id":7}
        """.data(using: .utf8)!
        return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
    }
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [MockURLProtocol.self]
    let api = AiuseAPIClient(
        baseURL: URL(string: "https://example.test/api")!,
        secretProvider: { nil },
        session: URLSession(configuration: cfg)
    )

    let resp = try await api.exchange(code: "AUTHCODE", verifier: "v123")

    XCTAssertEqual(resp.deviceToken, "dt")
    XCTAssertEqual(resp.githubToken, "ght")
    XCTAssertEqual(resp.githubLogin, "octocat")
    XCTAssertEqual(resp.serverUserId, 7)

    // verifier и code ушли в теле
    let sent = MockURLProtocol.lastBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    XCTAssertEqual(sent?["code"] as? String, "AUTHCODE")
    XCTAssertEqual(sent?["verifier"] as? String, "v123")
}
```

- [ ] **Step 2: Запустить — падает**

Run: `xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/AiuseAPIClientTests/test_exchange_postsCodeAndVerifier_returnsTokens`
Expected: FAIL — нет метода `exchange`.

- [ ] **Step 3: Добавить exchange + globalOptIn**

В `StatsApp/Network/AiuseAPIClient.swift`, секция `// MARK: - profiles`, обновить `patchProfile` (добавить параметр и проброс):

```swift
    func patchProfile(displayName: String? = nil,
                      avatar: Data? = nil,
                      avatarMime: String? = nil,
                      sharingEnabled: Bool? = nil,
                      globalOptIn: Bool? = nil) async throws -> ProfileResponse {
        let body = ProfileUpdateRequest(
            displayName: displayName,
            avatarB64: avatar?.base64EncodedString(),
            avatarMime: avatarMime,
            sharingEnabled: sharingEnabled,
            globalOptIn: globalOptIn
        )
        return try await request(
            path: "/profiles/me",
            method: "PATCH",
            body: body,
            authed: true,
            decodeAs: ProfileResponse.self
        )
    }
```

Добавить новую секцию (например, после `// MARK: - profiles`):

```swift
    // MARK: - auth

    func exchange(code: String, verifier: String) async throws -> AuthExchangeResponse {
        let body = AuthExchangeRequest(code: code, verifier: verifier)
        return try await request(
            path: "/auth/exchange",
            method: "POST",
            body: body,
            authed: false,
            decodeAs: AuthExchangeResponse.self
        )
    }
```

- [ ] **Step 4: Запустить — проходит**

Run: `xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/AiuseAPIClientTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add StatsApp/Network/AiuseAPIClient.swift Tests/StatsAppTests/Network/AiuseAPIClientTests.swift
git commit -m "feat(auth): AiuseAPIClient.exchange и globalOptIn в patchProfile"
```

---

## Task 5: WebAuthenticating + AuthService

**Files:**
- Create: `StatsApp/Network/WebAuthenticating.swift`
- Create: `StatsApp/Network/AuthService.swift`
- Create: `Tests/StatsAppTests/Network/AuthServiceTests.swift`

- [ ] **Step 1: Падающий тест AuthService (fake web-auth + mock exchange)**

Создать `Tests/StatsAppTests/Network/AuthServiceTests.swift`:

```swift
import XCTest
@testable import StatsApp

private final class FakeWebAuth: WebAuthenticating {
    var capturedURL: URL?
    var callback: URL

    init(callback: URL) { self.callback = callback }

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        capturedURL = url
        return callback
    }
}

final class AuthServiceTests: XCTestCase {
    private func makeAPI() -> AiuseAPIClient {
        MockURLProtocol.responder = { req in
            let body = """
            {"device_token":"dt","github_token":"ght","github_login":"octocat",
             "friend_code":"AAAA-BBBB-CC","server_user_id":7}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return AiuseAPIClient(
            baseURL: URL(string: "https://example.test/api")!,
            secretProvider: { nil },
            session: URLSession(configuration: cfg)
        )
    }

    func test_signIn_buildsStartURL_andExchangesCode() async throws {
        let fake = FakeWebAuth(callback: URL(string: "burn://auth/callback?code=AUTHCODE&state=st")!)
        let service = AuthService(
            authBaseURL: URL(string: "https://example.test/api")!,
            api: makeAPI(),
            webAuth: fake
        )

        let resp = try await service.signIn(provider: "github", includePrivate: false)

        XCTAssertEqual(resp.deviceToken, "dt")
        XCTAssertEqual(resp.githubLogin, "octocat")

        // start URL корректный
        let start = fake.capturedURL!.absoluteString
        XCTAssertTrue(start.hasPrefix("https://example.test/api/auth/start"))
        XCTAssertTrue(start.contains("provider=github"))
        XCTAssertTrue(start.contains("challenge="))
        XCTAssertTrue(start.contains("include_private=false"))
    }

    func test_signIn_noCodeInCallback_throws() async {
        let fake = FakeWebAuth(callback: URL(string: "burn://auth/callback?state=st")!)
        let service = AuthService(
            authBaseURL: URL(string: "https://example.test/api")!,
            api: makeAPI(),
            webAuth: fake
        )
        do {
            _ = try await service.signIn(provider: "github", includePrivate: false)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AuthError, .noCodeInCallback)
        }
    }
}
```

- [ ] **Step 2: Запустить — падает**

Run: `xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/AuthServiceTests`
Expected: FAIL — нет `WebAuthenticating`/`AuthService`.

- [ ] **Step 3: Протокол + production-обёртка**

Создать `StatsApp/Network/WebAuthenticating.swift`:

```swift
import Foundation
import AppKit
import AuthenticationServices

/// Абстракция над ASWebAuthenticationSession — для тестируемости AuthService.
protocol WebAuthenticating {
    /// Открывает `url`, ждёт редирект на `callbackScheme://…`, возвращает callback-URL.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// Production-реализация. @MainActor — ASWebAuthenticationSession требует main thread
/// и presentation anchor.
@MainActor
final class ASWebAuthenticator: NSObject, WebAuthenticating, ASWebAuthenticationPresentationContextProviding {
    // Сильная ссылка: без неё сессия может освободиться до завершения.
    private var session: ASWebAuthenticationSession?
    private var anchor: NSWindow?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    cont.resume(returning: callbackURL)
                } else if let asError = error as? ASWebAuthenticationSessionError,
                          asError.code == .canceledLogin {
                    cont.resume(throwing: AuthError.cancelled)
                } else {
                    cont.resume(throwing: error ?? AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            // Переиспользуем существующую сессию браузера (если юзер уже залогинен в GitHub).
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                cont.resume(throwing: AuthError.cannotStart)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let anchor { return anchor }
        // Menu bar app (LSUIElement) может не иметь видимого окна — создаём якорь.
        let w = NSApp.windows.first ?? NSWindow(
            contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true
        )
        anchor = w
        return w
    }
}
```

- [ ] **Step 4: AuthService**

Создать `StatsApp/Network/AuthService.swift`:

```swift
import Foundation

/// Узкий протокол для ViewModel — чтобы тестировать VM с fake-входом.
protocol GitHubSignInService {
    func signIn(provider: String, includePrivate: Bool) async throws -> AuthExchangeResponse
}

/// Оркестрирует OAuth-флоу: start URL → ASWebAuthenticationSession → exchange.
final class AuthService: GitHubSignInService {
    private let authBaseURL: URL   // например https://aiuse.popovs.tech/api
    private let api: AiuseAPIClient
    private let webAuth: WebAuthenticating

    static let callbackScheme = "burn"

    init(authBaseURL: URL, api: AiuseAPIClient, webAuth: WebAuthenticating) {
        self.authBaseURL = authBaseURL
        self.api = api
        self.webAuth = webAuth
    }

    func signIn(provider: String, includePrivate: Bool) async throws -> AuthExchangeResponse {
        let verifier = Crypto.randomVerifier()
        let challenge = Crypto.sha256Hex(verifier)

        var startURL = authBaseURL
        startURL.append(path: "/auth/start")
        guard var components = URLComponents(url: startURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.badCallbackURL(startURL.absoluteString)
        }
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "challenge", value: challenge),
            URLQueryItem(name: "include_private", value: includePrivate ? "true" : "false"),
        ]
        guard let finalStart = components.url else {
            throw AuthError.badCallbackURL(startURL.absoluteString)
        }

        let callback = try await webAuth.authenticate(
            url: finalStart, callbackScheme: Self.callbackScheme
        )

        guard let cc = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let code = cc.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw AuthError.noCodeInCallback
        }

        return try await api.exchange(code: code, verifier: verifier)
    }
}
```

- [ ] **Step 5: Запустить — проходит**

Run: `xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/AuthServiceTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add StatsApp/Network/WebAuthenticating.swift StatsApp/Network/AuthService.swift Tests/StatsAppTests/Network/AuthServiceTests.swift
git commit -m "feat(auth): AuthService и обёртка ASWebAuthenticationSession"
```

---

## Task 6: SecretsStore — githubLogin едет с токеном

**Files:**
- Modify: `StatsApp/Network/SecretsStore.swift`
- Modify: `Tests/StatsAppTests/Network/SecretsStoreTests.swift`

- [ ] **Step 1: Падающий тест round-trip githubLogin**

В `Tests/StatsAppTests/Network/SecretsStoreTests.swift` добавить:

```swift
func test_setGithubAuth_persistsTokenAndLogin() throws {
    let kc = MemoryKeychainStore()
    let store = SecretsStore(keychain: kc)

    try store.setGithubAuth(token: "ght", login: "octocat")

    let loaded = store.loadAll()
    XCTAssertEqual(loaded.githubPAT, "ght")
    XCTAssertEqual(loaded.githubLogin, "octocat")
}

func test_legacySecrets_haveNilGithubLogin() throws {
    let kc = MemoryKeychainStore()
    let store = SecretsStore(keychain: kc)
    try store.setAiuse("dt")

    XCTAssertNil(store.loadAll().githubLogin)
}
```

- [ ] **Step 2: Запустить — падает**

Run: `xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/SecretsStoreTests`
Expected: FAIL — нет `githubLogin` / `setGithubAuth`.

- [ ] **Step 3: Расширить Secrets**

В `StatsApp/Network/SecretsStore.swift`, struct `Secrets`:

```swift
    struct Secrets: Codable, Equatable {
        var aiuseSecret: String?
        var githubPAT: String?
        var githubLogin: String?

        static let empty = Secrets(aiuseSecret: nil, githubPAT: nil, githubLogin: nil)

        var hasAny: Bool {
            (aiuseSecret?.isEmpty == false) || (githubPAT?.isEmpty == false)
        }
    }
```

> `githubLogin` опционально и Codable терпит отсутствие ключа в старом combined-JSON (decode даёт nil) — обратная совместимость с уже записанными айтемами сохраняется. В `hasAny` логин не учитываем: он не секрет, сам по себе не повод писать combined-item.

В legacy-миграции `loadAll()` строка сборки `migrated` остаётся прежней (логина у legacy нет):

```swift
        let migrated = Secrets(aiuseSecret: aiuse, githubPAT: github, githubLogin: nil)
```

Добавить метод записи токена+логина:

```swift
    /// Пишет github-токен и логин одним апдейтом combined-item, сохраняя aiuseSecret.
    func setGithubAuth(token: String?, login: String?) throws {
        var current = loadAll()
        current.githubPAT = token
        current.githubLogin = login
        try save(current)
    }
```

- [ ] **Step 4: Запустить — проходит**

Run: `xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/SecretsStoreTests`
Expected: PASS (включая существующие тесты SecretsStore — `Secrets` инициализатор расширен, но старые вызовы `Secrets(aiuseSecret:githubPAT:)` сломаются на missing argument; если такие есть в тестах — добавить `githubLogin: nil`).

- [ ] **Step 5: Commit**

```bash
git add StatsApp/Network/SecretsStore.swift Tests/StatsAppTests/Network/SecretsStoreTests.swift
git commit -m "feat(auth): хранить github-логин рядом с токеном в SecretsStore"
```

---

## Task 7: GithubLoginBox + AppContainer wiring

**Files:**
- Modify: `StatsApp/Network/KeychainStore.swift`
- Modify: `StatsApp/AppContainer.swift`

- [ ] **Step 1: Добавить GithubLoginBox**

В `StatsApp/Network/KeychainStore.swift`, рядом с `GithubTokenBox`:

```swift
/// Memory-кэш GitHub-логина. Едет вместе с токеном (из OAuth или legacy config).
/// Та же причина что у GithubTokenBox — не дёргать Keychain каждый sync-тик.
@MainActor
final class GithubLoginBox {
    var value: String = ""
}
```

- [ ] **Step 2: Прокинуть login box и AuthService в AppContainer**

В `StatsApp/AppContainer.swift`:

Добавить свойства:

```swift
    let githubLoginBox: GithubLoginBox
    let authService: AuthService
```

В `init()`, после создания `ghBox` (GithubTokenBox):

```swift
        let ghLoginBox = GithubLoginBox()
        // OAuth-логин (из combined-secrets) приоритетнее legacy config.github_login.
        ghLoginBox.value = secrets.githubLogin ?? cfg.githubLogin
        self.githubLoginBox = ghLoginBox
```

После создания `api` (AiuseAPIClient) и `baseURL`:

```swift
        self.authService = AuthService(
            authBaseURL: baseURL,
            api: api,
            webAuth: ASWebAuthenticator()
        )
```

> `ASWebAuthenticator()` — `@MainActor`, а `init()` AppContainer уже `@MainActor` (класс помечен), так что создаётся без проблем.

Обновить `buildFetchers()` — брать логин из box, не из конфига:

```swift
        let token = githubTokenBox.value
        let login = githubLoginBox.value
        if !token.isEmpty && !login.isEmpty {
            sources.append(("github", [GitHubFetcher(token: token, login: login)]))
        }
```

Обновить `githubEnabledNow` (для DropdownViewModel):

```swift
        let githubEnabledNow = !ghBox.value.isEmpty && !ghLoginBox.value.isEmpty
```

Обновить фабрику VM аккаунта:

```swift
    func makeAccountTabViewModel() -> AccountTabViewModel {
        AccountTabViewModel(
            api: aiuseAPI,
            auth: authService,
            secretsStore: secretsStore,
            secretBox: secretBox,
            githubTokenBox: githubTokenBox,
            githubLoginBox: githubLoginBox,
            db: dbPool
        )
    }
```

- [ ] **Step 3: Сборка**

Run: `xcodebuild build -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -quiet`
Expected: BUILD FAILS — `AccountTabViewModel.init` ещё не принимает новые параметры. Чиним в Task 8 (это ожидаемый промежуточный фейл; коммит делаем после Task 8, либо здесь только git add без commit).

> Не коммить этот шаг отдельно: сборка зелёная только после Task 8. Переходи к Task 8, коммить их вместе.

---

## Task 8: AccountTabViewModel — вход через GitHub + global opt-in

**Files:**
- Modify: `StatsApp/Settings/AccountTabViewModel.swift`
- Modify: `Tests/StatsAppTests/Settings/AccountTabViewModelTests.swift`

- [ ] **Step 1: Падающий тест signInWithGitHub (fake AuthService)**

В `Tests/StatsAppTests/Settings/AccountTabViewModelTests.swift` добавить fake и тест (БД — in-memory pool как в существующих тестах файла; если хелпер уже есть — переиспользуй):

```swift
private final class FakeSignIn: GitHubSignInService {
    var response: AuthExchangeResponse
    init(_ r: AuthExchangeResponse) { response = r }
    func signIn(provider: String, includePrivate: Bool) async throws -> AuthExchangeResponse {
        response
    }
}

@MainActor
func test_signInWithGitHub_persistsTokensAndProfile() async throws {
    let db = try DatabaseQueue()  // или существующий хелпер in-memory GRDB из файла
    try Database.migrate(db)      // используем тот же migrator, что в других тестах файла

    let kc = MemoryKeychainStore()
    let store = SecretsStore(keychain: kc)
    let box = SecretBox()
    let ghBox = GithubTokenBox()
    let ghLoginBox = GithubLoginBox()
    let api = AiuseAPIClient(baseURL: URL(string: "https://x.test/api")!, secretProvider: { box.value })
    let fake = FakeSignIn(AuthExchangeResponse(
        deviceToken: "dt", githubToken: "ght", githubLogin: "octocat",
        friendCode: "AAAA-BBBB-CC", serverUserId: 7
    ))

    let vm = AccountTabViewModel(
        api: api, auth: fake, secretsStore: store, secretBox: box,
        githubTokenBox: ghBox, githubLoginBox: ghLoginBox, db: db
    )

    await vm.signInWithGitHub(includePrivate: false)

    XCTAssertEqual(box.value, "dt")
    XCTAssertEqual(ghBox.value, "ght")
    XCTAssertEqual(ghLoginBox.value, "octocat")
    XCTAssertEqual(store.loadAll().githubPAT, "ght")
    if case let .created(profile) = vm.state {
        XCTAssertEqual(profile.friendCode, "AAAA-BBBB-CC")
        XCTAssertEqual(profile.serverUserId, 7)
        XCTAssertFalse(profile.sharingEnabled)  // opt-in по умолчанию выключен
    } else {
        XCTFail("expected .created")
    }
}
```

> Замечание: подгони создание БД/миграцию под то, что уже используется в `AccountTabViewModelTests` (там есть рабочий способ поднять GRDB с таблицей `my_profile`). Не выдумывай новый — переиспользуй существующий хелпер файла.

- [ ] **Step 2: Запустить — падает**

Run: `xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/AccountTabViewModelTests/test_signInWithGitHub_persistsTokensAndProfile`
Expected: FAIL — `init` не принимает `auth`/`githubTokenBox`/`githubLoginBox`, нет `signInWithGitHub`.

- [ ] **Step 3: Расширить init и добавить методы**

В `StatsApp/Settings/AccountTabViewModel.swift`, обновить свойства и init:

```swift
    private let api: AiuseAPIClient
    private let auth: GitHubSignInService
    private let secretsStore: SecretsStore
    private let secretBox: SecretBox
    private let githubTokenBox: GithubTokenBox
    private let githubLoginBox: GithubLoginBox
    private let db: any DatabaseWriter

    init(api: AiuseAPIClient,
         auth: GitHubSignInService,
         secretsStore: SecretsStore,
         secretBox: SecretBox,
         githubTokenBox: GithubTokenBox,
         githubLoginBox: GithubLoginBox,
         db: any DatabaseWriter) {
        self.api = api
        self.auth = auth
        self.secretsStore = secretsStore
        self.secretBox = secretBox
        self.githubTokenBox = githubTokenBox
        self.githubLoginBox = githubLoginBox
        self.db = db
    }
```

Добавить методы (рядом с `createAccount`):

```swift
    /// Вход через GitHub OAuth: брокер-флоу → exchange → сохранить секреты и профиль.
    /// Создаёт фрешевый профиль. Старый api_secret-аккаунт (если был) не мигрируется —
    /// device_token перезаписывается новым.
    func signInWithGitHub(includePrivate: Bool) async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil

        do {
            let resp = try await auth.signIn(provider: "github", includePrivate: includePrivate)

            try secretsStore.setAiuse(resp.deviceToken)
            secretBox.value = resp.deviceToken

            if let token = resp.githubToken {
                try secretsStore.setGithubAuth(token: token, login: resp.githubLogin)
                githubTokenBox.value = token
                githubLoginBox.value = resp.githubLogin ?? ""
            }

            let row = MyProfileRow(
                id: 1,
                friendCode: resp.friendCode,
                displayName: resp.githubLogin ?? "anon",
                avatarPath: nil,
                sharingEnabled: false,
                serverUserId: resp.serverUserId,
                avatarBlob: nil,
                avatarMime: nil,
                avatarEtag: nil
            )
            try await db.write { try StatsQueries.saveMyProfile($0, row) }
            state = .created(row)
        } catch AuthError.cancelled {
            // молча — юзер сам закрыл окно входа
        } catch {
            errorMessage = "Не удалось войти: \(error.localizedDescription)"
        }
    }

    /// Тогл публичного глобального лидерборда.
    func toggleGlobalOptIn(_ enabled: Bool) async {
        guard case .created = state else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.patchProfile(globalOptIn: enabled)
        } catch {
            errorMessage = "Не удалось переключить публичный лидерборд: \(error.localizedDescription)"
        }
    }
```

> `toggleGlobalOptIn` не хранит `globalOptIn` в `MyProfileRow` локально (его там нет — это серверный флаг). Если потом понадобится показывать состояние тогла между запусками, добавить колонку в `my_profile` отдельной задачей. Для Phase 1 достаточно push-only.

- [ ] **Step 4: Починить существующие конструкторы VM**

Найти все места, где создаётся `AccountTabViewModel(...)` со старой сигнатурой (как минимум `AppContainer.makeAccountTabViewModel` — уже обновлён в Task 7, и существующие тесты в `AccountTabViewModelTests`). Прогон компилятора покажет все. Обновить каждый вызов под новую сигнатуру; в тестах, где GitHub-вход не нужен, передавать `FakeSignIn` с любым ответом и свежие `GithubTokenBox()`/`GithubLoginBox()`.

Run: `xcodebuild build -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED (после починки всех call site'ов).

- [ ] **Step 5: Запустить — проходит**

Run: `xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -only-testing:StatsAppTests/AccountTabViewModelTests`
Expected: PASS.

- [ ] **Step 6: Commit (Task 7 + 8 вместе)**

```bash
git add StatsApp/Network/KeychainStore.swift StatsApp/AppContainer.swift StatsApp/Settings/AccountTabViewModel.swift Tests/StatsAppTests/Settings/AccountTabViewModelTests.swift
git commit -m "feat(auth): вход через GitHub в AccountTabViewModel и wiring контейнера"
```

---

## Task 9: UI — кнопка входа и тогл публичного лидерборда

**Files:**
- Modify: `StatsApp/Settings/AccountTabView.swift`

UI без юнит-тестов (вью тонкий; логика покрыта в VM). Проверка — ручная сборка + визуальный smoke.

- [ ] **Step 1: Прочитать текущий AccountTabView**

Открыть `StatsApp/Settings/AccountTabView.swift`, найти ветку `.notCreated` (где сейчас форма создания профиля) и ветку `.created` (профиль есть).

- [ ] **Step 2: Добавить кнопку «Войти через GitHub» в ветку .notCreated**

В секцию для `.notCreated`, рядом с существующей формой создания, добавить primary-CTA:

```swift
Button {
    Task { await viewModel.signInWithGitHub(includePrivate: includePrivateRepos) }
} label: {
    Label("Войти через GitHub", systemImage: "person.badge.key")
}
.buttonStyle(.borderedProminent)
.disabled(viewModel.isWorking)

Toggle("Включая приватные репозитории", isOn: $includePrivateRepos)
    .font(.caption)
    .foregroundStyle(.secondary)
```

Добавить `@State private var includePrivateRepos = false` в начало вью.

> Существующую форму ручного создания профиля (`createAccount`) можно оставить как fallback или скрыть под «Дополнительно». Решение по UI — за исполнителем; логика обоих путей рабочая.

- [ ] **Step 3: Добавить тогл публичного лидерборда в ветку .created**

В секцию `.created`, рядом с существующим тоглом sharing, добавить:

```swift
Toggle("Показывать в публичном лидерборде", isOn: Binding(
    get: { globalOptInLocal },
    set: { newValue in
        globalOptInLocal = newValue
        Task { await viewModel.toggleGlobalOptIn(newValue) }
    }
))
.help("Твой handle, аватар и цифры станут видны публично на сайте")
```

Добавить `@State private var globalOptInLocal = false` (Phase 1: состояние локально оптимистичное; сервер — источник правды при следующем `reload`, который можно расширить в отдельной задаче).

- [ ] **Step 4: Сборка + ручной smoke**

Run: `xcodebuild build -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED.

Ручной smoke (после деплоя backend): открыть Settings → Аккаунт → «Войти через GitHub» → в браузере подтвердить → окно закрылось → профиль создан, friend_code показан.

- [ ] **Step 5: Commit**

```bash
git add StatsApp/Settings/AccountTabView.swift
git commit -m "feat(auth): UI входа через GitHub и тогл публичного лидерборда"
```

---

## Task 10: Полный прогон, локализация, README

**Files:**
- Modify: `Shared/Resources/ru.lproj/Localizable.strings`, `Shared/Resources/en.lproj/Localizable.strings` (если строки UI локализуются — см. существующий стиль)
- Modify: `README.md`

- [ ] **Step 1: Полный прогон тестов**

Run: `xcodebuild test -project ai-stats.xcodeproj -scheme StatsApp -destination 'platform=macOS'`
Expected: PASS — все тесты, включая существующие (Ccusage, GitHub, Database, Sync, SecretsStore, AiuseAPIClient, AccountTabViewModel и новые Crypto/AuthService).

- [ ] **Step 2: Локализация (если требуется)**

Если строки `"Войти через GitHub"` и т.п. должны быть локализованы — вынести в `Localizable.strings` (ru + en) и заменить на `NSLocalizedString`/`LocalizedStringKey` по образцу существующих вью. Если проект частично хардкодит RU-строки в UI (проверить соседние вью) — следовать тому же подходу, не разводить разнобой.

- [ ] **Step 3: README — раздел про GitHub-вход**

В `README.md` обновить раздел про GitHub: ручной PAT больше не обязателен — вход через GitHub OAuth (Settings → Аккаунт → «Войти через GitHub») выдаёт токен автоматически и подтягивает коммиты/LOC. PAT остаётся опциональным legacy-путём через `config.json`.

Отметить: multi-device — залогинься тем же GitHub на втором устройстве, статистика суммируется автоматически. Публичный лидерборд — тогл в Settings → Аккаунт, виден на сайте.

- [ ] **Step 4: Commit**

```bash
git add README.md Shared/Resources/ru.lproj/Localizable.strings Shared/Resources/en.lproj/Localizable.strings
git commit -m "docs: GitHub-вход, multi-device и публичный лидерборд в README"
```

---

## Self-Review

**1. Spec coverage** (против `2026-06-03-auth-and-sync-design.md`, клиентская часть):

| Раздел спеки | Где реализовано |
|---|---|
| §4.3 OAuth-брокер flow (start → web auth → exchange, PKCE-challenge) | Tasks 3, 5 |
| §4.5 восстановление через релогин | Task 8 (`signInWithGitHub` перезаписывает device_token) |
| §5.3 multi-device без парных кодов | Логин тем же GitHub → тот же серверный профиль (backend identity-match); клиент просто пишет новый device_token (Task 8) |
| §6.1 GitHub OAuth-токен вместо PAT | Tasks 6, 7, 8 (токен+логин в Keychain, фетчер из box) |
| §6.3 выбор scope (публичные/приватные) | Task 5 (`include_private`) + Task 9 (тогл UI) |
| §7.2 `global_opt_in` тогл | Tasks 2, 4, 8, 9 |
| §11 миграция: НЕ мигрируем (решение пользователя) | Task 8 (фрешевый профиль, device_token перезаписывается) |

**Сознательно НЕ в этом плане:** link-intent / привязка существующего api_secret-аккаунта (пользователь выбрал «пересоздать фреш»); live-rebuild GitHub-фетчера после входа в той же сессии (токен/логин персистятся, полноценно активируются при следующем запуске — отмечено); хранение `global_opt_in`/`sharing` состояния тогла локально между запусками (push-only в Phase 1); стрики/бейджи (фаза 2+).

**2. Placeholder scan:** код приведён целиком. Два места явно делегированы исполнителю с обоснованием, не плейсхолдеры: (а) точный способ поднять GRDB в `AccountTabViewModelTests` Step 1 — переиспользовать существующий хелпер файла, не выдумывать; (б) UI-решение «оставить ли ручную форму создания» в Task 9 — обе ветки рабочие. Это сознательная адаптация под существующий код, а не недописанные шаги.

**3. Type consistency:** `Crypto.sha256Hex`/`randomVerifier` (Task 3, исп. Task 5) · `WebAuthenticating.authenticate(url:callbackScheme:)` (Task 5) · `GitHubSignInService.signIn(provider:includePrivate:)` (Task 5, исп. Task 8 + тест) · `AuthExchangeResponse` поля `deviceToken/githubToken/githubLogin/friendCode/serverUserId` (Task 2, исп. Tasks 4,5,8) согласованы с серверными snake_case ключами через CodingKeys и с backend-планом (`github_login` добавлен в exchange) · `SecretsStore.setGithubAuth(token:login:)` (Task 6, исп. Task 8) · `GithubLoginBox` (Task 7, исп. Tasks 7,8) · `AccountTabViewModel.init` новая сигнатура (Task 8) согласована с `AppContainer.makeAccountTabViewModel` (Task 7).

**Ключевые риски для исполнителя:**
- **`MyProfileRow` поля** (Task 8 Step 3) скопированы из существующего `createAccount`. Если структура `MyProfileRow` отличается — свериться с `Shared/Storage/Models.swift` и `StatsQueries.saveMyProfile`, подогнать инициализатор.
- **`ASWebAuthenticationSession` в menu bar app** (Task 5): presentation anchor через свежее `NSWindow`, если нет видимого окна. На реальном устройстве проверить, что окно входа появляется и не висит за menu bar. Это единственное место, которое юнит-тестами не ловится — обязательный ручной smoke (Task 9 Step 4).
- **Промежуточные сборки** (Task 7 → 8): между ними проект не компилируется (новая сигнатура VM). Коммит — только после Task 8.
