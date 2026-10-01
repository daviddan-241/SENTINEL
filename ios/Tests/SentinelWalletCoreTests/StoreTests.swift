import XCTest
@testable import SentinelCore

final class StoreTests: XCTestCase {
    private var vaultStore: VaultStore!
    private var portfolioStore: PortfolioStore!

    override func setUp() {
        super.setUp()
        vaultStore = .inMemory()
        portfolioStore = .inMemory()
    }

    override func tearDown() {
        try? vaultStore.delete()
        try? portfolioStore.clear()
        super.tearDown()
    }

    func testVaultSurvivesAWriteAndRead() throws {
        var unlocked = try Vault.create(password: "correct horse", iterations: 1_000)
        try unlocked.add(kind: .mnemonic, label: "Main", hint: "hint", secret: Data(TestVectors.mnemonic.utf8))
        try vaultStore.save(unlocked.sealed)

        XCTAssertTrue(vaultStore.exists)
        let loaded = try XCTUnwrap(try vaultStore.load())
        let reopened = try Vault.unlock(loaded, password: "correct horse")
        XCTAssertEqual(try reopened.secret(of: reopened.vault.items[0]), Data(TestVectors.mnemonic.utf8))

        let onDisk = try String(contentsOf: vaultStore.url, encoding: .utf8)
        XCTAssertFalse(onDisk.contains("abandon"), "the phrase must never be on disk in the clear")
    }

    func testDeletingTheVaultDeletesTheFile() throws {
        let unlocked = try Vault.create(password: "pw", iterations: 1_000)
        try vaultStore.save(unlocked.sealed)
        try vaultStore.delete()
        XCTAssertFalse(vaultStore.exists)
        XCTAssertNil(try vaultStore.load())
    }

    func testScanHistoryKeepsTheLatestFirstAndCapsItsLength() throws {
        for index in 0..<5 {
            let report = AddressReport(id: "ethereum:0x\(index)", networkID: "ethereum", networkName: "Ethereum",
                                       symbol: "ETH", address: "0x\(index)", path: "m/44'/60'/0'/0/0",
                                       schemeLabel: "legacy", isPrimary: true, state: .funded,
                                       native: NativeBalance(symbol: "ETH", raw: "1", amount: 1, decimals: 18,
                                                             usdPrice: Decimal(index + 1), usdValue: Decimal(index + 1)),
                                       tokens: [], activity: [], transactionCount: 1,
                                       verification: .agreed, providers: ["test"], failures: [],
                                       scannedAt: Date())
            let portfolio = Portfolio(reports: [report], totalUSD: Decimal(index + 1),
                                      confirmedUSD: Decimal(index + 1), unconfirmedUSD: 0,
                                      scannedAt: Date(), duration: 0.5, providersUsed: ["test"],
                                      failures: [], duplicateAddresses: [])
            _ = try portfolioStore.record(portfolio)
        }
        let stored = try portfolioStore.load()
        XCTAssertEqual(stored.history.count, 5)
        XCTAssertEqual(stored.history.first?.totalUSD, 5, "newest first")
        XCTAssertEqual(stored.lastPortfolio?.totalUSD, 5, "the last scan is kept whole")

        let capped = PortfolioStore(url: portfolioStore.url, historyLimit: 2)
        _ = try capped.record(try XCTUnwrap(stored.lastPortfolio))
        XCTAssertEqual(try capped.load().history.count, 2)
    }

    func testMissingFileIsNotAnError() throws {
        XCTAssertNil(try vaultStore.load())
        XCTAssertEqual(try portfolioStore.load(), .empty)
    }
}
