import XCTest
@testable import SentinelCore

/// A provider whose answers the test controls. Used for the classification and verification
/// logic, where the interesting cases (disagreement, timeouts, silence) cannot be produced by
/// replaying a recorded payload.
final class StubProvider: AddressProvider, @unchecked Sendable {
    let name: String
    private let kinds: [Network.Kind]
    private let lock = NSLock()
    private var queue: [Result<ProviderReport, ChainError>]
    var delay: TimeInterval = 0

    init(name: String, kinds: [Network.Kind] = [.evm, .bitcoin, .solana],
         report: ProviderReport? = nil, error: ChainError? = nil,
         sequence: [Result<ProviderReport, ChainError>] = []) {
        self.name = name
        self.kinds = kinds
        if !sequence.isEmpty {
            self.queue = sequence
        } else if let error {
            self.queue = [.failure(error)]
        } else if let report {
            self.queue = [.success(report)]
        } else {
            self.queue = []
        }
    }

    func supports(_ network: Network) -> Bool { kinds.contains(network.kind) }

    func report(address: String, network: Network, limit: Int) async throws -> ProviderReport {
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        let next: Result<ProviderReport, ChainError>? = lock.withLock {
            queue.count > 1 ? queue.removeFirst() : queue.first
        }
        switch next {
        case .success(let report): return report
        case .failure(let error): throw error
        case nil: throw ChainError.rejected(provider: name, detail: "no scripted answer")
        }
    }
}

enum Stubbed {
    static func report(provider: String, symbol: String = "ETH", wei: String = "1000000000000000000",
                       decimals: Int = 18, price: Decimal? = Decimal(string: "2500"),
                       tokens: [TokenHolding] = [], activity: [ChainActivity] = [],
                       transactions: Int? = 4, neverUsed: Bool = false) -> ProviderReport {
        let amount = DecimalParsing.amount(raw: wei, decimals: decimals)
        return ProviderReport(provider: provider,
                              native: NativeBalance(symbol: symbol, raw: wei, amount: amount,
                                                    decimals: decimals, usdPrice: price,
                                                    usdValue: price.map { $0 * amount }),
                              tokens: tokens, activity: activity,
                              transactionCount: transactions, neverUsed: neverUsed)
    }

    static func account(_ network: Network = Networks.ethereum, path: String? = nil,
                        address: String = TestVectors.ethAddress, primary: Bool = true) -> DerivedAccount {
        DerivedAccount(network: network, path: path ?? network.derivationPath, address: address,
                       schemeLabel: network.scheme.shortLabel, isPrimary: primary)
    }
}

final class ScannerTests: XCTestCase {
    private let evmAddress = TestVectors.ethAddress

    private func scanner(_ providers: [AddressProvider], timeout: TimeInterval = 5,
                         priceSource: PriceSource? = nil) -> PortfolioScanner {
        PortfolioScanner(registry: ProviderRegistry(providers: providers, priceSource: priceSource),
                         concurrency: 2, timeout: timeout, activityLimit: 5, reconciliationDelay: 0.01)
    }

    // MARK: classification

    func testFundedAddressConfirmedByTwoProviders() async {
        let scanner = scanner([
            StubProvider(name: "explorer", report: Stubbed.report(provider: "explorer")),
            StubProvider(name: "node", report: Stubbed.report(provider: "node")),
        ])
        let portfolio = await scanner.scan([ScanInput(walletID: "w1", walletLabel: "Main", account: Stubbed.account())])
        let report = portfolio.reports[0]

        XCTAssertEqual(report.state, .funded)
        XCTAssertEqual(report.verification, .agreed)
        XCTAssertEqual(report.native.amount, 1)
        XCTAssertEqual(report.usdValue, 2500)
        XCTAssertEqual(portfolio.totalUSD, 2500)
        XCTAssertEqual(portfolio.confirmedUSD, 2500)
        XCTAssertEqual(portfolio.unconfirmedUSD, 0)
        XCTAssertEqual(portfolio.providersUsed.sorted(), ["explorer", "node"])
        XCTAssertTrue(portfolio.needsAttention.isEmpty)
        XCTAssertEqual(portfolio.fundedReports.count, 1)
    }

