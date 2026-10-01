import XCTest
@testable import SentinelCore

/// Loads the live responses captured by `tools/capture_fixtures.sh`.
enum Fixtures {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw XCTSkip("fixture \(name).json is missing")
        }
        return try Data(contentsOf: url)
    }

    static func json(_ name: String) throws -> Any {
        try JSONSerialization.jsonObject(with: data(name))
    }

    static func dictionary(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(json(name) as? [String: Any])
    }
}

/// Answers with a recorded response instead of hitting the network, so the decoding path runs
/// against the exact bytes the provider really sends.
struct FixtureTransport: ChainTransport {
    /// (URL substring, fixture file name) — used for GETs
    var routes: [(String, String)]
    /// (JSON-RPC method, fixture file name) — used for POSTs, so one provider can serve
    /// several RPC calls with the right recorded answer for each.
    var postRoutes: [(String, String)] = []
    var status = 200
    var bodyOverride: Data?
    var failure: ChainError?

    func get(_ url: URL, timeout: TimeInterval) async throws -> (Data, Int) {
        if let failure { throw failure }
        if routes.isEmpty { return (Data("{}".utf8), status) }
        for (needle, file) in routes where url.absoluteString.contains(needle) {
            return (try Fixtures.data(file), status)
        }
        throw ChainError.http(status: 404, provider: url.host ?? "fixture")
    }

    func post(_ url: URL, body: Data, timeout: TimeInterval) async throws -> (Data, Int) {
        if let failure { throw failure }
        if let bodyOverride { return (bodyOverride, status) }
        let method = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])??["method"] as? String
        for (wanted, file) in postRoutes where wanted == method {
            return (try Fixtures.data(file), status)
        }
        for (needle, file) in routes where url.absoluteString.contains(needle) || needle == url.host {
            return (try Fixtures.data(file), status)
        }
        if routes.isEmpty && postRoutes.isEmpty { return (Data("{}".utf8), status) }
        throw ChainError.http(status: 404, provider: url.host ?? "fixture")
    }
}

final class ChainDecodingTests: XCTestCase {
    private let evmAddress = TestVectors.ethAddress

    private var blockscoutTransport: FixtureTransport {
        FixtureTransport(routes: [
            ("/api/v2/addresses/\(evmAddress)/counters", "evm_eth_counters"),
            ("/api/v2/addresses/\(evmAddress)/token-balances", "evm_eth_token_balances"),
            ("/api/v2/addresses/\(evmAddress)/transactions", "evm_eth_transactions"),
            ("/api/v2/addresses/\(evmAddress)", "evm_eth_address"),
        ])
    }

    // MARK: Blockscout

    func testBlockscoutAddressDecodes() async throws {
        let provider = try XCTUnwrap(BlockscoutProvider(network: Networks.ethereum, transport: blockscoutTransport))
        let report = try await provider.report(address: evmAddress, network: Networks.ethereum, limit: 10)

        XCTAssertEqual(report.provider, "Ethereum Blockscout")
        XCTAssertEqual(report.native.raw, "0")
        XCTAssertEqual(report.native.amount, 0)
        XCTAssertEqual(report.native.usdPrice, Decimal(string: "2689.44"))
        XCTAssertEqual(report.transactionCount, 1280)
        XCTAssertFalse(report.neverUsed, "the fixture address has 1280 transactions")
        XCTAssertEqual(report.tokens.count, 3)
        XCTAssertEqual(report.activity.count, 2)
    }

    func testBlockscoutTokenBalancesDecode() async throws {
        let provider = try XCTUnwrap(BlockscoutProvider(network: Networks.ethereum, transport: blockscoutTransport))
        let report = try await provider.report(address: evmAddress, network: Networks.ethereum, limit: 10)
        let first = try XCTUnwrap(report.tokens.first)

        // Values come from the recorded payload, so the expectations are read from the same
        // bytes rather than typed by hand — the test still proves the decoding, not the number.
        let fixture = try XCTUnwrap(try Fixtures.json("evm_eth_token_balances") as? [[String: Any]])
        let expected = try XCTUnwrap(fixture.first)
        let token = try XCTUnwrap(expected["token"] as? [String: Any])
        let raw = try XCTUnwrap(expected["value"] as? String)
        let decimals = try XCTUnwrap(Int(token["decimals"] as? String ?? "0"))

        XCTAssertEqual(first.contract, token["address_hash"] as? String)
        XCTAssertEqual(first.symbol, token["symbol"] as? String)
        XCTAssertEqual(first.decimals, decimals)
        XCTAssertEqual(first.rawValue, raw)
        XCTAssertEqual(first.amount, DecimalParsing.amount(raw: raw, decimals: decimals))
        XCTAssertEqual(first.standard, "ERC-20")
        XCTAssertNil(first.usdValue, "this token has no published rate")
        XCTAssertTrue(report.tokens.allSatisfy { $0.contract.hasPrefix("0x") && $0.contract.count == 42 })
    }

