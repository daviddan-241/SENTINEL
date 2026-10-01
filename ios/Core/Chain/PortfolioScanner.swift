import Foundation

/// One account to scan, plus which wallet in the vault it belongs to (so the same address
/// arriving from two different wallets can be reported as a duplicate).
public struct ScanInput: Sendable {
    public var walletID: String
    public var walletLabel: String
    public var account: DerivedAccount

    public init(walletID: String, walletLabel: String, account: DerivedAccount) {
        self.walletID = walletID
        self.walletLabel = walletLabel
        self.account = account
    }
}

/// Decides what a set of provider answers means. Pure functions, so every branch is testable.
public enum ScanClassifier {
    public static func classify(address: String,
                                primary: ProviderReport?,
                                secondary: ProviderReport?,
                                verified: Bool,
                                failures: [String]) -> (state: ScanState, verification: Verification) {
        guard Address.classify(address) != nil else { return (.invalid, .unavailable) }
        guard let primary else {
            return failures.isEmpty ? (.invalid, .unavailable) : (.unavailable, .unavailable)
        }
        if let secondary, secondary.native.raw != primary.native.raw {
            return (.verifying, .disagreed)
        }
        let verification: Verification
        if secondary == nil {
            verification = .singleSource
        } else if verified || secondary!.native.raw == primary.native.raw {
            verification = .agreed
        } else {
            verification = .disagreed
        }
        if primary.native.amount > 0 || primary.tokens.contains(where: { $0.amount > 0 }) {
            return (.funded, verification)
        }
        if (primary.transactionCount ?? 0) > 0 || !primary.activity.isEmpty {
            return (.active, verification)
        }
        return primary.neverUsed ? (.unused, verification) : (.empty, verification)
    }

    /// The same address derived twice — usually the same key imported under two labels.
    public static func duplicates(in reports: [AddressReport]) -> [Portfolio.Duplicate] {
        var grouped: [String: [AddressReport]] = [:]
        for report in reports {
            grouped["\(report.networkID):\(report.address.lowercased())", default: []].append(report)
        }
        return grouped.compactMap { key, group in
            let paths = Array(Set(group.map(\.path))).sorted()
            guard paths.count > 1 else { return nil }
            let parts = key.split(separator: ":")
            guard parts.count == 2 else { return nil }
            return Portfolio.Duplicate(networkID: String(parts[0]),
                                       address: String(parts[1]),
                                       paths: paths)
        }
        .sorted { $0.id < $1.id }
    }
}

