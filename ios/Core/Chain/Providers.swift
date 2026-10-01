import Foundation

/// The provider set the app ships with: two independent sources for every chain family.
///
///   EVM       Blockscout (explorer, full detail)          + publicnode JSON-RPC (native coin)
///   Bitcoin   mempool.space (Esplora)                     + blockstream.info (Esplora)
///   Solana    api.mainnet-beta.solana.com                 + publicnode Solana RPC
///   prices    the explorer's own USD rate where it exists + Kraken ticker as a cross-check
public struct ProviderRegistry: Sendable {
    public var providers: [AddressProvider]
    public var priceSource: PriceSource?

    public init(providers: [AddressProvider], priceSource: PriceSource? = nil) {
        self.providers = providers
        self.priceSource = priceSource
    }

    public func providers(for network: Network) -> [AddressProvider] {
        providers.filter { $0.supports(network) }
    }

    public static func live(transport: ChainTransport = URLSessionTransport()) -> ProviderRegistry {
        var providers: [AddressProvider] = []
        for network in Networks.evmChains {
            if let explorer = BlockscoutProvider(network: network, transport: transport) {
                providers.append(explorer)
            }
            if let node = EVMJSONRPCProvider(network: network, transport: transport) {
                providers.append(node)
            }
        }
        if let mempool = EsploraProvider(host: "https://mempool.space", name: "mempool.space",
                                         transport: transport) {
            providers.append(mempool)
        }
        if let blockstream = EsploraProvider(host: "https://blockstream.info", name: "blockstream.info",
                                             transport: transport) {
            providers.append(blockstream)
        }
        if let mainnet = Networks.solana.explorerAPI {
            providers.append(SolanaRPCProvider(base: mainnet, name: "Solana mainnet-beta",
                                               transport: transport))
        }
        if let publicnode = Networks.solana.rpcAPI {
            providers.append(SolanaRPCProvider(base: publicnode, name: "Solana (publicnode)",
                                               transport: transport))
        }
        return ProviderRegistry(providers: providers, priceSource: KrakenPriceSource(transport: transport))
    }
}