    func testBlockscoutActivityDecodes() async throws {
        let provider = try XCTUnwrap(BlockscoutProvider(network: Networks.ethereum, transport: blockscoutTransport))
        let report = try await provider.report(address: evmAddress, network: Networks.ethereum, limit: 10)
        let first = try XCTUnwrap(report.activity.first)
        let fixture = try XCTUnwrap(try Fixtures.dictionary("evm_eth_transactions")["items"] as? [[String: Any]])
        let expected = try XCTUnwrap(fixture.first)

        XCTAssertEqual(first.hash, expected["hash"] as? String)
        XCTAssertEqual(first.amount, DecimalParsing.amount(raw: expected["value"] as? String ?? "0", decimals: 18))
        XCTAssertEqual(first.status, "success")
        XCTAssertEqual(first.direction, .incoming, "the address is the recipient of this transfer")
        XCTAssertEqual(first.networkID, "ethereum")
        XCTAssertNotNil(first.timestamp)
        XCTAssertTrue(first.isContractCall, "the destination is a contract")
        XCTAssertEqual(report.activity.map(\.hash).count, Set(report.activity.map(\.hash)).count)
    }

    func testBlockscoutHTTPFailuresMap() async throws {
        let rateLimited = try XCTUnwrap(BlockscoutProvider(network: Networks.ethereum,
                                                           transport: FixtureTransport(routes: [], status: 429)))
        do {
            _ = try await rateLimited.report(address: evmAddress, network: Networks.ethereum)
            XCTFail("expected a failure")
        } catch let error as ChainError {
            XCTAssertEqual(error, .rateLimited(provider: "Ethereum Blockscout"))
            XCTAssertTrue(error.isRetryable)
        }

        let broken = BlockscoutProvider(network: Networks.ethereum,
                                        transport: FixtureTransport(routes: [("/api/v2/addresses/", "btc_prices")]))
        do {
            _ = try await try XCTUnwrap(broken).report(address: evmAddress, network: Networks.ethereum)
            XCTFail("expected a decoding failure")
        } catch let error as ChainError {
            if case .decoding = error {} else { XCTFail("wrong error: \(error)") }
        }
    }

    // MARK: EVM JSON-RPC (the independent second opinion)

    func testEVMNodeDecodesHexQuantity() async throws {
        let transport = FixtureTransport(routes: [],
                                         postRoutes: [("eth_getBalance", "evm_rpc_balance"),
                                                      ("eth_getTransactionCount", "evm_rpc_nonce")])
        let provider = try XCTUnwrap(EVMJSONRPCProvider(network: Networks.ethereum, transport: transport))
        let report = try await provider.report(address: evmAddress, network: Networks.ethereum)
        XCTAssertEqual(report.native.raw, "0")
        XCTAssertEqual(report.provider, "Ethereum node")
        let nonce = try XCTUnwrap(try Fixtures.dictionary("evm_rpc_nonce")["result"] as? String)
        XCTAssertEqual(report.transactionCount, HexDecimal.int(fromHex: nonce))
        XCTAssertGreaterThan(report.transactionCount ?? 0, 0)
        XCTAssertFalse(report.neverUsed, "a used account has a nonce")
    }