/// Scans every derived address across every network and turns the answers into a portfolio.
///
/// Two independent providers are asked for the native balance. When they agree the value is
/// marked *confirmed*; when they differ the explorer is asked once more after a short pause,
/// because the difference is usually just a block that arrived between the two calls. If it
/// still differs, the address is marked "Verification required" and excluded from the total
/// rather than guessed at.
public actor PortfolioScanner {
    private let registry: ProviderRegistry
    private let concurrency: Int
    private let timeout: TimeInterval
    private let activityLimit: Int
    private let reconciliationDelay: TimeInterval

    public init(registry: ProviderRegistry = .live(),
                concurrency: Int = 4,
                timeout: TimeInterval = 25,
                activityLimit: Int = 8,
                reconciliationDelay: TimeInterval = 1.5) {
        self.registry = registry
        self.concurrency = max(1, concurrency)
        self.timeout = timeout
        self.activityLimit = activityLimit
        self.reconciliationDelay = reconciliationDelay
    }

    /// - Parameter activityLimit: overrides the depth configured at init (the app passes
    ///   the user's setting through here).
    public func scan(_ inputs: [ScanInput], activityLimit: Int? = nil) async -> Portfolio {
        let depth = activityLimit ?? self.activityLimit
        let started = Date()
        var reports: [AddressReport] = []
        var failures: Set<String> = []

        for chunk in inputs.chunked(into: concurrency) {
            await withTaskGroup(of: (AddressReport, [String]).self) { group in
                for input in chunk {
                    group.addTask { [self] in await scanOne(input, activityLimit: depth) }
                }
                for await outcome in group {
                    reports.append(outcome.0)
                    for failure in outcome.1 { failures.insert(failure) }
                }
            }
        }
        let ordered = reports.sorted { $0.id < $1.id }
        return assemble(ordered, failures: Array(failures).sorted(), started: started)
    }

    /// The address-lookup tab: one address, one network, no derivation involved.
    public func lookup(address: String, network: Network) async -> AddressReport {
        guard Address.classify(address) != nil else {
            return AddressReport(id: "\(network.id):\(address)",
                                 networkID: network.id, networkName: network.name, symbol: network.symbol,
                                 address: address, path: "(looked up)", schemeLabel: "lookup",
                                 isPrimary: true, state: .invalid,
                                 native: NativeBalance(symbol: network.symbol, raw: "0", amount: 0, decimals: 18),
                                 tokens: [], activity: [], transactionCount: nil,
                                 verification: .unavailable, providers: [], failures: ["address is not valid"],
                                 scannedAt: Date())
        }
        let input = ScanInput(walletID: "lookup", walletLabel: "Lookup",
                              account: DerivedAccount(network: network, path: "(looked up)",
                                                      address: address, schemeLabel: "lookup", isPrimary: true))
        let (report, failures) = await scanOne(input, activityLimit: activityLimit)
        var withFailures = report
        withFailures.failures = failures
        return withFailures
    }

    // MARK: internals

    private func scanOne(_ input: ScanInput, activityLimit: Int? = nil) async -> (AddressReport, [String]) {
        let network = input.account.network
        let address = input.account.address
        let candidates = registry.providers(for: network)
        let limit = activityLimit ?? self.activityLimit
        var failures: [String] = []

        guard !candidates.isEmpty else {
            return (emptyReport(input, state: .unavailable, verification: .unavailable,
                                providers: [], failures: ["no provider for \(network.name)"]),
                    ["no provider for \(network.name)"])
        }

        var reports: [ProviderReport] = []
        var usedNames: [String] = []
        for provider in candidates.prefix(2) {
            do {
                let report = try await withTimeout(timeout) {
                    try await provider.report(address: address, network: network, limit: limit)
                }
                reports.append(report)
                usedNames.append(provider.name)
            } catch let error as ChainError {
                if case .cancelled = error { break }
                failures.append("\(provider.name): \(error.message)")
            } catch {
                failures.append("\(provider.name): \(error.localizedDescription)")
            }
        }

        let primary = reports.first
        var secondary = reports.count > 1 ? reports[1] : nil
        var confirmed = false

        // Reconciliation: if the two disagree, one of them is probably just behind. Ask the
        // explorer again and, if it catches up, count the value as confirmed.
        if let primary, let comparison = secondary, comparison.native.raw != primary.native.raw {
            try? await Task.sleep(nanoseconds: UInt64(reconciliationDelay * 1_000_000_000))
            if let refreshed = try? await withTimeout(timeout, operation: {
                try await candidates[0].report(address: address, network: network, limit: 1)
            }) {
                if refreshed.native.raw == comparison.native.raw {
                    // The explorer caught up: keep its fresher number as the primary and the
                    // node as the second source, now in agreement.
                    reports[0] = refreshed
                    secondary = comparison
                    confirmed = true
                }
            }
        }

        // Read the primary again: reconciliation may have replaced it with a fresher answer.
        let resolved = reports.first
        let (state, verification) = ScanClassifier.classify(address: address,
                                                            primary: resolved,
                                                            secondary: secondary,
                                                            verified: confirmed,
                                                            failures: failures)

        guard let primary = resolved else {
            return (emptyReport(input, state: state, verification: verification,
                                providers: [], failures: failures), failures)
        }

        let native = await priced(primary.native, network: network)
        let tokens = primary.tokens
        return (AddressReport(id: "\(network.id):\(address)",
                              networkID: network.id,
                              networkName: network.name,
                              symbol: network.symbol,
                              address: address,
                              path: input.account.path,
                              schemeLabel: input.account.schemeLabel,
                              isPrimary: input.account.isPrimary,
                              state: state,
                              native: native,
                              tokens: tokens,
                              activity: primary.activity,
                              transactionCount: primary.transactionCount,
                              verification: verification,
                              providers: usedNames,
                              failures: failures,
                              scannedAt: Date()),
                failures)
    }

    /// Fills in a USD price when the chain's own provider did not publish one.
    private func priced(_ balance: NativeBalance, network: Network) async -> NativeBalance {
        guard balance.usdPrice == nil, balance.amount > 0, let source = registry.priceSource else {
            return balance
        }
        var updated = balance
        if let prices = try? await source.prices(symbols: [network.symbol]),
           let price = prices[network.symbol.uppercased()] {
            updated.usdPrice = price
            updated.usdValue = price * balance.amount
        }
        return updated
    }

    private func emptyReport(_ input: ScanInput, state: ScanState, verification: Verification,
                             providers: [String], failures: [String]) -> AddressReport {
        let network = input.account.network
        return AddressReport(id: "\(network.id):\(input.account.address)",
                             networkID: network.id,
                             networkName: network.name,
                             symbol: network.symbol,
                             address: input.account.address,
                             path: input.account.path,
                             schemeLabel: input.account.schemeLabel,
                             isPrimary: input.account.isPrimary,
                             state: state,
                             native: NativeBalance(symbol: network.symbol, raw: "0", amount: 0,
                                                   decimals: network.kind == .bitcoin ? 8 : (network.kind == .solana ? 9 : 18)),
                             tokens: [], activity: [], transactionCount: nil,
                             verification: verification, providers: providers, failures: failures,
                             scannedAt: Date())
    }

    private func assemble(_ reports: [AddressReport], failures: [String], started: Date) -> Portfolio {
        var total: Decimal = 0
        var confirmed: Decimal = 0
        var unconfirmed: Decimal = 0
        for report in reports {
            total += report.usdValue
            switch report.verification {
            case .agreed: confirmed += report.usdValue
            case .singleSource: unconfirmed += report.usdValue
            default: break
            }
        }
        let providers = Array(Set(reports.flatMap(\.providers))).sorted()
        return Portfolio(reports: reports,
                         totalUSD: total,
                         confirmedUSD: confirmed,
                         unconfirmedUSD: unconfirmed,
                         scannedAt: Date(),
                         duration: Date().timeIntervalSince(started),
                         providersUsed: providers,
                         failures: failures,
                         duplicateAddresses: ScanClassifier.duplicates(in: reports))
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
