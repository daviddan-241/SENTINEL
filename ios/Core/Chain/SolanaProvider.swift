import Foundation

/// Solana JSON-RPC. Two public endpoints are used as independent sources, and the same
/// provider shape as everywhere else keeps the scanner simple.
public struct SolanaRPCProvider: AddressProvider {
    public let name: String
    private let base: URL
    private let transport: ChainTransport

    public init(base: URL, name: String, transport: ChainTransport = URLSessionTransport()) {
        self.base = base
        self.name = name
        self.transport = transport
    }

    public func supports(_ network: Network) -> Bool { network.kind == .solana }

    public func report(address: String, network: Network, limit: Int = 10) async throws -> ProviderReport {
        let lamports = try await rpcValue("getBalance", params: [address]) { object in
            (((object["result"] as? [String: Any])?["value"]) as? NSNumber)?.int64Value
        }
        let signatures = (try? await rpcValue("getSignaturesForAddress",
                                              params: [address, ["limit": limit]]) { object in
            (object["result"] as? [[String: Any]])?.compactMap { entry -> (String, Date?)? in
                guard let signature = entry["signature"] as? String else { return nil }
                let blockTime = (entry["blockTime"] as? NSNumber)?.doubleValue
                return (signature, blockTime.map { Date(timeIntervalSince1970: $0) })
            }
        }) ?? []

        let amount = DecimalParsing.amount(raw: String(lamports), decimals: 9)
        let activity = signatures.enumerated().map { index, entry in
            ChainActivity(id: "solana:\(entry.0)",
                          hash: entry.0,
                          direction: .unknown,
                          counterparty: "",
                          amount: 0,
                          symbol: "SOL",
                          timestamp: entry.1,
                          status: index == 0 ? "latest" : "success",
                          isContractCall: false,
                          networkID: "solana")
        }
        let native = NativeBalance(symbol: "SOL", raw: String(lamports), amount: amount, decimals: 9)
        return ProviderReport(provider: name,
                              native: native,
                              tokens: [],                       // SPL holdings need a token program scan; not claimed here
                              activity: activity,
                              transactionCount: signatures.count,
                              neverUsed: lamports == 0 && signatures.isEmpty)
    }

    private func rpcValue<T>(_ method: String, params: [Any],
                             extract: @escaping ([String: Any]) -> T?) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1,
                                                               "method": method, "params": params])
        return try await withRetry {
            let (data, status) = try await transport.post(base, body: body, timeout: 20)
            guard (200...299).contains(status) else {
                if status == 429 { throw ChainError.rateLimited(provider: name) }
                throw ChainError.http(status: status, provider: name)
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ChainError.decoding(provider: name, detail: "not JSON")
            }
            if let error = object["error"] as? [String: Any] {
                throw ChainError.rejected(provider: name, detail: (error["message"] as? String) ?? "rpc error")
            }
            guard let value = extract(object) else {
                throw ChainError.decoding(provider: name, detail: "missing \(method) result")
            }
            return value
        }
    }
}

/// Kraken's public ticker: the price source for coins whose explorer publishes no USD rate
/// (Solana), and an independent cross-check for the ones that do.
public struct KrakenPriceSource: PriceSource {
    public let name = "Kraken"
    private let transport: ChainTransport
    private static let pairs = ["SOL": "SOLUSD", "BTC": "XBTUSD", "ETH": "ETHUSD",
                                "POL": "POLUSD", "XDAI": "DAIUSD"]

    public init(transport: ChainTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func prices(symbols: [String]) async throws -> [String: Decimal] {
        var out: [String: Decimal] = [:]
        for symbol in Set(symbols) {
            guard let pair = Self.pairs[symbol.uppercased()] else { continue }
            guard let url = URL(string: "https://api.kraken.com/0/public/Ticker?pair=\(pair)") else { continue }
            let (data, status) = try await transport.get(url, timeout: 15)
            guard (200...299).contains(status) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = object["result"] as? [String: Any] else { continue }
            for (_, value) in result {
                guard let entry = value as? [String: Any],
                      let close = entry["c"] as? [String], let last = close.first,
                      let price = Decimal(string: last) else { continue }
                out[symbol.uppercased()] = price
            }
        }
        return out
    }
}
