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
