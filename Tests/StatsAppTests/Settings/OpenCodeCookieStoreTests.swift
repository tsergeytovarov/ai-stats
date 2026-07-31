import XCTest
@testable import StatsApp

final class OpenCodeCookieStoreTests: XCTestCase {

    private func store() -> (OpenCodeCookieStore, MemoryKeychainStore) {
        let keychain = MemoryKeychainStore()
        return (OpenCodeCookieStore(keychain: keychain, account: "tester"), keychain)
    }

    // Cookie — секрет, лежит только в Keychain и только в auth-виде.
    func test_saves_normalized_cookie_to_keychain() throws {
        let (subject, keychain) = store()
        try subject.save("  Fe26.2**abc  ")
        XCTAssertEqual(keychain.get(account: "tester",
                                    service: OpenCodeLimitsFetcher.keychainService),
                       "auth=Fe26.2**abc")
    }

    func test_load_returns_nil_when_empty() {
        let (subject, _) = store()
        XCTAssertNil(subject.load())
    }

    func test_clear_removes_value() throws {
        let (subject, keychain) = store()
        try subject.save("Fe26.2**abc")
        try subject.clear()
        XCTAssertNil(keychain.get(account: "tester",
                                  service: OpenCodeLimitsFetcher.keychainService))
    }

    // Пустая строка — это «убрать», а не «сохранить пустоту».
    func test_saving_blank_clears() throws {
        let (subject, keychain) = store()
        try subject.save("Fe26.2**abc")
        try subject.save("   ")
        XCTAssertNil(keychain.get(account: "tester",
                                  service: OpenCodeLimitsFetcher.keychainService))
    }
}
