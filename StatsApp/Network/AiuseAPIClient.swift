import Foundation

/// Клиент для `https://aiuse.popovs.tech/api`. Тонкая обёртка над URLSession.
/// `secretProvider` — closure которая лезет в Keychain (чтобы клиент не зависел
/// от KeychainStore API напрямую — тестируется через моки).
final class AiuseAPIClient {
    /// Жёсткий кап на размер JSON-ответа от aiuse. Защита от malicious/compromised
    /// сервера, который попытается съесть память клиента.
    static let maxResponseBytes = 1 * 1024 * 1024   // 1 MB

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

    /// Текущий профиль с сервера (включая sharing_enabled) — источник правды
    /// для синхронизации локального флага шаринга.
    func getMyProfile() async throws -> ProfileResponse {
        return try await request(
            path: "/profiles/me",
            method: "GET",
            authed: true,
            decodeAs: ProfileResponse.self
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

    func linkIntent() async throws -> LinkIntentResponse {
        return try await request(
            path: "/auth/link-intent",
            method: "POST",
            authed: true,
            decodeAs: LinkIntentResponse.self
        )
    }

    /// Streaming-чтение байтов с жёстким капом. При превышении бросает указанную ошибку,
    /// не дочитывает остаток. Используется JSON-декодером `request`.
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
