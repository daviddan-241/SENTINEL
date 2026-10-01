import Foundation

/// A credential the owner typed or pasted in. Never leaves the device.
public enum Credential: Sendable {
    case mnemonic(phrase: String, passphrase: String)
    case privateKey(Data)                 // 32 raw bytes
    case wif(String, mainnet: Bool)

    public var kindLabel: String {
        switch self {
        case .mnemonic(let phrase, _):
            let count = BIP39.normalise(phrase).count
            return "\(count)-word recovery phrase"
        case .privateKey: return "256-bit private key"
        case .wif: return "WIF private key"
        }
    }
}

/// One address derived from a credential, plus the provenance needed to explain it in the UI.
public struct DerivedAccount: Sendable, Identifiable {
    public let id: String                 // network id + address, unique
    public let network: Network
    public let path: String
    public let address: String
    public let schemeLabel: String
    public let isPrimary: Bool            // the address the UI shows for that network

    public init(network: Network, path: String, address: String, schemeLabel: String, isPrimary: Bool) {
        self.id = "\(network.id):\(address)"
        self.network = network
        self.path = path
        self.address = address
        self.schemeLabel = schemeLabel
        self.isPrimary = isPrimary
    }
}

public enum DerivationError: Error, Equatable {
    case invalidMnemonic(BIP39.ValidationResult)
    case invalidPrivateKey
    case unsupportedNetwork(String)

    public var message: String {
        switch self {
        case .invalidMnemonic(let result): return result.explanation
        case .invalidPrivateKey: return "That does not look like a 32-byte private key or a valid WIF."
        case .unsupportedNetwork(let id): return "\(id) is not a supported network."
        }
    }
}

/// Turns a credential into the addresses the app will scan.
public enum Derivation {
    /// All Bitcoin address styles derived from the same seed (BIP-44/49/84/86).
    public static let bitcoinSchemes: [Network.Scheme] = [.bip84, .bip44, .bip49, .bip86]

    public static func accounts(for credential: Credential,
                                evmChains: [Network] = Networks.evmChains,
                                includeSolana: Bool = true) throws -> [DerivedAccount] {
        var derived: [DerivedAccount] = []

        switch credential {
        case .mnemonic(let phrase, let passphrase):
            let result = BIP39.validate(phrase)
            guard result.isValid else { throw DerivationError.invalidMnemonic(result) }
            let seed = BIP39.seed(phrase: phrase, passphrase: passphrase)
            let master = try ExtendedPrivateKey.master(seed: seed)

            for chain in evmChains {
                let key = try master.derive(path: chain.derivationPath)
                let address = Address.ethereum(from: key.publicKey)
                derived.append(DerivedAccount(network: chain, path: chain.derivationPath,
                                              address: address, schemeLabel: "BIP-44",
                                              isPrimary: chain.id == "ethereum"))
            }

            for scheme in bitcoinSchemes {
                let path = "m/\(scheme.purpose)'/0'/0'/0/0"
                guard let version = versionPrefix(for: scheme) else { continue }
                let key = try master.derive(path: path, version: version)
                let address: String
                switch scheme {
                case .bip44: address = Address.p2pkh(from: key.publicKey)
                case .bip49: address = Address.p2shP2wpkh(from: key.publicKey)
                case .bip84: address = Address.p2wpkh(from: key.publicKey)
                case .bip86: address = Address.p2tr(from: key.publicKey)
                default: continue
                }
                derived.append(DerivedAccount(network: Networks.bitcoin, path: path, address: address,
                                              schemeLabel: scheme.shortLabel, isPrimary: scheme == .bip84))
            }

            if includeSolana {
                let path = "m/44'/501'/0'/0'"
                let key = try master.derive(path: path)
                if let address = Address.solana(fromSeed: key.privateKey.data) {
                    derived.append(DerivedAccount(network: Networks.solana, path: path, address: address,
                                                  schemeLabel: "ed25519", isPrimary: true))
                }
            }

        case .privateKey(let data):
            guard let parsed = PrivateKeyImport.parse(data.hexString) else {
                throw DerivationError.invalidPrivateKey
            }
            derived += rawKeyAccounts(scalar: parsed.key, evmChains: evmChains)

        case .wif(let string, _):
            guard let parsed = PrivateKeyImport.parseWIF(string) else {
                throw DerivationError.invalidPrivateKey
            }
            derived += rawKeyAccounts(scalar: parsed.key, evmChains: evmChains)
        }

        return derived
    }

    /// A single secp256k1 key has no HD tree: it maps to one EVM address and one Bitcoin
    /// legacy address — exactly what wallets show for an imported raw key.
    static func rawKeyAccounts(scalar: UInt256, evmChains: [Network]) -> [DerivedAccount] {
        guard !scalar.isZero, scalar < Secp256k1.n,
              let point = Secp256k1.multiplyGenerator(scalar) else { return [] }
        var accounts = evmChains.map {
            DerivedAccount(network: $0, path: "raw key", address: Address.ethereum(from: point),
                           schemeLabel: "raw key", isPrimary: $0.id == "ethereum")
        }
        accounts.append(DerivedAccount(network: Networks.bitcoin, path: "raw key",
                                       address: Address.p2pkh(from: point),
                                       schemeLabel: "legacy", isPrimary: true))
        return accounts
    }

    static func credentialString(_ credential: Credential) -> String {
        switch credential {
        case .wif(let string, _): return string
        case .mnemonic(let phrase, _): return phrase
        case .privateKey(let data): return data.hexString
        }
    }

    static func versionPrefix(for scheme: Network.Scheme) -> UInt32? {
        switch scheme {
        case .bip44: return 0x0488ADE4      // xprv
        case .bip49: return 0x049D7878      // yprv
        case .bip84: return 0x04B2430C      // zprv
        case .bip86: return 0x0488ADE4      // xprv (taproot accounts use plain xprv)
        default: return nil
        }
    }

    /// The single address the UI shows for a network.
    public static func primaryAddress(of accounts: [DerivedAccount], network: Network) -> String? {
        accounts.first { $0.network.id == network.id && $0.isPrimary }?.address
            ?? accounts.first { $0.network.id == network.id }?.address
    }
}

/// Private key import: raw hex and WIF.
public enum PrivateKeyImport {
    public struct Parsed {
        public let key: UInt256
        public let compressed: Bool
        public let mainnet: Bool
    }

    public static func parse(_ string: String) -> Parsed? {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = Hex.bytes(text, expectingBytes: 32) {
            let scalar = UInt256(data)
            guard !scalar.isZero, scalar < Secp256k1.n else { return nil }
            return Parsed(key: scalar, compressed: true, mainnet: true)
        }
        return parseWIF(text)
    }

    /// Wallet Import Format: base58check payload of 0x80 | key [| 0x01]
    public static func parseWIF(_ string: String) -> Parsed? {
        guard let decoded = Base58.decodeCheck(string.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let mainnet: Bool
        switch decoded.first {
        case 0x80: mainnet = true
        case 0xef: mainnet = false
        default: return nil
        }
        let body = decoded.dropFirst()
        let compressed: Bool
        let keyBytes: Data
        if body.count == 32 {
            compressed = false
            keyBytes = Data(body)
        } else if body.count == 33, body.last == 0x01 {
            compressed = true
            keyBytes = Data(body.dropLast())
        } else {
            return nil
        }
        let scalar = UInt256(keyBytes)
        guard !scalar.isZero, scalar < Secp256k1.n else { return nil }
        return Parsed(key: scalar, compressed: compressed, mainnet: mainnet)
    }
}
