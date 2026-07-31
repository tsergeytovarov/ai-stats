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
    /// Поле всегда стартует пустым: подгружать сюда сохранённый секрет незачем,
    /// SecureField его всё равно маскирует, а plaintext в @State — лишняя
    /// поверхность утечки. Факт наличия показываем отдельной подписью.
    @State private var cookie: String = ""
    @State private var hasSavedCookie = false
    @State private var checkResult: String?
    @State private var checking = false

    private let store = OpenCodeCookieStore()

    /// Разовая проверка идёт мимо LimitsCoordinator — без этого колбэка попап
    /// до следующего тика координатора продолжал бы показывать старое
    /// состояние, хотя человек только что увидел «работает» (находка 12
    /// финального ревью). По умолчанию no-op — превью и другие вызовы без
    /// AppContainer под рукой не обязаны его прокидывать.
    var onChecked: (ProviderLimits) async -> Void = { _ in }

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

            Text(hasSavedCookie ? "cookie сохранена" : "cookie не задана")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Сохранить") { save() }
                if hasSavedCookie {
                    Button("Убрать") { remove() }
                }
                Button(checking ? "Проверяю…" : "Проверить") { Task { await check() } }
                    .disabled(checking)
                if let checkResult {
                    Text(checkResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { hasSavedCookie = store.load() != nil }
    }

    /// Пустое поле здесь — не «убрать», а «ничего не вводил»: не трогаем
    /// уже сохранённую cookie. Убрать её можно только явной кнопкой ниже.
    ///
    /// Проверяем через normalizeCookie, а не через .whitespaces: это та же
    /// функция, что store.save() применит к значению перед записью — раньше
    /// здесь был отдельный .whitespaces-трим, и строка из одного перевода
    /// строки проходила guard как «непустая», а внутри normalizeCookie
    /// нормализовалась в пустую и тихо стирала уже сохранённую cookie
    /// (находка 9 финального ревью).
    private func save() {
        guard !OpenCodeUsageParser.normalizeCookie(cookie).isEmpty else { return }
        do {
            try store.save(cookie)
            hasSavedCookie = true
            // Значение уже в Keychain — держать его в состоянии незачем.
            cookie = ""
            checkResult = "сохранена"
        } catch {
            // В текст ошибки значение cookie не подставляем ни при каких условиях.
            checkResult = "не удалось сохранить"
        }
    }

    private func remove() {
        do {
            try store.clear()
            hasSavedCookie = false
            cookie = ""
            checkResult = "убрана"
        } catch {
            checkResult = "не удалось убрать"
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }

        // Сохраняем только если в поле что-то ввели; если оно пустое, а cookie
        // уже сохранена — проверяем то, что уже лежит в Keychain, ничего не трогая.
        // Тот же normalizeCookie, что и в save() — иначе тут воспроизводится
        // та же находка 9: строка из одних пробелов/переводов строки прошла
        // бы этот guard, но store.save() всё равно её сотрёт.
        if !OpenCodeUsageParser.normalizeCookie(cookie).isEmpty {
            do {
                try store.save(cookie)
                hasSavedCookie = true
                cookie = ""
            } catch {
                checkResult = "не удалось сохранить"
                return
            }
        }

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
        // Записываем результат в общее состояние — попап должен показать то
        // же самое, что человек только что увидел здесь, не дожидаясь
        // следующего тика координатора.
        await onChecked(limits)
    }
}
