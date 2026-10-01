import Foundation

/// The encrypted vault: one PBKDF2-stretched key wraps a random master key, and every
/// secret is sealed with that master key.
///
/// Layout
/// ------
///   password --PBKDF2-HMAC-SHA512(salt, iterations)--> key-encryption key (KEK)
///   KEK --AES-256-GCM--> wrapped master key
///   master key --AES-256-GCM--> each item
///
/// Nothing secret is ever written in the clear: the file holds a salt, a nonce, the wrapped
/// master key, and per-item ciphertext. Changing the password re-wraps the master key only,
/// so items never have to be touched. The GCM additional authenticated data binds the
/// format version, the iteration count and the salt, so a tampered header fails to open
/// rather than silently deriving a different key.
public enum VaultError: Error, Equatable {
    case unsupportedVersion(Int)
    case wrongPassword
    case tamperedItem(id: String)
    case itemRemoved(id: String)
    case malformed(String)
    case cryptoUnavailable
}

public enum VaultKind: String, Codable, CaseIterable, Sendable {
    case mnemonic
    case privateKey
    case passphrase
    case note

    public var title: String {
        switch self {
        case .mnemonic: return "Recovery phrase"
        case .privateKey: return "Private key"
        case .passphrase: return "BIP-39 passphrase"
        case .note: return "Note"
        }
    }
}

public struct VaultItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: VaultKind
    public var label: String
    /// A non-secret identifier shown in lists: the first derived address, or a short hash.
    public var hint: String
    public var createdAt: Date
    public var nonce: Data
    public var ciphertext: Data
    public var tag: Data
}

public struct VaultHeader: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let kdfName = "pbkdf2-hmac-sha512"

    public var version: Int
    public var kdf: String
    public var iterations: Int
    public var salt: Data
    public var wrapNonce: Data
    public var wrappedKey: Data
    public var wrapTag: Data
    public var createdAt: Date
}

public struct Vault: Codable, Equatable, Sendable {
    public var header: VaultHeader
    public var items: [VaultItem]
    public var revision: Int
}

extension Vault {
    /// OWASP-style floor for PBKDF2-HMAC-SHA512; the app uses this, tests use less.
    public static let defaultIterations = 600_000

    static func wrapAAD(iterations: Int, salt: Data) -> Data {
        var aad = Data("SentinelVault-v1".utf8)
        aad.append(UInt8((iterations >> 24) & 0xff))
        aad.append(UInt8((iterations >> 16) & 0xff))
        aad.append(UInt8((iterations >> 8) & 0xff))
        aad.append(UInt8(iterations & 0xff))
        aad.append(salt)
        return aad
    }

    static func itemAAD(id: String) -> Data {
        Data("SentinelVaultItem-v1".utf8) + Data(id.utf8)
    }

    /// Derives the key-encryption key. CommonCrypto on Apple platforms, the pure-Swift
    /// PBKDF2 elsewhere.
    public static func keyEncryptionKey(password: String, salt: Data, iterations: Int) -> Data {
        guard iterations > 0, !salt.isEmpty else { return Data() }
        #if canImport(CommonCrypto)
        return CommonCryptoPBKDF2.sha512(password: Data(password.utf8), salt: salt,
                                         iterations: iterations, keyLength: 32)
        #else
        return PBKDF2.derive(algorithm: .sha512, password: Data(password.utf8), salt: salt,
                             iterations: iterations, keyLength: 32)
        #endif
    }

    public static func create(password: String,
                              iterations: Int = Vault.defaultIterations,
                              salt: Data = RandomBytes.bytes(32),
                              wrapNonce: Data = AESGCM.randomNonce(),
                              masterKey: Data = RandomBytes.bytes(32),
                              createdAt: Date = Date()) throws -> UnlockedVault {
        guard masterKey.count == 32 else { throw VaultError.malformed("master key must be 32 bytes") }
        guard iterations > 0 else { throw VaultError.malformed("iterations must be positive") }
        let kek = keyEncryptionKey(password: password, salt: salt, iterations: iterations)
        let sealed = try AESGCM.seal(masterKey, key: kek,
                                     nonce: wrapNonce,
                                     aad: wrapAAD(iterations: iterations, salt: salt))
        let header = VaultHeader(version: VaultHeader.currentVersion,
                                 kdf: VaultHeader.kdfName,
                                 iterations: iterations,
                                 salt: salt,
                                 wrapNonce: sealed.nonce,
                                 wrappedKey: sealed.ciphertext,
                                 wrapTag: sealed.tag,
                                 createdAt: createdAt)
        return UnlockedVault(vault: Vault(header: header, items: [], revision: 1), masterKey: masterKey)
    }

