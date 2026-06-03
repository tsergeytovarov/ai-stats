import Foundation

/// Клиент для `https://aiuse.popovs.tech/api`. Тонкая обёртка над URLSession.
/// `secretProvider` — closure которая лезет в Keychain (чтобы клиент не зависел
/// от KeychainStore API напрямую — тестируется через моки).
final class AiuseAPIClient {
    /// Жёсткий кап на размер JSON-ответа от aiuse. Защита от malicious/compromised
    /// сервера, который попытается съесть память клиента.
    static let maxResponseBytes = 1 * 1024 * 1024   // 1 MB

    /// Жёсткий кап на размер аватарки. Сами пикаем при создании профиля максимум
    /// 200 KB (AccountTabView), поэтому 512 KB на ответ — щедрый запас.
    static let maxAvatarBytes = 512 * 1024          // 512 KB

    /// MIME allowlist для /avatars. Всё остальное (image/svg+xml, image/webp, etc.)
    /// отбрасываем — историчecки в ImageIO ловили CVE на парсинг разных форматов.
    static let allowedAvatarMimes: Set<String> = ["image/png", "image/jpeg"]

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

    // MARK: - profiles

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

    func patchProfile(displayName: String? = nil,
                      avatar: Data? = nil,
                      avatarMime: String? = nil,
                      sharingEnabled: Bool? = nil) async throws -> ProfileResponse {
        let body = ProfileUpdateRequest(
            displayName: displayName,
            avatarB64: avatar?.base64EncodedString(),
            avatarMime: avatarMime,
            sharingEnabled: sharingEnabled,
            globalOptIn: nil
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

    // MARK: - friends

    func addFriend(friendCode: String) async throws -> FriendDTO {
        let validated = try FriendCode.validated(friendCode)
        return try await request(
            path: "/friends",
            method: "POST",
            body: AddFriendRequest(friendCode: validated),
            authed: true,
            decodeAs: FriendDTO.self
        )
    }

    func listFriends() async throws -> [FriendDTO] {
        let resp = try await request(
            path: "/friends",
            method: "GET",
            authed: true,
            decodeAs: FriendsListResponse.self
        )
        return resp.friends
    }

    func removeFriend(friendCode: String, block: Bool = false) async throws {
        let validated = try FriendCode.validated(friendCode)
        // `block` дублируется в query И в body. Body — для backward-compat с текущим
        // сервером, query — для устойчивости к CDN/proxy которые DELETE body выкидывают.
        // Когда сервер начнёт читать `block` из query, body можно будет убрать.
        _ = try await request(
            path: "/friends/\(validated)",
            method: "DELETE",
            query: ["block": block ? "true" : "false"],
            body: RemoveFriendRequest(block: block),
            authed: true,
            decodeAs: EmptyResponse.self
        )
    }

    // MARK: - leaderboard

    func getLeaderboard(period: String) async throws -> LeaderboardResponse {
        return try await request(
            path: "/leaderboard",
            method: "GET",
            query: ["period": period],
            authed: true,
            decodeAs: LeaderboardResponse.self
        )
    }

    // MARK: - blocks

    func listBlocks() async throws -> [BlockDTO] {
        let resp = try await request(
            path: "/blocks",
            method: "GET",
            authed: true,
            decodeAs: BlocksListResponse.self
        )
        return resp.blocked
    }

    func unblock(friendCode: String) async throws {
        let validated = try FriendCode.validated(friendCode)
        _ = try await request(
            path: "/blocks/\(validated)",
            method: "DELETE",
            authed: true,
            decodeAs: EmptyResponse.self
        )
    }

    // MARK: - avatars

    /// Запрос аватарки. Возвращает (data, mime, etag) — или nil если 304 / 404.
    /// ifNoneMatch — ETag из предыдущего ответа для conditional GET.
    ///
    /// **Безопасность:** ответ ограничен `maxAvatarBytes` (512 KB) и обязан иметь
    /// `Content-Type` из allowlist `{image/png, image/jpeg}`. Иначе бросает ошибку
    /// до того, как байты попадут в `NSImage(data:)` — закрывает RCE-вектор через
    /// malformed image (CVE-классов ImageIO).
    func getAvatar(friendCode: String, ifNoneMatch: String? = nil) async throws -> (data: Data, mime: String?, etag: String?)? {
        guard let secret = secretProvider() else { throw AiuseAPIError.missingSecret }
        // friend_code приходит из server-side data (FriendsPullSyncer), но всё равно валидируем —
        // defense in depth, чтобы скомпрометированный сервер не смог подсунуть `..` в URL.
        let validated = try FriendCode.validated(friendCode)

        var url = baseURL
        url.append(path: "/avatars/\(validated)")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if let ifNoneMatch {
            req.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: req)
        } catch {
            throw AiuseAPIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AiuseAPIError.unexpected
        }

        if http.statusCode == 304 || http.statusCode == 404 {
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AiuseAPIError.http(status: http.statusCode, body: "")
        }

        // MIME-allowlist: режим check-then-read. Чарсет-довески ("image/png; charset=..")
        // отрезаем — нас интересует только сам тип.
        let rawMime = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        let mime = rawMime.split(separator: ";").first.map {
            String($0).trimmingCharacters(in: .whitespaces).lowercased()
        } ?? ""
        guard Self.allowedAvatarMimes.contains(mime) else {
            throw AiuseAPIError.avatarBadMime(mime: rawMime)
        }

        // Content-Length precheck (можно отвалиться до чтения тела).
        if let lenStr = http.value(forHTTPHeaderField: "Content-Length"),
           let len = Int(lenStr), len > Self.maxAvatarBytes {
            throw AiuseAPIError.avatarTooLarge(bytes: len)
        }

        let data = try await Self.readWithCap(bytes, cap: Self.maxAvatarBytes, onOverflow: { count in
            AiuseAPIError.avatarTooLarge(bytes: count)
        })
        let etag = http.value(forHTTPHeaderField: "ETag")
        return (data, mime, etag)
    }

    /// Streaming-чтение байтов с жёстким капом. При превышении бросает указанную ошибку,
    /// не дочитывает остаток. Используется и `getAvatar`, и JSON-ом `request`.
    private static func readWithCap(
        _ bytes: URLSession.AsyncBytes,
        cap: Int,
        onOverflow: (Int) -> Error
    ) async throws -> Data {
        var data = Data()
        data.reserveCapacity(min(cap, 64 * 1024))
        for try await byte in bytes {
            data.append(byte)
            if data.count > cap {
                throw onOverflow(data.count)
            }
        }
        return data
    }

    // MARK: - snapshots

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

    // MARK: - core

    private func request<R: Decodable>(
        path: String,
        method: String,
        query: [String: String] = [:],
        body: Encodable? = nil,
        authed: Bool = true,
        decodeAs: R.Type
    ) async throws -> R {
        var url = baseURL
        url.append(path: path)
        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw AiuseAPIError.invalidURL
            }
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let finalURL = components.url else { throw AiuseAPIError.invalidURL }
            url = finalURL
        }
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

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: req)
        } catch {
            throw AiuseAPIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AiuseAPIError.unexpected
        }

        // Content-Length precheck: можно отвалиться до чтения тела (на случай
        // компрометированного aiuse, который захочет залить нам GB JSON-а).
        if let lenStr = http.value(forHTTPHeaderField: "Content-Length"),
           let len = Int(lenStr), len > Self.maxResponseBytes {
            throw AiuseAPIError.responseTooLarge(bytes: len)
        }

        let data = try await Self.readWithCap(bytes, cap: Self.maxResponseBytes, onOverflow: { count in
            AiuseAPIError.responseTooLarge(bytes: count)
        })

        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw AiuseAPIError.http(status: http.statusCode, body: bodyString)
        }

        if R.self == EmptyResponse.self {
            // Для 204 No Content
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

/// Type-erased wrapper для Encodable — JSONEncoder.encode имеет generic-сигнатуру.
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