    func testHexQuantityConversion() {
        XCTAssertEqual(HexDecimal.wei(fromHex: "0x0"), "0")
        XCTAssertEqual(HexDecimal.wei(fromHex: "0x1"), "1")
        XCTAssertEqual(HexDecimal.wei(fromHex: "0x1bc16d674ec80000"), "2000000000000000000")
        XCTAssertEqual(HexDecimal.wei(fromHex: "0xde0b6b3a7640000"), "1000000000000000000")
        XCTAssertEqual(HexDecimal.wei(fromHex: "0xffffffffffffffff"), "18446744073709551615")
        XCTAssertEqual(HexDecimal.wei(fromHex: "0x2386f26fc10000"), "10000000000000000")
        XCTAssertNil(HexDecimal.wei(fromHex: "0xzz"))
        XCTAssertNil(HexDecimal.wei(fromHex: ""))
        XCTAssertEqual(HexDecimal.int(fromHex: "0x1a"), 26)
    }

    // MARK: Esplora (Bitcoin)

    func testMempoolSpaceDecodes() async throws {
        let transport = FixtureTransport(routes: [
            ("/api/address/\(TestVectors.btcLegacyAddress)/txs", "btc_transactions"),
            ("/api/address/\(TestVectors.btcLegacyAddress)", "btc_address"),
            ("/api/v1/prices", "btc_prices"),
        ])
        let provider = try XCTUnwrap(EsploraProvider(host: "https://mempool.space", name: "mempool.space",
                                                     transport: transport))
        let report = try await provider.report(address: TestVectors.btcLegacyAddress,
                                               network: Networks.bitcoin, limit: 10)
        XCTAssertEqual(report.native.raw, "0", "funded and spent sums cancel out in the fixture")
        XCTAssertEqual(report.transactionCount, 48)
        XCTAssertFalse(report.neverUsed)
        XCTAssertEqual(report.activity.count, 2)
        XCTAssertEqual(report.native.usdPrice, Decimal(84536), "the captured BTC/USD rate")
        XCTAssertEqual(report.activity.first?.networkID, "bitcoin")
        XCTAssertNotNil(report.activity.first?.timestamp, "Esplora reports block_time")
    }

    func testEsploraTransactionsDecodeDirection() async throws {
        let transport = FixtureTransport(routes: [
            ("/api/address/\(TestVectors.btcLegacyAddress)/txs", "btc_transactions"),
            ("/api/address/\(TestVectors.btcLegacyAddress)", "btc_address"),
        ])
        let provider = try XCTUnwrap(EsploraProvider(host: "https://mempool.space", name: "mempool.space",
                                                     transport: transport))
        let report = try await provider.report(address: TestVectors.btcLegacyAddress,
                                               network: Networks.bitcoin, limit: 10)
        // The fixture address both receives and spends in these transactions.
        XCTAssertTrue(report.activity.allSatisfy { $0.direction != .unknown })
        XCTAssertTrue(report.activity.allSatisfy { $0.amount >= 0 })
        XCTAssertEqual(report.activity.first?.hash.count, 64)
        XCTAssertEqual(report.activity.first?.symbol, "BTC")
    }

    func testEsploraBalanceArithmetic() async throws {
        // 24 funded outputs and 24 spends of the same total in the fixture ⇒ 0 sats.
        let stats = try EsploraDecoding.address(try Fixtures.data("btc_address"), provider: "test")
        XCTAssertEqual(stats.confirmedBalance, 0)
        XCTAssertEqual(stats.transactionCount, 48)
        XCTAssertEqual(stats.fundedCount, 24)
        XCTAssertEqual(stats.spentCount, 24)

        let segwit = try EsploraDecoding.address(try Fixtures.data("btc_segwit_address"), provider: "test")
        XCTAssertEqual(segwit.transactionCount, 176)
        XCTAssertEqual(segwit.confirmedBalance, 0)
    }

    // MARK: Solana

    func testSolanaBalanceMatchesTheRecordedAccountResponse() async throws {
        let transport = FixtureTransport(routes: [],
                                         postRoutes: [("getBalance", "sol_balance"),
                                                      ("getSignaturesForAddress", "sol_signatures")])
        let provider = SolanaRPCProvider(base: try XCTUnwrap(Networks.solana.explorerAPI),
                                         name: "Solana mainnet-beta", transport: transport)
        let report = try await provider.report(address: TestVectors.solanaAddress, network: Networks.solana)
        XCTAssertEqual(report.native.raw, "0", "the standard mnemonic's Solana account holds nothing")
        XCTAssertEqual(report.native.amount, 0)
        XCTAssertEqual(report.native.decimals, 9)
    }