    public static func unlock(_ vault: Vault, password: String) throws -> UnlockedVault {
        guard vault.header.version == VaultHeader.currentVersion else {
            throw VaultError.unsupportedVersion(vault.header.version)
        }
        guard vault.header.kdf == VaultHeader.kdfName else {
            throw VaultError.malformed("unknown key derivation: \(vault.header.kdf)")
        }
        guard vault.header.salt.count == 32, vault.header.iterations > 0 else {
            throw VaultError.malformed("header is incomplete")
        }
        let kek = keyEncryptionKey(password: password, salt: vault.header.salt, iterations: vault.header.iterations)
        let sealed = AESGCM.Sealed(nonce: vault.header.wrapNonce,
                                   ciphertext: vault.header.wrappedKey,
                                   tag: vault.header.wrapTag)
        do {
            let master = try AESGCM.open(sealed, key: kek,
                                         aad: wrapAAD(iterations: vault.header.iterations, salt: vault.header.salt))
            return UnlockedVault(vault: vault, masterKey: master)
        } catch {
            // GCM cannot tell a wrong password from a damaged file, and neither should we.
            throw VaultError.wrongPassword
        }
    }

    public static func encode(_ vault: Vault) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(vault)
    }

    public static func decode(_ data: Data) throws -> Vault {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let vault = try decoder.decode(Vault.self, from: data)
            guard vault.header.version == VaultHeader.currentVersion else {
                throw VaultError.unsupportedVersion(vault.header.version)
            }
            return vault
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.malformed("vault file is not readable")
        }
    }

}

/// An unlocked view over the vault: the only thing that can read or write secrets.
public struct UnlockedVault: Sendable {
    public private(set) var vault: Vault
    private let masterKey: Data
    /// Items deleted in this session. A caller may still hold a `VaultItem` value it copied
    /// out earlier; keeping the ids here means a deleted secret cannot be read back even
    /// from a stale handle. (The ciphertext is gone from the file, which is the real
    /// guarantee; this closes the window inside the running session.)
    private var removedIDs: Set<String> = []

    init(vault: Vault, masterKey: Data) {
        self.vault = vault
        self.masterKey = masterKey
    }

    public var itemCount: Int { vault.items.count }

    public func secret(of item: VaultItem) throws -> Data {
        guard !removedIDs.contains(item.id) else { throw VaultError.itemRemoved(id: item.id) }
        let sealed = AESGCM.Sealed(nonce: item.nonce, ciphertext: item.ciphertext, tag: item.tag)
        do {
            return try AESGCM.open(sealed, key: masterKey, aad: Vault.itemAAD(id: item.id))
        } catch {
            throw VaultError.tamperedItem(id: item.id)
        }
    }

    @discardableResult
    public mutating func add(kind: VaultKind,
                             label: String,
                             hint: String,
                             secret: Data,
                             id: String = UUID().uuidString,
                             nonce: Data = AESGCM.randomNonce(),
                             createdAt: Date = Date()) throws -> VaultItem {
        let sealed = try AESGCM.seal(secret, key: masterKey, nonce: nonce, aad: Vault.itemAAD(id: id))
        let item = VaultItem(id: id, kind: kind, label: label, hint: hint, createdAt: createdAt,
                             nonce: sealed.nonce, ciphertext: sealed.ciphertext, tag: sealed.tag)
        vault.items.append(item)
        vault.revision += 1
        return item
    }

    public mutating func remove(id: String) {
        let before = vault.items.count
        vault.items.removeAll { $0.id == id }
        guard vault.items.count != before else { return }
        removedIDs.insert(id)
        vault.revision += 1
    }

    public mutating func rename(id: String, to label: String) {
        guard let index = vault.items.firstIndex(where: { $0.id == id }) else { return }
        vault.items[index].label = label
        vault.revision += 1
    }

    /// New password, new salt, new nonce — items keep working because they are sealed with
    /// the master key, which is only re-wrapped here.
    @discardableResult
    public mutating func changePassword(to password: String,
                                        iterations: Int = Vault.defaultIterations,
                                        salt: Data = RandomBytes.bytes(32),
                                        wrapNonce: Data = AESGCM.randomNonce()) throws -> Vault {
        let kek = Vault.keyEncryptionKey(password: password, salt: salt, iterations: iterations)
        let sealed = try AESGCM.seal(masterKey, key: kek, nonce: wrapNonce,
                                     aad: Vault.wrapAAD(iterations: iterations, salt: salt))
        vault.header.iterations = iterations
        vault.header.salt = salt
        vault.header.wrapNonce = sealed.nonce
        vault.header.wrappedKey = sealed.ciphertext
        vault.header.wrapTag = sealed.tag
        vault.revision += 1
        return vault
    }

    /// The sealed form, safe to write to disk.
    public var sealed: Vault { vault }
}

#if canImport(CommonCrypto)
/// CommonCrypto's PBKDF2 — Apple's accelerated implementation, used on device.
enum CommonCryptoPBKDF2 {
    static func sha512(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        var derived = Data(count: keyLength)
        let result = derived.withUnsafeMutableBytes { out -> Int32 in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         passwordBytes.bindMemory(to: Int8.self).baseAddress, password.count,
                                         saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                                         UInt32(iterations),
                                         out.bindMemory(to: UInt8.self).baseAddress, keyLength)
                }
            }
        }
        precondition(result == kCCSuccess, "PBKDF2 failed")
        return derived
    }
}
#endif
