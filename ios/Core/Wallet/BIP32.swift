import Foundation

/// BIP-32 hierarchical deterministic keys, extended to the SLIP-132 prefixes that
/// Bitcoin wallets use for ypub/zpub accounts.
public struct ExtendedPrivateKey: Sendable {
    public let privateKey: UInt256
    public let chainCode: Data
    public let depth: UInt8
    public let parentFingerprint: Data          // 4 bytes
    public let index: UInt32
    public let version: UInt32                  // SLIP-132 aware

    public init(privateKey: UInt256, chainCode: Data, depth: UInt8 = 0,
                parentFingerprint: Data = Data(repeating: 0, count: 4),
                index: UInt32 = 0, version: UInt32 = 0x0488ADE4) {
        self.privateKey = privateKey
        self.chainCode = chainCode
        self.depth = depth
        self.parentFingerprint = parentFingerprint
        self.index = index
        self.version = version
    }

    public var publicKey: Secp256k1.Point {
        // A derived key is always in range; the guard keeps the type system honest.
        Secp256k1.multiplyGenerator(privateKey) ?? Secp256k1.generator
    }

    public var compressedPublicKey: Data { Secp256k1.compressed(publicKey) }

    public var fingerprint: Data { RIPEMD160.hash(SHA256.hash(compressedPublicKey)).prefix(4) }

    public var identifier: Data { RIPEMD160.hash(SHA256.hash(compressedPublicKey)) }

    public var serialized: String {
        var payload = Data()
        payload.append(uint32: version)
        payload.append(depth)
        payload.append(parentFingerprint)
        payload.append(uint32: index)
        payload.append(chainCode)
        payload.append(0x00)                       // private key marker
        payload.append(privateKey.data)
        return Base58.encodeCheck(payload)
    }

    public var publicSerialized: String {
        var payload = Data()
        // private version → public version (SLIP-132 aware where relevant)
        payload.append(uint32: Self.publicVersion(for: version))
        payload.append(depth)
        payload.append(parentFingerprint)
        payload.append(uint32: index)
        payload.append(chainCode)
        payload.append(compressedPublicKey)
        return Base58.encodeCheck(payload)
    }

    static func publicVersion(for version: UInt32) -> UInt32 {
        switch version {
        case 0x04b2430c: return 0x04b24746      // zprv → zpub
        case 0x049d7878: return 0x049d7cb2      // yprv → ypub
        case 0x0295b005: return 0x0295b43f      // uprv → upub (SLIP-132 testnet)
        default: return 0x0488B21E              // xprv → xpub
        }
    }

    /// Derives one child. Hardened indices are >= 2^31.
    public func child(_ index: UInt32, version: UInt32? = nil) throws -> ExtendedPrivateKey {
        var data = Data()
        if index >= 0x80000000 {
            data.append(0x00)
            data.append(privateKey.data)
        } else {
            data.append(compressedPublicKey)
        }
        data.append(uint32: index)

        let digest = HMAC.authenticate(.sha512, key: chainCode, message: data)
        let left = UInt256(digest.prefix(32))
        let right = digest.suffix(32)

        guard left < Secp256k1.n else { throw BIP32Error.invalidChild }
        let childKey = Secp256k1.addModN(left, privateKey)
        guard !childKey.isZero else { throw BIP32Error.invalidChild }

        return ExtendedPrivateKey(privateKey: childKey,
                                  chainCode: Data(right),
                                  depth: depth &+ 1,
                                  parentFingerprint: fingerprint,
                                  index: index,
                                  version: version ?? self.version)
    }

    /// Derives a whole path such as m/44'/60'/0'/0/0.
    public func derive(path: String, version: UInt32? = nil) throws -> ExtendedPrivateKey {
        var key = self
        for component in try BIP32Path.components(of: path) {
            key = try key.child(component, version: version)
        }
        return key
    }

    /// master key from a BIP-39 seed
    public static func master(seed: Data, version: UInt32 = 0x0488ADE4) throws -> ExtendedPrivateKey {
        let digest = HMAC.authenticate(.sha512, key: Data("Bitcoin seed".utf8), message: seed)
        let key = UInt256(digest.prefix(32))
        guard !key.isZero, key < Secp256k1.n else { throw BIP32Error.invalidMasterKey }
        return ExtendedPrivateKey(privateKey: key,
                                  chainCode: Data(digest.suffix(32)),
                                  depth: 0,
                                  parentFingerprint: Data(repeating: 0, count: 4),
                                  index: 0,
                                  version: version)
    }
}

public enum BIP32Error: Error, Equatable {
    case invalidChild
    case invalidMasterKey
    case badPath(String)
    case unsupportedPrefix(String)
}

public enum BIP32Path {
    /// "m/44'/60'/0'/0/0" → [2147483692, 2147483708, 2147483648, 0, 0]
    public static func components(of path: String) throws -> [UInt32] {
        let text = path.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { throw BIP32Error.badPath(path) }
        if text == "m" || text == "M" { return [] }
        // Absolute paths only: a wallet must never be handed a relative path by accident.
        guard text.hasPrefix("m/") || text.hasPrefix("M/") else { throw BIP32Error.badPath(path) }
        let body = String(text.dropFirst(2))
        var out = [UInt32]()
        for raw in body.split(separator: "/", omittingEmptySubsequences: false) {
            var component = String(raw)
            var hardened = false
            if component.hasSuffix("'") || component.hasSuffix("h") || component.hasSuffix("H") {
                hardened = true
                component = String(component.dropLast())
            }
            // Catches empty components ("m/44//0"), non-numbers, and anything past 2^31 - 1.
            guard !component.isEmpty, let value = UInt32(component), value < 0x80000000 else {
                throw BIP32Error.badPath(path)
            }
            out.append(hardened ? value + 0x80000000 : value)
        }
        guard !out.isEmpty else { throw BIP32Error.badPath(path) }    // "m/" alone
        return out
    }

    public static func describe(_ components: [UInt32]) -> String {
        "m/" + components.map { $0 >= 0x80000000 ? "\($0 - 0x80000000)'" : "\($0)" }.joined(separator: "/")
    }
}

extension Data {
    mutating func append(uint32 value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }
}