    func testSingleSourceIsMarkedUnconfirmed() async {
        let scanner = scanner([StubProvider(name: "explorer", report: Stubbed.report(provider: "explorer"))])
        let portfolio = await scanner.scan([ScanInput(walletID: "w1", walletLabel: "Main", account: Stubbed.account())])
        let report = portfolio.reports[0]
        XCTAssertEqual(report.state, .funded)
        XCTAssertEqual(report.verification, .singleSource)
        XCTAssertEqual(portfolio.totalUSD, 2500)
        XCTAssertEqual(portfolio.confirmedUSD, 0)
        XCTAssertEqual(portfolio.unconfirmedUSD, 2500, "single-source money is never called confirmed")
    }

    func testDisagreeingProvidersAskForVerificationAndAreExcludedFromTheTotal() async {
        let scanner = scanner([
            StubProvider(name: "explorer", report: Stubbed.report(provider: "explorer", wei: "1000000000000000000")),
            StubProvider(name: "node", report: Stubbed.report(provider: "node", wei: "2000000000000000000")),
        ])
        let portfolio = await scanner.scan([ScanInput(walletID: "w1", walletLabel: "Main", account: Stubbed.account())])
        let report = portfolio.reports[0]
        XCTAssertEqual(report.state, .verifying)
        XCTAssertEqual(report.verification, .disagreed)
        XCTAssertEqual(report.usdValue, 0, "an unverified balance must not be totalled")
        XCTAssertEqual(portfolio.totalUSD, 0)
        XCTAssertEqual(portfolio.needsAttention.map(\.id), [report.id])
    }

    func testDisagreementThatClearsUpOnASecondLookIsConfirmed() async {
        // The explorer was a block behind; asked again it agrees with the node.
        let behind = Stubbed.report(provider: "explorer", wei: "1000000000000000000")
        let caughtUp = Stubbed.report(provider: "explorer", wei: "2000000000000000000")
        let scanner = scanner([
            StubProvider(name: "explorer", sequence: [.success(behind), .success(caughtUp)]),
            StubProvider(name: "node", report: Stubbed.report(provider: "node", wei: "2000000000000000000")),
        ])
        let portfolio = await scanner.scan([ScanInput(walletID: "w1", walletLabel: "Main", account: Stubbed.account())])
        let report = portfolio.reports[0]
        XCTAssertEqual(report.verification, .agreed)
        XCTAssertEqual(report.state, .funded)
        XCTAssertEqual(report.native.amount, 2, "the fresh, agreed number is the one that is shown")
        XCTAssertEqual(report.usdValue, 5000)
    }

    func testNothingReachableIsNotAnEmptyWallet() async {
        let scanner = scanner([
            StubProvider(name: "explorer", error: .offline),
            StubProvider(name: "node", error: .timedOut),
        ])
        let portfolio = await scanner.scan([ScanInput(walletID: "w1", walletLabel: "Main", account: Stubbed.account())])
        let report = portfolio.reports[0]
        XCTAssertEqual(report.state, .unavailable, "silence is not proof of an empty wallet")
        XCTAssertEqual(report.verification, .unavailable)
        XCTAssertEqual(report.failures.count, 2)
        XCTAssertTrue(report.failures.contains { $0.contains("No internet connection") })
        XCTAssertTrue(report.failures.contains { $0.contains("too long") })
        XCTAssertEqual(portfolio.totalUSD, 0)
        XCTAssertFalse(portfolio.failures.isEmpty)
    }

    func testSlowProviderHitsTheTimeout() async {
        let slow = StubProvider(name: "explorer", report: Stubbed.report(provider: "explorer"))
        slow.delay = 1.0
        let scanner = scanner([slow], timeout: 0.1)
        let portfolio = await scanner.scan([ScanInput(walletID: "w1", walletLabel: "Main", account: Stubbed.account())])
        XCTAssertEqual(portfolio.reports[0].state, .unavailable)
        XCTAssertTrue(portfolio.reports[0].failures.first?.contains("took too long") ?? false)
    }

