import Foundation

enum GithubAvatar {
    /// Тянет аватар GitHub-юзера по логину: https://github.com/<login>.png?size=256
    /// Best-effort: возвращает nil при любой ошибке/неподходящем ответе. Кап 512 KB.
    static func fetch(login: String, session: URLSession = .shared) async -> (data: Data, mime: String)? {
        guard let url = URL(string: "https://github.com/\(login).png?size=256") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            guard data.count <= 512 * 1024 else { return nil }
            // GitHub отдаёт png/jpeg; берём content-type, иначе png
            let raw = (http.value(forHTTPHeaderField: "Content-Type") ?? "image/png").lowercased()
            let mime = raw.contains("jpeg") || raw.contains("jpg") ? "image/jpeg" : "image/png"
            return (data, mime)
        } catch {
            return nil
        }
    }
}
