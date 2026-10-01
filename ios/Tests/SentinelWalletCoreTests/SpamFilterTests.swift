import XCTest
@testable import SentinelCore

/// Every name in `realDustedNames` was read off a live explorer for the standard test
/// address — a real address that receives junk constantly. The filter has to catch these
/// without flagging ordinary tokens.
final class SpamFilterTests: XCTestCase {
    /// Captured from Ethereum, Base, Polygon, Optimism, Arbitrum and Gnosis for the BIP-44
    /// test address, October 2026.
    private let realDustedNames: [(String, String)] = [
        ("Visit https://5eth.vip to claim Airdrop", "5ETH"),
        ("Telegram @CheckSeedAndNancyBot", "CHECKSEED"),
        ("www.badrp.co ✅", "BADRP"),
        ("Airdrop: degen.gifts/?claim", "DEGEN"),
        ("ARB | t.me/s/arb_pool", "ARB"),
        ("BellaFi at https://Bellafi.top", "BELLA"),
        ("Read more: https://hana-network.cc/", "HANA"),
        ("Unwrap: https://HEXPool.io", "HEX"),
        ("www.vefa.rest 💰", "VEFA"),
        ("$ CLAIM ON: [web3sui.lol]", "SUI"),
        ("polbridge.vercel.app bridge", "POLB"),
        ("Claim USDC at https://cusdc.disusd.eth.limo", "CUSDC"),
        ("bridge for 14500 $POL(polbridge.vercel.app)", "14500POL"),
        ("swap for 9800MATIC[polybridg.vercel.app]", "MATIC"),
        ("10000 ZKsync airdrop claim [ zksync.lat ]", "ZK"),
        ("ACX   [via www.across.events]", "ACX"),
        ("Telegram @TronVanity88_bot", "TRON"),
    ]

    /// The one token from that address the heuristics deliberately do not judge.
    ///
    /// "OpenAI" was dusted to the same address by the same campaign, and there is no official
    /// OpenAI token — but its name and symbol are ordinary words. Calling it junk would mean
    /// guessing, so it is left alone unless the explorer publishes a reputation for it.
    /// Curated brand lists are the right fix, and that is a data problem, not a regex one.
    private let looksOrdinaryButIsNot = [("OpenAI", "OPENAI")]

    private let ordinaryTokens: [(String, String)] = [
        ("SmartFund for Dividend", "SFD"),
        ("Royal Dog", "DOG"),
        ("Fiat24", "Fiat24"),
        ("USD Coin", "USDC"),
        ("Tether USD", "USDT"),
        ("Wrapped Ether", "WETH"),
        ("Dai Stablecoin", "DAI"),
        ("Chainlink Token", "LINK"),
        ("Uniswap", "UNI"),
        ("Aave Token", "AAVE"),
        ("BLEND", "BLEND"),
        ("Gold Token", "XAU"),
        ("Gnosis Token", "GNO"),
        ("Bridged USDC (Stargate)", "USDC.e"),
    ]

    func testRealJunkTokensAreFlagged() {
        for (name, symbol) in realDustedNames {
            XCTAssertTrue(SpamFilter.isFlagged(name: name, symbol: symbol, reputation: "ok"),
                          "missed the junk token \(name)")
            XCTAssertFalse(SpamFilter.reason(name: name, symbol: symbol, reputation: "ok").isEmpty)
        }
    }

    func testOrdinaryTokensAreNotFlagged() {
        for (name, symbol) in ordinaryTokens {
            XCTAssertFalse(SpamFilter.isFlagged(name: name, symbol: symbol, reputation: "ok"),
                           "wrongly flagged \(name)")
        }
    }

    func testExplorerReputationWins() {
        XCTAssertTrue(SpamFilter.isFlagged(name: "Something Innocent", symbol: "SI", reputation: "spam"))
        XCTAssertTrue(SpamFilter.isFlagged(name: "Ordinary", symbol: "OK", reputation: "HONEYPOT"))
        XCTAssertFalse(SpamFilter.isFlagged(name: "Ordinary", symbol: "OK", reputation: "ok"))
        XCTAssertTrue(SpamFilter.reason(name: "Ordinary", symbol: "OK", reputation: "spam").contains("spam"))
    }

    func testImpersonationWithoutAReputationIsLeftAlone() {
        for (name, symbol) in looksOrdinaryButIsNot {
            XCTAssertFalse(SpamFilter.isFlagged(name: name, symbol: symbol, reputation: "ok"))
            XCTAssertTrue(SpamFilter.isFlagged(name: name, symbol: symbol, reputation: "spam"),
                          "an explorer reputation is enough to flag it")
        }
    }

