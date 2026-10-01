import Foundation

#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

/// Ed25519 public keys for Solana. Apple's CryptoKit does the maths (and is the right
/// primitive on device); the Package manifest pulls in swift-crypto on Linux so the same
/// code path is covered by `swift test` in CI.
public enum Ed25519 {
    public static var isAvailable: Bool {
        #if canImport(CryptoKit) || canImport(Crypto)
        return true
        #else
        return false
        #endif
    }

    public static func publicKey(fromSeed seed: Data) -> Data? {
        guard seed.count == 32 else { return nil }
        #if canImport(CryptoKit) || canImport(Crypto)
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else { return nil }
        return key.publicKey.rawRepresentation
        #else
        return nil
        #endif
    }
}
