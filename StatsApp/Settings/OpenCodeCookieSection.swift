import SwiftUI

/// Cookie сессии opencode.ai. Секрет — живёт только в Keychain, в UserDefaults и
/// в логи не попадает никогда.
struct OpenCodeCookieStore {
    private let keychain: KeychainStore
    private let account: String

    init(keychain: KeychainStore = MacOSKeychainStore(), account: String = NSUserName()) {
        self.keychain = keychain
        self.account = account
    }

    func load() -> String? {
        keychain.get(account: account, service: OpenCodeLimitsFetcher.keychainService)
    }

    /// Пустая строка значит «убрать»: хранить пустой секрет незачем.
    func save(_ raw: String) throws {
        let normalized = OpenCodeUsageParser.normalizeCookie(raw)
        guard !normalized.isEmpty else {
            try clear()
            return
        }
        try keychain.set(normalized, account: account,
                         service: OpenCodeLimitsFetcher.keychainService)
    }

    func clear() throws {
        try keychain.delete(account: account, service: OpenCodeLimitsFetcher.keychainService)
    }
}

struct OpenCodeCookieSection: View {
    @State private var cookie: String = ""
    @State private var checkResult: String?
    @State private var checking = false

    private let store = OpenCodeCookieStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Лимиты OpenCode")
                .font(.headline)

            Text("""
            Ключи моделей для этого не годятся — нужна сессионная cookie сайта. \
            Открой opencode.ai, залогинься, в DevTools скопируй значение cookie \
            auth и вставь сюда.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)

            SecureField("auth=Fe26.2**…", text: $cookie)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Сохранить") { save() }
                Button(checking ? "Проверяю…" : "Проверить") { Task { await check() } }
                    .disabled(checking)
                if let checkResult {
                    Text(checkResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { cookie = store.load() ?? "" }
    }

    private func save() {
        do {
            try store.save(cookie)
            checkResult = cookie.trimmingCharacters(in: .whitespaces).isEmpty ? "убрана" : "сохранена"
        } catch {
            // В текст ошибки значение cookie не подставляем ни при каких условиях.
            checkResult = "не удалось сохранить"
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        do { try store.save(cookie) } catch { checkResult = "не удалось сохранить"; return }

        let limits = await OpenCodeLimitsFetcher().fetch()
        switch limits.status {
        case .ok:
            let windows = limits.windows.count
            checkResult = "работает, окон: \(windows)"
        case .unconfigured:  checkResult = "cookie пустая"
        case .unauthorized:  checkResult = "cookie не принята"
        case .unavailable:   checkResult = "страница не разобралась"
        case .stale, .throttled: checkResult = "не достучался"
        }
    }
}
