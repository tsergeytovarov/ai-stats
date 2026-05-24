import Foundation

/// Клиент для `https://aiuse.popovs.tech/api`. Тонкая обёртка над URLSession.
/// `secretProvider` — closure которая лезет в Keychain (чтобы клиент не зависел
/// от KeychainStore API напрямую — тестируется через моки).
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
        _ = try await request(
            path: "/friends/\(validated)",
            method: "DELETE",
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
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
        let mime = http.value(forHTTPHeaderField: "Content-Type")
        let etag = http.value(forHTTPHeaderField: "ETag")
        return (data, mime, etag)
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AiuseAPIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AiuseAPIError.unexpected
        }
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