    func testUnusedEmptyAndActiveStates() async {
        let unused = scanner([StubProvider(name: "node", report: Stubbed.report(provider: "node", wei: "0",
                                                                               transactions: 0, neverUsed: true))])
        let unusedPortfolio = await unused.scan([ScanInput(walletID: "w", walletLabel: "w",
                                                           account: Stubbed.account())])
        XCTAssertEqual(unusedPortfolio.reports[0].state, .unused)

        let empty = scanner([StubProvider(name: "node", report: Stubbed.report(provider: "node", wei: "0",
                                                                              transactions: 0, neverUsed: false))])
        let emptyPortfolio = await empty.scan([ScanInput(walletID: "w", walletLabel: "w", account: Stubbed.account())])
        XCTAssertEqual(emptyPortfolio.reports[0].state, .empty)

        let active = scanner([StubProvider(name: "node", report: Stubbed.report(provider: "node", wei: "0",
                                                                               transactions: 12, neverUsed: false))])
        let activePortfolio = await active.scan([ScanInput(walletID: "w", walletLabel: "w",
                                                           account: Stubbed.account())])
        XCTAssertEqual(activePortfolio.reports[0].state, .active)
    }

    func testTokensCountAsFunds() async {
        let token = TokenHolding(contract: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", symbol: "USDC",
                                 name: "USD Coin", decimals: 6, rawValue: "2500000", amount: 2.5,
                                 exchangeRate: 1, usdValue: 2.5, standard: "ERC-20")
        let scanner = scanner([StubProvider(name: "explorer",
                                            report: Stubbed.report(provider: "explorer", wei: "0", tokens: [token],
                                                                   transactions: 3))])
        let portfolio = await scanner.scan([ScanInput(walletID: "w", walletLabel: "w", account: Stubbed.account())])
        XCTAssertEqual(portfolio.reports[0].state, .funded)
        XCTAssertEqual(portfolio.reports[0].usdValue, Decimal(string: "2.5"))
        XCTAssertEqual(portfolio.tokenTotals.first?.symbol, "USDC")
    }

    func testPriceSourceFillsInAMissingRate() async {
        struct FixedPrice: PriceSource {
            let name = "test"
            func prices(symbols: [String]) async throws -> [String: Decimal] { ["SOL": 120] }
        }
        let solana = Networks.solana
        let provider = StubProvider(name: "solana-rpc", kinds: [.solana],
                                    report: Stubbed.report(provider: "solana-rpc", symbol: "SOL",
                                                           wei: "2000000000", decimals: 9, price: nil,
                                                           transactions: 1))
        let scanner = scanner([provider], priceSource: FixedPrice())
        let portfolio = await scanner.scan([ScanInput(walletID: "w", walletLabel: "w",
                                                     account: Stubbed.account(solana,
                                                                              address: TestVectors.solanaAddress))])
        let report = portfolio.reports[0]
        XCTAssertEqual(report.native.usdPrice, 120)
        XCTAssertEqual(report.native.usdValue, 240, "2 SOL at 120")
    }

    // MARK: duplicates, lookup, ordering

    func testTheSameAddressUnderTwoWalletsIsReportedAsADuplicate() async {
        let provider = StubProvider(name: "explorer", report: Stubbed.report(provider: "explorer"))
        let scanner = scanner([provider, StubProvider(name: "node", report: Stubbed.report(provider: "node"))])
        let portfolio = await scanner.scan([
            ScanInput(walletID: "w1", walletLabel: "Main", account: Stubbed.account(path: TestVectors.ethPath)),
            ScanInput(walletID: "w2", walletLabel: "Imported",
                      account: Stubbed.account(path: "m/44'/60'/0'/0/7", address: TestVectors.ethAddress)),
        ])
        XCTAssertEqual(portfolio.duplicateAddresses.count, 1)
        let duplicate = portfolio.duplicateAddresses[0]
        XCTAssertEqual(duplicate.networkID, "ethereum")
        XCTAssertEqual(duplicate.address, TestVectors.ethAddress.lowercased())
        XCTAssertEqual(duplicate.paths, [TestVectors.ethPath, "m/44'/60'/0'/0/7"].sorted())
    }

    func testLookupOfSomethingThatIsNotAnAddressIsInvalid() async {
        let scanner = scanner([StubProvider(name: "explorer", report: Stubbed.report(provider: "explorer"))])
        let report = await scanner.lookup(address: "definitely not an address", network: Networks.ethereum)
        XCTAssertEqual(report.state, .invalid)
        XCTAssertEqual(report.verification, .unavailable)
        XCTAssertFalse(report.failures.isEmpty)
    }

