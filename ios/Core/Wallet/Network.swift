import Foundation

/// A chain the app can actually read. Only networks whose public endpoints were verified
/// to answer without an API key are listed here — see docs/networks.md.
public struct Network: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case evm, bitcoin, solana
    }

    public enum Scheme: String, Sendable {
        case bip44          // m/44'/coin'/0'/0/0
        case bip49          // m/49'/coin'/0'/0/0
        case bip84          // m/84'/coin'/0'/0/0
        case bip86          // m/86'/coin'/0'/0/0
        case solanaAccount  // m/44'/501'/0'/0'

        public var purpose: UInt32 {
            switch self {
            case .bip44: return 44
            case .bip49: return 49
            case .bip84: return 84
            case .bip86: return 86
            case .solanaAccount: return 44
            }
        }

        public var shortLabel: String {
            switch self {
            case .bip44: return "legacy"
            case .bip49: return "wrapped segwit"
            case .bip84: return "native segwit"
            case .bip86: return "taproot"
            case .solanaAccount: return "ed25519"
            }
        }
    }

    public let id: String                 // "ethereum"
    public let name: String               // "Ethereum"
    public let symbol: String             // "ETH"
    public let kind: Kind
    public let coinType: UInt32
    public let scheme: Scheme
    public let colorHex: String
    /// Blockscout v2 API base — the primary provider for EVM chains.
    public let explorerAPI: URL?
    /// A second, independent endpoint: JSON-RPC for EVM, Esplora for Bitcoin, Solana RPC.
    public let rpcAPI: URL?
    public let explorerAddressURL: @Sendable (String) -> String

    public init(id: String,
                name: String,
                symbol: String,
                kind: Kind,
                coinType: UInt32,
                scheme: Scheme,
                colorHex: String,
                explorerAPI: URL? = nil,
                rpcAPI: URL? = nil,
                explorerAddressURL: @escaping @Sendable (String) -> String) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.kind = kind
        self.coinType = coinType
        self.scheme = scheme
        self.colorHex = colorHex
        self.explorerAPI = explorerAPI
        self.rpcAPI = rpcAPI
        self.explorerAddressURL = explorerAddressURL
    }

    public static func == (a: Network, b: Network) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public var derivationPath: String {
        switch scheme {
        case .solanaAccount: return "m/44'/\(coinType)'/0'/0'"
        default: return "m/\(scheme.purpose)'/\(coinType)'/0'/0/0"
        }
    }
}

public enum Networks {
    // EVM chains share the m/44'/60' account: that is the convention every major wallet uses,
    // so the same address exists on all of them.
    public static let ethereum = Network(
        id: "ethereum", name: "Ethereum", symbol: "ETH", kind: .evm, coinType: 60, scheme: .bip44,
        colorHex: "#627EEA", explorerAPI: URL(string: "https://eth.blockscout.com"),
        rpcAPI: URL(string: "https://ethereum-rpc.publicnode.com"),
        explorerAddressURL: { "https://eth.blockscout.com/address/\($0)" })

    public static let base = Network(
        id: "base", name: "Base", symbol: "ETH", kind: .evm, coinType: 60, scheme: .bip44,
        colorHex: "#0052FF", explorerAPI: URL(string: "https://base.blockscout.com"),
        rpcAPI: URL(string: "https://base-rpc.publicnode.com"),
        explorerAddressURL: { "https://base.blockscout.com/address/\($0)" })

    public static let arbitrum = Network(
        id: "arbitrum", name: "Arbitrum One", symbol: "ETH", kind: .evm, coinType: 60, scheme: .bip44,
        colorHex: "#12AAFF", explorerAPI: URL(string: "https://arbitrum.blockscout.com"),
        rpcAPI: URL(string: "https://arbitrum-one-rpc.publicnode.com"),
        explorerAddressURL: { "https://arbitrum.blockscout.com/address/\($0)" })

    public static let optimism = Network(
        id: "optimism", name: "OP Mainnet", symbol: "ETH", kind: .evm, coinType: 60, scheme: .bip44,
        colorHex: "#FF0420", explorerAPI: URL(string: "https://explorer.optimism.io"),
        rpcAPI: URL(string: "https://optimism-rpc.publicnode.com"),
        explorerAddressURL: { "https://explorer.optimism.io/address/\($0)" })

    public static let polygon = Network(
        id: "polygon", name: "Polygon", symbol: "POL", kind: .evm, coinType: 60, scheme: .bip44,
        colorHex: "#8247E5", explorerAPI: URL(string: "https://polygon.blockscout.com"),
        rpcAPI: URL(string: "https://polygon-bor-rpc.publicnode.com"),
        explorerAddressURL: { "https://polygon.blockscout.com/address/\($0)" })

    public static let gnosis = Network(
        id: "gnosis", name: "Gnosis", symbol: "xDAI", kind: .evm, coinType: 60, scheme: .bip44,
        colorHex: "#04795B", explorerAPI: URL(string: "https://gnosisscan.io"),
        rpcAPI: URL(string: "https://gnosis-rpc.publicnode.com"),
        explorerAddressURL: { "https://gnosisscan.io/address/\($0)" })

    public static let bitcoin = Network(
        id: "bitcoin", name: "Bitcoin", symbol: "BTC", kind: .bitcoin, coinType: 0, scheme: .bip84,
        colorHex: "#F7931A",
        explorerAPI: URL(string: "https://mempool.space"),
        rpcAPI: URL(string: "https://blockstream.info"),
        explorerAddressURL: { "https://mempool.space/address/\($0)" })

    public static let solana = Network(
        id: "solana", name: "Solana", symbol: "SOL", kind: .solana, coinType: 501, scheme: .solanaAccount,
        colorHex: "#14F195",
        explorerAPI: URL(string: "https://api.mainnet-beta.solana.com"),
        rpcAPI: URL(string: "https://solana-rpc.publicnode.com"),
        explorerAddressURL: { "https://solscan.io/account/\($0)" })

    /// Every network the app will scan for an imported key.
    public static let evmChains: [Network] = [ethereum, base, arbitrum, optimism, polygon, gnosis]
    public static let all: [Network] = evmChains + [bitcoin, solana]

    public static func network(id: String) -> Network? { all.first { $0.id == id } }
}
