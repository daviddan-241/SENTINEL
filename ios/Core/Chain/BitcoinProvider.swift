import Foundation

/// Esplora-compatible Bitcoin indexer. mempool.space and blockstream.info run independent
/// instances of the same API, which makes them a genuine second opinion: same shapes,
/// different infrastructure.
public struct EsploraProvider: AddressProvider {
    public let name: String
    private let base: URL
    private let transport: ChainTransport

    public init?(host: String, name: String, transport: ChainTransport = URLSessionTransport()) {
        guard let url = URL(string: host) else { return nil }
        self.base = url
        self.name = name
        self.transport = transport
    }

    public func supports(_ network: Network) -> Bool { network.kind == .bitcoin }

    public func report(address: String, network: Network, limit: Int = 10) async throws -> ProviderReport {
        let statsData = try await call(path: "/api/address/\(address)")
        let stats = try EsploraDecoding.address(statsData, provider: name)

        var activity: [ChainActivity] = []
        var price: Decimal?
        if let txData = try? await call(path: "/api/address/\(address)/txs") {
            activity = (try? EsploraDecoding.transactions(txData, address: address, provider: name)) ?? []
            activity = Array(activity.prefix(limit))
        }
        if let priceData = try? await call(host: "https://mempool.space", path: "/api/v1/prices") {
            price = (try? EsploraDecoding.price(priceData)) ?? nil
        }

        let sats = stats.balance
        let amount = DecimalParsing.amount(raw: String(sats), decimals: 8)
        let native = NativeBalance(symbol: "BTC",
                                   raw: String(sats),
                                   amount: amount,
                                   decimals: 8,
                                   usdPrice: price,
                                   usdValue: price.map { $0 * amount })
        let transactions = stats.transactionCount + stats.mempoolTransactionCount
        return ProviderReport(provider: name,
                              native: native,
                              tokens: [],
                              activity: activity,
                              transactionCount: transactions,
                              neverUsed: transactions == 0 && stats.fundedCount == 0 && stats.spentCount == 0)
    }

    private func call(path: String) async throws -> Data { try await call(host: nil, path: path) }

    private func call(host: String?, path: String) async throws -> Data {
        let target = host.flatMap { URL(string: $0) } ?? base
        guard let url = URL(string: path, relativeTo: target) else {
            throw ChainError.decoding(provider: name, detail: "bad URL \(path)")
        }
        return try await withRetry {
            let (data, status) = try await transport.get(url, timeout: 20)
            switch status {
            case 200...299: return data
            case 429: throw ChainError.rateLimited(provider: name)
            case 400: throw ChainError.rejected(provider: name, detail: "not a Bitcoin address")
            case 404: throw ChainError.rejected(provider: name, detail: "address not seen yet")
            default: throw ChainError.http(status: status, provider: name)
            }
        }
    }
}

enum EsploraDecoding {
    struct AddressStats {
        var confirmedBalance: Int64
        var mempoolBalance: Int64
        var transactionCount: Int
        var mempoolTransactionCount: Int
        var fundedCount: Int
        var spentCount: Int

        var balance: Int64 { confirmedBalance + mempoolBalance }
    }

    static func address(_ data: Data, provider: String) throws -> AddressStats {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chain = object["chain_stats"] as? [String: Any] else {
            throw ChainError.decoding(provider: provider, detail: "missing chain_stats")
        }
        let mempool = object["mempool_stats"] as? [String: Any] ?? [:]

        func int(_ dictionary: [String: Any], _ key: String) -> Int64 {
            if let value = dictionary[key] as? NSNumber { return value.int64Value }
            if let value = dictionary[key] as? String { return Int64(value) ?? 0 }
            return 0
        }

        let funded = int(chain, "funded_txo_sum")
        let spent = int(chain, "spent_txo_sum")
        return AddressStats(confirmedBalance: funded - spent,
                            mempoolBalance: int(mempool, "funded_txo_sum") - int(mempool, "spent_txo_sum"),
                            transactionCount: Int(int(chain, "tx_count")),
                            mempoolTransactionCount: Int(int(mempool, "tx_count")),
                            fundedCount: Int(int(chain, "funded_txo_count")),
                            spentCount: Int(int(chain, "spent_txo_count")))
    }

    static func transactions(_ data: Data, address: String, provider: String) throws -> [ChainActivity] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ChainError.decoding(provider: provider, detail: "transactions are not a list")
        }
        return rows.compactMap { row in
            guard let txid = row["txid"] as? String else { return nil }
            let vin = row["vin"] as? [[String: Any]] ?? []
            let vout = row["vout"] as? [[String: Any]] ?? []

            var inFromAddress: Int64 = 0
            var outToAddress: Int64 = 0
            var counterparty = "unknown"
            for input in vin {
                guard let prevout = input["prevout"] as? [String: Any] else { continue }
                let owner = prevout["scriptpubkey_address"] as? String
                let value = (prevout["value"] as? NSNumber)?.int64Value ?? 0
                if owner == address { inFromAddress += value }
                else if let owner { counterparty = owner }
            }
            for output in vout {
                let owner = output["scriptpubkey_address"] as? String
                let value = (output["value"] as? NSNumber)?.int64Value ?? 0
                if owner == address { outToAddress += value }
                else if let owner, counterparty == "unknown" { counterparty = owner }
            }

            let direction: ChainActivity.Direction
            let moved: Int64
            if inFromAddress > 0 && outToAddress > 0 {
                direction = outToAddress >= inFromAddress ? .selfTransfer : .incoming
                moved = abs(outToAddress - inFromAddress)
            } else if inFromAddress > 0 {
                direction = .outgoing
                moved = inFromAddress
            } else if outToAddress > 0 {
                direction = .incoming
                moved = outToAddress
            } else {
                direction = .unknown
                moved = 0
            }

            let status = row["status"] as? [String: Any] ?? [:]
            let confirmed = (status["confirmed"] as? Bool) ?? false
            let blockTime = (status["block_time"] as? NSNumber)?.doubleValue
            return ChainActivity(id: "bitcoin:\(txid)",
                                 hash: txid,
                                 direction: direction,
                                 counterparty: counterparty,
                                 amount: DecimalParsing.amount(raw: String(abs(moved)), decimals: 8),
                                 symbol: "BTC",
                                 timestamp: blockTime.map { Date(timeIntervalSince1970: $0) },
                                 status: confirmed ? "success" : "pending",
                                 isContractCall: false,
                                 networkID: "bitcoin")
        }
    }

    static func price(_ data: Data) throws -> Decimal? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChainError.decoding(provider: "mempool.space", detail: "no price object")
        }
        if let usd = object["USD"] as? NSNumber { return Decimal(usd.doubleValue) }
        if let usd = object["USD"] as? String { return Decimal(string: usd) }
        return nil
    }
}
