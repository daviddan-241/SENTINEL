import Foundation

// MARK: - what a single address looks like

/// A non-native asset: ERC-20/721/1155 on EVM chains, SPL tokens on Solana.
public struct TokenHolding: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(contract):\(tokenID ?? "")" }
    public var contract: String
    public var symbol: String
    public var name: String
    public var decimals: Int
    /// Base units exactly as the chain reported them (a decimal string; never a Double).
    public var rawValue: String
    /// Human amount, i.e. rawValue / 10^decimals.
    public var amount: Decimal
    /// USD per whole token, when the explorer publishes a rate.
    public var exchangeRate: Decimal?
    public var usdValue: Decimal?
    public var standard: String            // "ERC-20", "ERC-721", …
    public var tokenID: String?            // NFT ids
    public var iconURL: String?
    /// What the explorer says about it: "ok", "spam", …
    public var reputation: String?
    /// Junk-token flag, from `SpamFilter`. Flagged tokens are never counted in a total.
    public var isFlagged: Bool = false
    /// Why it was flagged, for the UI.
    public var flaggedReason: String?

    public init(contract: String, symbol: String, name: String, decimals: Int, rawValue: String,
                amount: Decimal, exchangeRate: Decimal? = nil, usdValue: Decimal? = nil,
                standard: String, tokenID: String? = nil, iconURL: String? = nil,
                reputation: String? = nil) {
        self.contract = contract
        self.symbol = symbol
        self.name = name
        self.decimals = decimals
        self.rawValue = rawValue
        self.amount = amount
        self.exchangeRate = exchangeRate
        self.usdValue = usdValue
        self.standard = standard
        self.tokenID = tokenID
        self.iconURL = iconURL
        self.reputation = reputation
        self.isFlagged = SpamFilter.isFlagged(name: name, symbol: symbol, reputation: reputation)
        self.flaggedReason = isFlagged ? SpamFilter.reason(name: name, symbol: symbol, reputation: reputation) : nil
    }
}

/// The chain's own coin: wei, satoshi, lamports.
public struct NativeBalance: Codable, Equatable, Sendable {
    public var symbol: String
    public var raw: String                 // base units, decimal string
    public var amount: Decimal             // whole coins
    public var decimals: Int
    public var usdPrice: Decimal?
    public var usdValue: Decimal?
    /// The block the explorer reported the balance at, when it says.
    public var blockNumber: UInt64?

    public init(symbol: String, raw: String, amount: Decimal, decimals: Int,
                usdPrice: Decimal? = nil, usdValue: Decimal? = nil, blockNumber: UInt64? = nil) {
        self.symbol = symbol
        self.raw = raw
        self.amount = amount
        self.decimals = decimals
        self.usdPrice = usdPrice
        self.usdValue = usdValue
        self.blockNumber = blockNumber
    }

    public var isZero: Bool { amount == 0 }
}

public struct ChainActivity: Codable, Equatable, Sendable, Identifiable {
    public enum Direction: String, Codable, Sendable { case incoming, outgoing, selfTransfer, unknown }

    public var id: String
    public var hash: String
    public var direction: Direction
    public var counterparty: String
    public var amount: Decimal
    public var symbol: String
    public var timestamp: Date?
    public var status: String              // "success" / "failed" / "pending"
    public var isContractCall: Bool
    public var networkID: String

    public init(id: String, hash: String, direction: Direction, counterparty: String, amount: Decimal,
                symbol: String, timestamp: Date?, status: String, isContractCall: Bool, networkID: String) {
        self.id = id
        self.hash = hash
        self.direction = direction
        self.counterparty = counterparty
        self.amount = amount
        self.symbol = symbol
        self.timestamp = timestamp
        self.status = status
        self.isContractCall = isContractCall
        self.networkID = networkID
    }
}

// MARK: - how sure the app is

/// Where a number came from, and whether a second provider backed it up.
public enum Verification: String, Codable, Sendable {
    case agreed          // two independent providers returned the same balance
    case singleSource    // only one provider could answer; shown as unconfirmed
    case disagreed       // providers differ — the UI must not total this up
    case unavailable     // nothing answered

    public var label: String {
        switch self {
        case .agreed: return "Confirmed by two providers"
        case .singleSource: return "Single source"
        case .disagreed: return "Verification required"
        case .unavailable: return "No provider reachable"
        }
    }
}

public enum ScanState: String, Codable, Sendable, CaseIterable {
    case funded        // holds something right now
    case active        // nothing right now, but the address has history
    case empty         // the chain answered, everything is zero, no history
    case unused        // the chain says this address has never been used
    case invalid       // could not be derived, or the chain rejected the address
    case verifying     // providers disagree — do not total this up
    case unavailable   // no provider answered; absence of data is not absence of funds

    public var title: String {
        switch self {
        case .funded: return "Funded"
        case .active: return "Previously used"
        case .empty: return "No funds"
        case .unused: return "Never used"
        case .invalid: return "Invalid"
        case .verifying: return "Verification required"
        case .unavailable: return "Could not check"
        }
    }

    public var detail: String {
        switch self {
        case .funded: return "This address holds a balance right now."
        case .active: return "Empty now, but it has on-chain history."
        case .empty: return "The chain answered: nothing here yet."
        case .unused: return "This address has never appeared in a transaction."
        case .invalid: return "The address could not be derived or was rejected."
        case .verifying: return "Two providers disagree about this balance."
        case .unavailable: return "No provider answered — this says nothing about the funds."
        }
    }
}