    func testLookupOfARealAddressUsesTheSameScanner() async {
        let scanner = scanner([
            StubProvider(name: "explorer", report: Stubbed.report(provider: "explorer")),
            StubProvider(name: "node", report: Stubbed.report(provider: "node")),
        ])
        let report = await scanner.lookup(address: TestVectors.btcSegwitAddress, network: Networks.bitcoin)
        XCTAssertEqual(report.state, .funded)
        XCTAssertEqual(report.address, TestVectors.btcSegwitAddress)
        XCTAssertEqual(report.verification, .agreed)
    }

    func testPortfolioAggregatesAcrossNetworks() async {
        let eth = StubProvider(name: "eth-explorer", kinds: [.evm],
                               report: Stubbed.report(provider: "eth-explorer", wei: "1000000000000000000"))
        let btcReport = Stubbed.report(provider: "btc", symbol: "BTC", wei: "50000000", decimals: 8,
                                       price: Decimal(string: "80000"), transactions: 0, neverUsed: true)
        let btc = StubProvider(name: "btc", kinds: [.bitcoin], report: btcReport)
        let scanner = scanner([eth, StubProvider(name: "eth-node", kinds: [.evm],
                                                 report: Stubbed.report(provider: "eth-node")), btc])
        let portfolio = await scanner.scan([
            ScanInput(walletID: "w", walletLabel: "w", account: Stubbed.account()),
            ScanInput(walletID: "w", walletLabel: "w", account: Stubbed.account(Networks.bitcoin,
                                                                                address: TestVectors.btcLegacyAddress)),
        ])

        XCTAssertEqual(portfolio.reports.count, 2)
        XCTAssertEqual(portfolio.networkTotals.count, 2)
        XCTAssertEqual(portfolio.networkTotals.first?.networkID, "bitcoin", "largest first")
        // 1 ETH × 2500 and 0.5 BTC × 80000
        XCTAssertEqual(portfolio.networkTotals.map(\.usd), [40000, 2500])
        XCTAssertEqual(portfolio.totalUSD, 42500)
        XCTAssertEqual(portfolio.reports.first { $0.networkID == "bitcoin" }?.state, .funded)
        XCTAssertEqual(portfolio.reports.first { $0.networkID == "bitcoin" }?.native.amount,
                       Decimal(string: "0.5"))
        XCTAssertEqual(portfolio.reports.first { $0.networkID == "ethereum" }?.verification, .agreed)
        XCTAssertEqual(portfolio.reports.first { $0.networkID == "bitcoin" }?.verification, .singleSource)
    }

    func testSnapshotSummarisesAScan() async {
        let scanner = scanner([StubProvider(name: "explorer", report: Stubbed.report(provider: "explorer")),
                               StubProvider(name: "node", report: Stubbed.report(provider: "node"))])
        let portfolio = await scanner.scan([ScanInput(walletID: "w", walletLabel: "w", account: Stubbed.account())])
        let snapshot = ScanSnapshot(from: portfolio)
        XCTAssertEqual(snapshot.totalUSD, 2500)
        XCTAssertEqual(snapshot.addressCount, 1)
        XCTAssertEqual(snapshot.fundedCount, 1)
        XCTAssertEqual(snapshot.states["funded"], 1)
        XCTAssertEqual(snapshot.providersUsed.sorted(), ["explorer", "node"])
        XCTAssertNotNil(snapshot.id)
    }

    func testClassifierMatrix() {
        let funded = Stubbed.report(provider: "a")
        XCTAssertEqual(ScanClassifier.classify(address: evmAddress, primary: funded, secondary: nil,
                                               verified: false, failures: []).state, .funded)
        XCTAssertEqual(ScanClassifier.classify(address: evmAddress, primary: nil, secondary: nil,
                                               verified: false, failures: []).state, .invalid)
        XCTAssertEqual(ScanClassifier.classify(address: "nonsense", primary: funded, secondary: nil,
                                               verified: false, failures: []).state, .invalid)
        XCTAssertEqual(ScanClassifier.classify(address: evmAddress, primary: nil, secondary: nil,
                                               verified: false, failures: ["boom"]).state, .unavailable)
        let zero = Stubbed.report(provider: "a", wei: "0", transactions: 0, neverUsed: true)
        XCTAssertEqual(ScanClassifier.classify(address: evmAddress, primary: zero, secondary: nil,
                                               verified: false, failures: []).state, .unused)
    }
}
