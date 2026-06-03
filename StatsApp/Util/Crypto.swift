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