// MARK: - provider output

/// One provider's answer for one address.
public struct ProviderReport: Sendable, Equatable {
    public var provider: String
    public var native: NativeBalance
    public var tokens: [TokenHolding]
    public var activity: [ChainActivity]
    public var transactionCount: Int?
    /// True when the provider positively knows the address has never transacted.
    public var neverUsed: Bool

    public init(provider: String, native: NativeBalance, tokens: [TokenHolding] = [],
                activity: [ChainActivity] = [], transactionCount: Int? = nil, neverUsed: Bool = false) {
        self.provider = provider
        self.native = native
        self.tokens = tokens
        self.activity = activity
        self.transactionCount = transactionCount
        self.neverUsed = neverUsed
    }
}

/// Everything the app learned about one derived address.
public struct AddressReport: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var networkID: String
    public var networkName: String
    public var symbol: String
    public var address: String
    public var path: String
    public var schemeLabel: String
    public var isPrimary: Bool
    public var state: ScanState
    public var native: NativeBalance
    public var tokens: [TokenHolding]
    public var activity: [ChainActivity]
    public var transactionCount: Int?
    public var verification: Verification
    public var providers: [String]
    public var failures: [String]
    public var scannedAt: Date

    public var usdValue: Decimal {
        guard state != .verifying, state != .unavailable else { return 0 }
        return (native.usdValue ?? 0) + tokens.filter { !$0.isFlagged }.compactMap(\.usdValue).reduce(0, +)
    }

    public var tokenCount: Int { tokens.count }
    public var flaggedTokens: [TokenHolding] { tokens.filter(\.isFlagged) }
    public var realTokens: [TokenHolding] { tokens.filter { !$0.isFlagged } }
}

// MARK: - the whole picture

public struct Portfolio: Codable, Equatable, Sendable {
    public var reports: [AddressReport]
    public var totalUSD: Decimal
    public var confirmedUSD: Decimal
    public var unconfirmedUSD: Decimal
    public var scannedAt: Date
    public var duration: TimeInterval
    public var providersUsed: [String]
    public var failures: [String]
    public var duplicateAddresses: [Duplicate]

    public struct Duplicate: Codable, Equatable, Sendable, Identifiable {
        public var id: String { "\(networkID):\(address)" }
        public var networkID: String
        public var address: String
        public var paths: [String]
    }

    public var fundedReports: [AddressReport] { reports.filter { $0.state == .funded } }
    /// Addresses that only ever received junk: they are not funded, they were targeted.
    public var dustedReports: [AddressReport] {
        reports.filter { $0.state == .funded && $0.native.isZero && $0.realTokens.allSatisfy { $0.amount == 0 } }
    }
    public var flaggedTokenCount: Int { reports.reduce(0) { $0 + $1.flaggedTokens.count } }
    public var needsAttention: [AddressReport] {
        reports.filter { $0.state == .verifying || $0.state == .invalid }
    }

    /// Newest first, across every chain.
    public var activityFeed: [ChainActivity] {
        reports.flatMap(\.activity).sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    public var networkTotals: [NetworkTotal] {
        var byNetwork: [String: NetworkTotal] = [:]
        for report in reports {
            var total = byNetwork[report.networkID] ?? NetworkTotal(networkID: report.networkID,
                                                                  symbol: report.symbol,
                                                                  usd: 0,
                                                                  confirmed: true,
                                                                  addressCount: 0)
            let value = report.usdValue
            total.usd += value
            total.addressCount += 1
            if report.verification != .agreed { total.confirmed = false }
            byNetwork[report.networkID] = total
        }
        return byNetwork.values.sorted { $0.usd > $1.usd }
    }

    public struct NetworkTotal: Codable, Equatable, Sendable, Identifiable {
        public var id: String { networkID }
        public var networkID: String
        public var symbol: String
        public var usd: Decimal
        public var confirmed: Bool
        public var addressCount: Int
    }

    public var tokenTotals: [TokenHolding] {
        var seen: [String: TokenHolding] = [:]
        for report in reports {
            for token in report.tokens where token.amount > 0 && !token.isFlagged {
                if var existing = seen[token.id] {
                    existing.amount += token.amount
                    existing.usdValue = (existing.usdValue ?? 0) + (token.usdValue ?? 0)
                    seen[token.id] = existing
                } else {
                    seen[token.id] = token
                }
            }
        }
        return seen.values.sorted { ($0.usdValue ?? 0) > ($1.usdValue ?? 0) }
    }

    public static let empty = Portfolio(reports: [], totalUSD: 0, confirmedUSD: 0, unconfirmedUSD: 0,
                                        scannedAt: .distantPast, duration: 0,
                                        providersUsed: [], failures: [], duplicateAddresses: [])
}

/// The number a scan screen shows after a run; kept in the history list.
public struct ScanSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var date: Date
    public var totalUSD: Decimal
    public var addressCount: Int
    public var fundedCount: Int
    public var states: [String: Int]
    public var providersUsed: [String]
    public var duration: TimeInterval

    public init(from portfolio: Portfolio) {
        self.id = UUID().uuidString
        self.date = portfolio.scannedAt
        self.totalUSD = portfolio.totalUSD
        self.addressCount = portfolio.reports.count
        self.fundedCount = portfolio.fundedReports.count
        var counts: [String: Int] = [:]
        for report in portfolio.reports { counts[report.state.rawValue, default: 0] += 1 }
        self.states = counts
        self.providersUsed = portfolio.providersUsed
        self.duration = portfolio.duration
    }
}
