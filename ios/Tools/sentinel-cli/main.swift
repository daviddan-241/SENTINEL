import Foundation
import SentinelCore

/// Shared so the process can tear it down explicitly before exiting.
let transport = URLSessionTransport()
let registry = ProviderRegistry.live(transport: transport)
let scanner = PortfolioScanner(registry: registry)

// A small command-line front end for the same core the app uses. Handy for checking a
// wallet from a terminal, and it exercises the live providers end to end.
//
//   sentinel scan <address|mnemonic> [--json]
//   sentinel phrase <mnemonic>            → addresses for every supported network
//   sentinel prices                       → live USD rates the app uses

let arguments = Array(CommandLine.arguments.dropFirst())
let wantsJSON = arguments.contains("--json")
let filtered = arguments.filter { $0 != "--json" }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func printJSON(_ object: Any) {
    let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data ?? Data(), encoding: .utf8) ?? "{}")
}

func reportDictionary(_ report: AddressReport) -> [String: Any] {
    var out: [String: Any] = [
        "network": report.networkID,
        "address": report.address,
        "path": report.path,
        "state": report.state.rawValue,
        "verification": report.verification.rawValue,
        "native": report.native.raw,
        "native_amount": String(describing: report.native.amount),
        "providers": report.providers,
    ]
    if let price = report.native.usdPrice { out["usd_price"] = String(describing: price) }
    if let value = report.native.usdValue { out["usd_value"] = String(describing: value) }
    if let transactions = report.transactionCount { out["transactions"] = transactions }
    if !report.tokens.isEmpty {
        out["tokens"] = report.tokens.prefix(10).map { ["symbol": $0.symbol, "amount": String(describing: $0.amount)] }
    }
    if !report.failures.isEmpty { out["failures"] = report.failures }
    return out
}

@main
struct SentinelCLI {
    static func main() async {
        guard let command = filtered.first else {
            print("""
            sentinel — wallet scanner for the SentinelWallet app

              sentinel scan <address|mnemonic> [--json]   scan an address (or derive from a phrase)
              sentinel phrase <mnemonic>                  show every derived address
              sentinel prices                             live USD prices used for portfolio totals
            """)
            finish()
        }

        switch command {
        case "phrase", "scan":
            guard filtered.count > 1 else { fail("\(command) needs an address or a recovery phrase") }
            let input = filtered[1]
            let validation = BIP39.validate(input)
            if case .valid = validation {
                await scanPhrase(input)
            } else if command == "phrase" {
                fail("not a valid BIP-39 phrase: \(validation.explanation)")
            } else {
                await scanAddress(input)
            }

        case "prices":
            let source = KrakenPriceSource(transport: transport)
            do {
                let prices = try await source.prices(symbols: ["BTC", "ETH", "SOL"])
                printJSON(prices.mapValues { String(describing: $0) })
            } catch {
                fail("prices unavailable: \(error)")
            }
            finish()

        default:
            fail("unknown command \(command)")
        }
    }

    /// Closes the socket pool, then exits. Linux Foundation segfaults in its own teardown
    /// when a URLSession is still alive at process exit, so a CLI should stop it first.
    static func finish() -> Never {
        transport.invalidate()
        exit(0)
    }

    static func accounts(for phrase: String) async -> [DerivedAccount] {
        do {
            return try Derivation.accounts(for: .mnemonic(phrase: phrase, passphrase: ""))
        } catch {
            fail("could not derive: \(error)")
        }
    }

    static func scanPhrase(_ phrase: String) async {
        let accounts = await accounts(for: phrase)
        let inputs = accounts.map { ScanInput(walletID: "cli", walletLabel: "CLI", account: $0) }
        let portfolio = await scanner.scan(inputs)
        if wantsJSON {
            printJSON(["reports": portfolio.reports.map(reportDictionary),
                       "total_usd": String(describing: portfolio.totalUSD),
                       "failures": portfolio.failures])
        } else {
            print(portfolioText(portfolio))
        }
        SentinelCLI.finish()
    }

    static func scanAddress(_ address: String) async {
        guard let network = Networks.all.first(where: { Address.classify(address) != nil && $0.kind.covers(address) }) else {
            fail("\"\(address)\" is not a valid EVM, Bitcoin or Solana address")
        }
        let report = await scanner.lookup(address: address, network: network)
        if wantsJSON {
            printJSON(reportDictionary(report))
        } else {
            print("\(report.networkName)  \(report.address)")
            print("  state        \(report.state.title) — \(report.state.detail)")
            print("  balance      \(report.native.amount) \(report.symbol)"
                  + (report.native.usdValue.map { " (≈ $\($0))" } ?? ""))
            print("  verification \(report.verification.label)")
            print("  providers    \(report.providers.joined(separator: ", "))")
            if !report.tokens.isEmpty {
                print("  tokens")
                for token in report.tokens.prefix(10) {
                    print("    \(token.symbol.padding(toLength: 8, withPad: " ", startingAt: 0)) \(token.amount)")
                }
            }
            for failure in report.failures { print("  ! \(failure)") }
        }
        SentinelCLI.finish()
    }

    static func portfolioText(_ portfolio: Portfolio) -> String {
        var lines = ["\(portfolio.reports.count) addresses scanned in \(String(format: "%.1f", portfolio.duration))s"]
        lines.append("total        $\(portfolio.totalUSD)")
        lines.append("confirmed    $\(portfolio.confirmedUSD)   single-source $\(portfolio.unconfirmedUSD)")
        for report in portfolio.reports where report.state == .funded || report.state == .verifying {
            lines.append("  \(report.networkName) \(report.address)  \(report.native.amount) \(report.symbol)  [\(report.state.rawValue)]")
        }
        if !portfolio.duplicateAddresses.isEmpty {
            lines.append("duplicate addresses: \(portfolio.duplicateAddresses.count)")
        }
        for failure in portfolio.failures.prefix(6) { lines.append("  ! \(failure)") }
        return lines.joined(separator: "\n")
    }
}

extension Network.Kind {
    func covers(_ address: String) -> Bool {
        guard let kind = Address.classify(address) else { return false }
        switch self {
        case .evm: return kind == .evm
        case .bitcoin: return kind != .evm && kind != .solana
        case .solana: return kind == .solana
        }
    }
}