    func testEmptyNamesAreFlaggedNotCrashing() {
        XCTAssertTrue(SpamFilter.isFlagged(name: "", symbol: "", reputation: nil))
        XCTAssertTrue(SpamFilter.isFlagged(name: " ", symbol: " ", reputation: nil))
    }

    func testFlaggedTokensAreExcludedFromTotals() {
        let flagged = TokenHolding(contract: "0x1", symbol: "5ETH", name: "Visit https://5eth.vip to claim Airdrop",
                                   decimals: 18, rawValue: "1000000000000000000", amount: 1,
                                   exchangeRate: 5000, usdValue: 5000, standard: "ERC-20")
        XCTAssertTrue(flagged.isFlagged)
        let real = TokenHolding(contract: "0x2", symbol: "USDC", name: "USD Coin", decimals: 6,
                                rawValue: "2500000", amount: Decimal(string: "2.5")!, exchangeRate: 1,
                                usdValue: Decimal(string: "2.5"), standard: "ERC-20")
        XCTAssertFalse(real.isFlagged)

        let report = AddressReport(id: "ethereum:0xabc", networkID: "ethereum", networkName: "Ethereum",
                                   symbol: "ETH", address: "0xabc", path: "m/44'/60'/0'/0/0",
                                   schemeLabel: "legacy", isPrimary: true, state: .funded,
                                   native: NativeBalance(symbol: "ETH", raw: "0", amount: 0,
                                                         decimals: 18, usdPrice: 2500, usdValue: 0),
                                   tokens: [flagged, real], activity: [], transactionCount: 2,
                                   verification: .agreed, providers: ["test"], failures: [],
                                   scannedAt: Date())
        XCTAssertEqual(report.usdValue, Decimal(string: "2.5"), "the airdrop lure must not add value")
        XCTAssertEqual(report.flaggedTokens.count, 1)
        XCTAssertEqual(report.realTokens.map(\.symbol), ["USDC"])

        let portfolio = Portfolio(reports: [report], totalUSD: report.usdValue, confirmedUSD: report.usdValue,
                                  unconfirmedUSD: 0, scannedAt: Date(), duration: 0.1,
                                  providersUsed: ["test"], failures: [], duplicateAddresses: [])
        XCTAssertEqual(portfolio.flaggedTokenCount, 1)
        XCTAssertEqual(portfolio.tokenTotals.map(\.symbol), ["USDC"])
    }

    func testAnAddressThatOnlyReceivedJunkIsCalledOut() {
        let junk = TokenHolding(contract: "0x1", symbol: "5ETH", name: "Visit https://5eth.vip to claim Airdrop",
                                decimals: 18, rawValue: "1", amount: Decimal(string: "0.000000000000000001")!,
                                standard: "ERC-20")
        let report = AddressReport(id: "ethereum:0xabc", networkID: "ethereum", networkName: "Ethereum",
                                   symbol: "ETH", address: "0xabc", path: "m/44'/60'/0'/0/0",
                                   schemeLabel: "legacy", isPrimary: true, state: .funded,
                                   native: NativeBalance(symbol: "ETH", raw: "0", amount: 0, decimals: 18),
                                   tokens: [junk], activity: [], transactionCount: 1,
                                   verification: .agreed, providers: ["test"], failures: [],
                                   scannedAt: Date())
        let portfolio = Portfolio(reports: [report], totalUSD: 0, confirmedUSD: 0, unconfirmedUSD: 0,
                                  scannedAt: Date(), duration: 0.1, providersUsed: [], failures: [],
                                  duplicateAddresses: [])
        XCTAssertEqual(portfolio.dustedReports.count, 1, "flagged as a dusted address, not as funded")
    }

    func testFixtureTokensAreDecodedWithTheirReputation() async throws {
        let transport = FixtureTransport(routes: [
            ("/api/v2/addresses/\(TestVectors.ethAddress)/counters", "evm_eth_counters"),
            ("/api/v2/addresses/\(TestVectors.ethAddress)/token-balances", "evm_eth_token_balances"),
            ("/api/v2/addresses/\(TestVectors.ethAddress)/transactions", "evm_eth_transactions"),
            ("/api/v2/addresses/\(TestVectors.ethAddress)", "evm_eth_address"),
        ])
        let provider = try XCTUnwrap(BlockscoutProvider(network: Networks.ethereum, transport: transport))
        let report = try await provider.report(address: TestVectors.ethAddress, network: Networks.ethereum)
        let fixture = try XCTUnwrap(try Fixtures.json("evm_eth_token_balances") as? [[String: Any]])
        for (index, token) in report.tokens.enumerated() {
            let expected = try XCTUnwrap((fixture[index]["token"] as? [String: Any])?["reputation"] as? String)
            XCTAssertEqual(token.reputation, expected)
        }
    }
}