    func testSolanaSignaturesDecode() async throws {
        let fixture = try XCTUnwrap(try Fixtures.dictionary("sol_signatures")["result"] as? [[String: Any]])
        XCTAssertFalse(fixture.isEmpty, "the busy account fixture must contain signatures")
        let transport = FixtureTransport(routes: [],
                                         postRoutes: [("getBalance", "sol_balance"),
                                                      ("getSignaturesForAddress", "sol_signatures")])
        let provider = SolanaRPCProvider(base: try XCTUnwrap(Networks.solana.explorerAPI),
                                         name: "Solana mainnet-beta", transport: transport)
        let report = try await provider.report(address: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
                                               network: Networks.solana, limit: 2)
        XCTAssertEqual(report.transactionCount, fixture.count)
        XCTAssertEqual(report.activity.count, fixture.count)
        XCTAssertEqual(report.activity.first?.hash, fixture.first?["signature"] as? String)
        XCTAssertEqual(report.activity.first?.hash.count, 88, "base58 signature length")
        let blockTime = try XCTUnwrap((fixture.first?["blockTime"] as? NSNumber)?.doubleValue)
        XCTAssertEqual(report.activity.first?.timestamp?.timeIntervalSince1970 ?? 0, blockTime, accuracy: 0.5)
    }

    // MARK: prices

    func testKrakenTickerDecodes() async throws {
        let transport = FixtureTransport(routes: [("api.kraken.com", "kraken_sol")])
        let source = KrakenPriceSource(transport: transport)
        let prices = try await source.prices(symbols: ["SOL", "NOPE"])
        let fixture = try XCTUnwrap(try Fixtures.dictionary("kraken_sol")["result"] as? [String: Any])
        let pair = try XCTUnwrap(fixture["SOLUSD"] as? [String: Any])
        let close = try XCTUnwrap((pair["c"] as? [String])?.first)
        XCTAssertEqual(prices["SOL"], Decimal(string: close))
        XCTAssertNil(prices["NOPE"], "unknown symbols are skipped, not guessed")
        XCTAssertEqual(source.name, "Kraken")
    }

    func testDecimalParsingNeverUsesBinaryFloats() {
        XCTAssertEqual(DecimalParsing.amount(raw: "1000000000000000000", decimals: 18), 1)
        XCTAssertEqual(DecimalParsing.amount(raw: "1", decimals: 18), Decimal(string: "0.000000000000000001"))
        XCTAssertEqual(DecimalParsing.amount(raw: "1150402", decimals: 8), Decimal(string: "0.01150402"))
        XCTAssertEqual(DecimalParsing.amount(raw: "1000000000", decimals: 9), 1)
        XCTAssertEqual(DecimalParsing.amount(raw: "0", decimals: 18), 0)
        XCTAssertEqual(DecimalParsing.amount(raw: "-2500000000000000000", decimals: 18), Decimal(string: "-2.5"))
        XCTAssertEqual(DecimalParsing.amount(raw: "not a number", decimals: 18), 0)
        XCTAssertEqual(DecimalParsing.amount(raw: "", decimals: 18), 0)
    }

    // MARK: provider registry

    func testRegistryCoversEveryNetworkWithTwoProviders() {
        let registry = ProviderRegistry.live()
        for network in Networks.all {
            let providers = registry.providers(for: network)
            XCTAssertGreaterThanOrEqual(providers.count, 2,
                                        "\(network.name) needs an independent second source")
            XCTAssertEqual(Set(providers.map(\.name)).count, providers.count)
        }
        XCTAssertEqual(registry.providers.count, Networks.evmChains.count * 2 + 4)
        XCTAssertNotNil(registry.priceSource)
    }

    func testEveryProviderHasAVerifiedHTTPSHost() {
        for provider in ProviderRegistry.live().providers {
            XCTAssertFalse(provider.name.isEmpty)
        }
        for network in Networks.all {
            XCTAssertEqual(network.explorerAPI?.scheme, "https", "\(network.id) explorer")
            XCTAssertEqual(network.rpcAPI?.scheme, "https", "\(network.id) second source")
            XCTAssertEqual(network.explorerAddressURL("TEST").hasPrefix("https://"), true)
        }
    }
}
