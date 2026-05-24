import XCTest
@testable import StatsApp

final class FriendCodeTests: XCTestCase {
    // MARK: - normalize

    func test_normalize_strips_dashes_and_spaces() {
        XCTAssertEqual(FriendCode.normalize("XK7P-3M9Q-2A"), "XK7P3M9Q2A")
        XCTAssertEqual(FriendCode.normalize("  xk7p 3m9q 2a  "), "XK7P3M9Q2A")
        XCTAssertEqual(FriendCode.normalize("xk7p\t3m9q\n2a"), "XK7P3M9Q2A")
    }

    func test_normalize_uppercases() {
        XCTAssertEqual(FriendCode.normalize("abcdefghij"), "ABCDEFGHIJ")
    }

    func test_normalize_drops_non_ascii_alphanumeric() {
        // эмодзи/кириллица — выкидываются
        XCTAssertEqual(FriendCode.normalize("XK7P3M9Q2A😀"), "XK7P3M9Q2A")
        XCTAssertEqual(FriendCode.normalize("привет"), "")
    }

    // MARK: - validated

    func test_validated_accepts_canonical_form() throws {
        XCTAssertEqual(try FriendCode.validated("XK7P3M9Q2A"), "XK7P3M9Q2A")
    }

    func test_validated_accepts_dashed_form() throws {
        XCTAssertEqual(try FriendCode.validated("XK7P-3M9Q-2A"), "XK7P3M9Q2A")
    }

    func test_validated_accepts_lowercase_and_normalizes() throws {
        XCTAssertEqual(try FriendCode.validated("xk7p-3m9q-2a"), "XK7P3M9Q2A")
    }

    func test_validated_rejects_short() {
        XCTAssertThrowsError(try FriendCode.validated("XK7P3M9Q")) { err in
            guard case AiuseAPIError.invalidFriendCode = err else {
                return XCTFail("ожидали invalidFriendCode, получили \(err)")
            }
        }
    }

    func test_validated_rejects_long() {
        XCTAssertThrowsError(try FriendCode.validated("XK7P3M9Q2AB")) { err in
            guard case AiuseAPIError.invalidFriendCode = err else {
                return XCTFail("ожидали invalidFriendCode, получили \(err)")
            }
        }
    }

    func test_validated_rejects_empty() {
        XCTAssertThrowsError(try FriendCode.validated("")) { err in
            guard case AiuseAPIError.invalidFriendCode = err else {
                return XCTFail("ожидали invalidFriendCode, получили \(err)")
            }
        }
    }

    func test_validated_rejects_path_traversal_attempt() {
        // Главный риск который мы закрываем: попытка просунуть `..` в URL.
        XCTAssertThrowsError(try FriendCode.validated("../admin"))
        XCTAssertThrowsError(try FriendCode.validated("XK7P/../adm"))
        XCTAssertThrowsError(try FriendCode.validated("XK7P3M9Q2A/admin"))
    }

    func test_validated_rejects_query_string_injection() {
        XCTAssertThrowsError(try FriendCode.validated("XK7P3M9Q2A?admin=1"))
        XCTAssertThrowsError(try FriendCode.validated("XK7P3M9Q2A#frag"))
    }

    func test_validated_rejects_non_ascii() {
        XCTAssertThrowsError(try FriendCode.validated("XK7P3M9Q2А"))  // последняя А — кириллица
    }

    func test_validated_error_carries_original_input() {
        do {
            _ = try FriendCode.validated("bogus")
            XCTFail("должно бросить")
        } catch let AiuseAPIError.invalidFriendCode(raw) {
            XCTAssertEqual(raw, "bogus", "ошибка должна содержать оригинальный ввод для UI")
        } catch {
            XCTFail("неожиданная ошибка: \(error)")
        }
    }
}
