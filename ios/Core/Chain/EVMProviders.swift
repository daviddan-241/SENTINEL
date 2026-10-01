import Foundation

/// Blockscout v2 REST — the full picture for an EVM address: native balance, ERC-20/721/1155
/// holdings, recent transactions, and the chain's own USD rate for its coin.
public struct BlockscoutProvider: AddressProvider {
    public let name: String
    private let base: URL
    private let networkID: String
    private let transport: ChainTransport

    public init?(network: Network, transport: ChainTransport = URLSessionTransport()) {
        guard let base = network.explorerAPI else { return nil }
        self.base = base
        self.networkID = network.id
        self.name = "\(network.name) Blockscout"
        self.transport = transport
    }

    public func supports(_ network: Network) -> Bool { network.id == networkID }

    public func report(address: String, network: Network, limit: Int = 10) async throws -> ProviderReport {
        let addressData = try await call(path: "/api/v2/addresses/\(address)")
        let summary = try BlockscoutDecoding.address(addressData, provider: name)
        let price = summary.exchangeRate

        async let countersData = try? call(path: "/api/v2/addresses/\(address)/counters")
        async let tokensData = try? call(path: "/api/v2/addresses/\(address)/token-balances")
        async let activityData = try? call(path: "/api/v2/addresses/\(address)/transactions?filter=to")

        let counters = (await countersData).flatMap { try? BlockscoutDecoding.counters($0) }
        let tokens = (await tokensData).flatMap { data in
            (try? BlockscoutDecoding.tokenBalances(data, provider: name)) ?? []
        } ?? []
        let activity = (await activityData).flatMap { data in
            (try? BlockscoutDecoding.transactions(data, address: address, networkID: networkID,
                                                  symbol: network.symbol, decimals: 18, provider: name)) ?? []
        } ?? []

        let native = NativeBalance(symbol: network.symbol,
                                   raw: summary.wei,
                                   amount: DecimalParsing.amount(raw: summary.wei, decimals: 18),
                                   decimals: 18,
                                   usdPrice: price,
                                   usdValue: price.map { $0 * DecimalParsing.amount(raw: summary.wei, decimals: 18) },
                                   blockNumber: summary.blockNumber)
        let transactionCount = counters?.transactions
        let neverUsed = (transactionCount ?? 0) == 0 && !summary.hasTokens && !summary.hasTokenTransfers
            && !summary.hasLogs && activity.isEmpty
        return ProviderReport(provider: name,
                              native: native,
                              tokens: tokens,
                              activity: activity,
                              transactionCount: transactionCount,
                              neverUsed: neverUsed)
    }

    private func call(path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: base) else {
            throw ChainError.decoding(provider: name, detail: "bad URL \(path)")
        }
        return try await withRetry {
            let (data, status) = try await transport.get(url, timeout: 20)
            switch status {
            case 200...299: return data
            case 429: throw ChainError.rateLimited(provider: name)
            case 404: throw ChainError.rejected(provider: name, detail: "no such address")
            default: throw ChainError.http(status: status, provider: name)
            }
        }
    }
}

/// Independent JSON-RPC: `eth_getBalance` and `eth_getTransactionCount` straight from a node.
/// Only the native coin is covered — its job is to disagree with the explorer when the
/// explorer is wrong.
public struct EVMJSONRPCProvider: AddressProvider {
    public let name: String
    private let base: URL
    private let networkID: String
    private let networkName: String
    private let symbol: String
    private let transport: ChainTransport

    public init?(network: Network, transport: ChainTransport = URLSessionTransport()) {
        guard let base = network.rpcAPI else { return nil }
        self.base = base
        self.networkID = network.id
        self.networkName = network.name
        self.symbol = network.symbol
        self.name = "\(network.name) node"
        self.transport = transport
    }

    public func supports(_ network: Network) -> Bool { network.id == networkID }

    public func report(address: String, network: Network, limit: Int = 1) async throws -> ProviderReport {
        async let balanceHex = rpc("eth_getBalance", params: [address, "latest"])
        async let nonceHex = rpc("eth_getTransactionCount", params: [address, "latest"])
        let (balance, nonce) = try await (balanceHex, nonceHex)
        let wei = HexDecimal.wei(fromHex: balance) ?? "0"
        let transactions = HexDecimal.int(fromHex: nonce) ?? 0
        let native = NativeBalance(symbol: symbol,
                                   raw: wei,
                                   amount: DecimalParsing.amount(raw: wei, decimals: 18),
                                   decimals: 18)
        return ProviderReport(provider: name, native: native, tokens: [], activity: [],
                              transactionCount: transactions, neverUsed: transactions == 0)
    }

    private func rpc(_ method: String, params: [Any]) async throws -> String {
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
            guard let result = object["result"] as? String else {
                throw ChainError.decoding(provider: name, detail: "no result")
            }
            return result
        }
    }
}

/// Hex quantities from JSON-RPC ("0x1bc16d674ec80000") → decimal strings, without a Double.
public enum HexDecimal {
    public static func wei(fromHex hex: String) -> String? {
        let trimmed = hex.hasPrefix("0x") || hex.hasPrefix("0X") ? String(hex.dropFirst(2)) : hex
        return decimalString(fromHex: trimmed)
    }

    public static func int(fromHex hex: String) -> Int? {
        guard let text = wei(fromHex: hex) else { return nil }
        return Int(text)
    }

