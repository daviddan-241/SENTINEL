import Foundation

#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto        // swift-crypto: same API surface as CryptoKit
#endif

/// AES-256-GCM with an explicit nonce and additional authenticated data.
///
/// Both CryptoKit (Apple platforms) and swift-crypto (Linux, used by the test suite) expose
/// `AES.GCM`, so this shim is the only place that knows which one is present.
public enum AESGCM {
    public struct Sealed: Equatable, Sendable {
        public let nonce: Data
        public let ciphertext: Data
        public let tag: Data

        public init(nonce: Data, ciphertext: Data, tag: Data) {
            self.nonce = nonce
            self.ciphertext = ciphertext
            self.tag = tag
        }
    }

    public enum Failure: Error, Equatable {
        case badKeyLength(Int)
        case badNonceLength(Int)
        case authenticationFailed
        case unavailable
    }

    public static let nonceLength = 12

    public static func seal(_ plaintext: Data, key: Data, nonce: Data, aad: Data) throws -> Sealed {
        guard key.count == 32 else { throw Failure.badKeyLength(key.count) }
        guard nonce.count == nonceLength else { throw Failure.badNonceLength(nonce.count) }
        do {
            let box = try AES.GCM.seal(plaintext,
                                       using: SymmetricKey(data: key),
                                       nonce: AES.GCM.Nonce(data: nonce),
                                       authenticating: aad)
            return Sealed(nonce: nonce, ciphertext: box.ciphertext, tag: box.tag)
        } catch {
            throw Failure.authenticationFailed
        }
    }

    public static func open(_ sealed: Sealed, key: Data, aad: Data) throws -> Data {
        guard key.count == 32 else { throw Failure.badKeyLength(key.count) }
        guard sealed.nonce.count == nonceLength else { throw Failure.badNonceLength(sealed.nonce.count) }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: sealed.nonce),
                                            ciphertext: sealed.ciphertext,
                                            tag: sealed.tag)
            return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad)
        } catch {
            throw Failure.authenticationFailed
        }
    }

    /// Re-exported so callers can use the same random source for nonces.
    public static func randomNonce() -> Data { RandomBytes.bytes(nonceLength) }
}
