import Foundation

/// Address encoders for the chains the app supports. Every function here is checked
/// against published test vectors in the test suite.
public enum Address {
    /// EIP-55 checksummed lowercase-hex address.
    public static func ethereum(from publicKey: Secp256k1.Point) -> String {
        let uncompressed = Secp256k1.uncompressed(publicKey)      // 0x04 || X || Y
        let hash = Keccak256.hash(Data(uncompressed.dropFirst()))
        let raw = hash.suffix(20).hexString
        return "0x" + checksum(raw)
    }

    static func checksum(_ lowercaseHex: String) -> String {
        let hash = Keccak256.hash(Data(lowercaseHex.utf8)).hexString
        var out = ""
        for (i, character) in lowercaseHex.enumerated() {
            guard character.isLetter else { out.append(character); continue }
            let nibble = hash[hash.index(hash.startIndex, offsetBy: i)]
            let value = Int(String(nibble), radix: 16) ?? 0
            out.append(value >= 8 ? Character(character.uppercased()) : character)
        }
        return out
    }

    /// P2PKH — 1…
    public static func p2pkh(from publicKey: Secp256k1.Point, mainnet: Bool = true) -> String {
        Base58.encodeCheck(Data([mainnet ? 0x00 : 0x6f]) + hash160(Secp256k1.compressed(publicKey)))
    }

    /// P2SH-P2WPKH — 3… (BIP-49)
    public static func p2shP2wpkh(from publicKey: Secp256k1.Point, mainnet: Bool = true) -> String {
        let redeemScript = Data([0x00, 0x14]) + hash160(Secp256k1.compressed(publicKey))
        return Base58.encodeCheck(Data([mainnet ? 0x05 : 0xc4]) + hash160(redeemScript))
    }

    /// P2WPKH — bc1q… (BIP-84)
    public static func p2wpkh(from publicKey: Secp256k1.Point, mainnet: Bool = true) -> String {
        Bech32.encodeSegwit(hrp: mainnet ? "bc" : "tb", version: 0, program: hash160(Secp256k1.compressed(publicKey)))
    }

    /// P2TR — bc1p… (BIP-86)
    public static func p2tr(from publicKey: Secp256k1.Point, mainnet: Bool = true) -> String {
        guard let output = Secp256k1.taprootOutputKey(internalKey: publicKey) else { return "" }
        return Bech32.encodeSegwit(hrp: mainnet ? "bc" : "tb", version: 1, program: Secp256k1.xonly(output))
    }

    /// Solana — base58 of the 32-byte ed25519 public key.
    public static func solana(fromSeed seed: Data) -> String? {
        guard let key = Ed25519.publicKey(fromSeed: seed) else { return nil }
        return Base58.encode(key)
    }

    public static func hash160(_ data: Data) -> Data {
        RIPEMD160.hash(SHA256.hash(data))
    }

    /// True when the string looks like an address the app can look up.
    public static func classify(_ string: String) -> AddressKind? {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.lowercased().hasPrefix("0x"), text.count == 42, Hex.bytes(text, expectingBytes: 20) != nil {
            return .evm
        }
        if let decoded = Base58.decodeCheck(text) {
            if decoded.count == 21 {
                switch decoded.first {
                case 0x00, 0x6f: return .bitcoinP2PKH
                case 0x05, 0xc4: return .bitcoinP2SH
                default: break
                }
            }
            if decoded.count == 34 { return .solana }        // raw ed25519 key, no checksum
            if decoded.count == 33 || decoded.count == 32 { return .solana }
        }
        if let segwit = Bech32.decodeSegwit(text), ["bc", "tb"].contains(segwit.hrp) {
            switch segwit.version {
            case 0: return .bitcoinSegwit
            case 1: return .bitcoinTaproot
            default: return .bitcoinSegwit
            }
        }
        if Base58.decode(text)?.count == 32 { return .solana }
        return nil
    }

    public enum AddressKind: String, Sendable {
        case evm, bitcoinP2PKH, bitcoinP2SH, bitcoinSegwit, bitcoinTaproot, solana

        public var label: String {
            switch self {
            case .evm: return "EVM address"
            case .bitcoinP2PKH: return "Bitcoin legacy"
            case .bitcoinP2SH: return "Bitcoin wrapped segwit"
            case .bitcoinSegwit: return "Bitcoin native segwit"
            case .bitcoinTaproot: return "Bitcoin taproot"
            case .solana: return "Solana account"
            }
        }
    }

    /// "bc1qgdjqv0av3q56jvd82tkdjpy7gdp9ut8tlqmgrpmv24sq90ecnvqqjwvw97" → "bc1qgdj…vw97"
    public static func shorten(_ address: String, leading: Int = 7, trailing: Int = 5) -> String {
        guard address.count > leading + trailing + 1 else { return address }
        return address.prefix(leading) + "…" + address.suffix(trailing)
    }
}