    static func decimalString(fromHex hex: String) -> String? {
        guard !hex.isEmpty, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        var digits: [UInt8] = [0]                        // little-endian base-10 accumulator
        for character in hex {
            guard let value = UInt8(String(character), radix: 16) else { return nil }
            var carry = Int(value)
            for index in digits.indices {
                let current = Int(digits[index]) * 16 + carry
                digits[index] = UInt8(current % 10)
                carry = current / 10
            }
            while carry > 0 {
                digits.append(UInt8(carry % 10))
                carry /= 10
            }
        }
        let text = String(digits.reversed().map { Character(UnicodeScalar($0 + 48)) })
        let trimmed = text.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }
}

// MARK: - decoding

/// Tolerant decoding of Blockscout's payloads: every number arrives as a string, and most
/// optional fields are null for some addresses.
enum BlockscoutDecoding {
    struct AddressSummary {
        var wei: String
        var exchangeRate: Decimal?
        var blockNumber: UInt64?
        var hasTokens: Bool
        var hasTokenTransfers: Bool
        var hasLogs: Bool
    }

    static func address(_ data: Data, provider: String) throws -> AddressSummary {
        let object = try object(data, provider: provider)
        guard let wei = object["coin_balance"] as? String else {
            throw ChainError.decoding(provider: provider, detail: "missing coin_balance")
        }
        return AddressSummary(wei: wei,
                              exchangeRate: DecimalParsing.decimal(object["exchange_rate"] as? String),
                              blockNumber: DecimalParsing.uint64((object["block_number_balance_updated_at"] as? NSNumber)?.stringValue
                                                                  ?? object["block_number_balance_updated_at"] as? String),
                              hasTokens: object["has_tokens"] as? Bool ?? false,
                              hasTokenTransfers: object["has_token_transfers"] as? Bool ?? false,
                              hasLogs: object["has_logs"] as? Bool ?? false)
    }

    static func counters(_ data: Data) throws -> (transactions: Int, tokenTransfers: Int) {
        let object = try object(data, provider: "counters")
        return (Int(object["transactions_count"] as? String ?? "0") ?? 0,
                Int(object["token_transfers_count"] as? String ?? "0") ?? 0)
    }

    static func tokenBalances(_ data: Data, provider: String) throws -> [TokenHolding] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ChainError.decoding(provider: provider, detail: "token balances are not a list")
        }
        return rows.compactMap { row in
            guard let token = row["token"] as? [String: Any],
                  let contract = token["address_hash"] as? String,
                  let raw = row["value"] as? String else { return nil }
            let decimals = Int(token["decimals"] as? String ?? "0") ?? 0
            let symbol = (token["symbol"] as? String) ?? "?"
            let standard = (token["type"] as? String) ?? "ERC-20"
            let rate = DecimalParsing.decimal(token["exchange_rate"] as? String)
            let amount = DecimalParsing.amount(raw: raw, decimals: decimals)
            let isFungible = standard == "ERC-20"
            return TokenHolding(contract: contract,
                                symbol: symbol,
                                name: (token["name"] as? String) ?? symbol,
                                decimals: decimals,
                                rawValue: raw,
                                amount: amount,
                                exchangeRate: rate,
                                usdValue: (rate != nil && isFungible) ? rate! * amount : nil,
                                standard: standard,
                                tokenID: row["token_id"] as? String,
                                iconURL: token["icon_url"] as? String,
                                reputation: token["reputation"] as? String)
        }
    }

    static func transactions(_ data: Data, address: String, networkID: String, symbol: String,
                             decimals: Int, provider: String) throws -> [ChainActivity] {
        let root = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]
        if let object = root as? [String: Any], let items = object["items"] as? [[String: Any]] {
            rows = items
        } else if let items = root as? [[String: Any]] {
            rows = items
        } else {
            throw ChainError.decoding(provider: provider, detail: "transactions are not a list")
        }
        return rows.compactMap { row in
            guard let hash = row["hash"] as? String else { return nil }
            let from = (row["from"] as? [String: Any])?["hash"] as? String
            let to = (row["to"] as? [String: Any])?["hash"] as? String
            let outgoing = from?.lowercased() == address.lowercased()
            let counterparty = outgoing ? (to ?? "contract creation") : (from ?? "unknown")
            let direction: ChainActivity.Direction
            if from?.lowercased() == to?.lowercased() { direction = .selfTransfer }
            else { direction = outgoing ? .outgoing : .incoming }
            let value = DecimalParsing.amount(raw: row["value"] as? String ?? "0", decimals: decimals)
            let status = (row["status"] as? String) ?? (row["result"] as? String) ?? "pending"
            return ChainActivity(id: "\(networkID):\(hash)",
                                 hash: hash,
                                 direction: direction,
                                 counterparty: counterparty,
                                 amount: value,
                                 symbol: symbol,
                                 timestamp: ISO8601.date(row["timestamp"] as? String),
                                 status: status == "ok" ? "success" : status,
                                 isContractCall: ((row["to"] as? [String: Any])?["is_contract"] as? Bool ?? false)
                                    || (row["method"] as? String) != nil,
                                 networkID: networkID)
        }
    }

    static func stats(_ data: Data) throws -> (coinPrice: Decimal?, change: Decimal?) {
        let object = try object(data, provider: "stats")
        return (DecimalParsing.decimal(object["coin_price"] as? String),
                DecimalParsing.decimal(object["coin_price_change_percentage"] as? String))
    }

    private static func object(_ data: Data, provider: String) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChainError.decoding(provider: provider, detail: "not a JSON object")
        }
        return object
    }
}

public enum ISO8601 {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return formatter.date(from: string) ?? plain.date(from: string)
    }
}
