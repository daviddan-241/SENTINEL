import XCTest
@testable import SentinelCore

/// Every assertion here is a published test vector: NIST for the hashes, BIP-39/BIP-32/
/// BIP-44/BIP-49/BIP-84/BIP-86 for the wallet maths, BIP-173 for bech32, EIP-55 for
/// Ethereum addresses. Two independent implementations produced these numbers — a pure
/// Python reference (tools/vectors.py) and the standards' own documents.
final class CryptoTests: XCTestCase {

    // MARK: word list

    func testWordListIsTheCanonicalBIP39List() {
        XCTAssertEqual(BIP39Wordlist.words.count, 2048)
        XCTAssertEqual(Set(BIP39Wordlist.words).count, 2048, "duplicate words")
        XCTAssertEqual(BIP39Wordlist.words, BIP39Wordlist.words.sorted(), "list must be sorted")
        XCTAssertEqual(BIP39Wordlist.words.first, TestVectors.wordlistFirst)
        XCTAssertEqual(BIP39Wordlist.words.last, TestVectors.wordlistLast)
        XCTAssertEqual(BIP39Wordlist.indexOf["about"], TestVectors.indexAbout)
        XCTAssertTrue(BIP39Wordlist.isCanonical(), "sha256 of the list does not match the reference")
    }

    // MARK: hashes

    func testSHA256Vectors() {
        for (input, expected) in TestVectors.sha256 {
            XCTAssertEqual(SHA256.hash(Data(input.utf8)).hexString, expected, "sha256(\(input))")
        }
        // the SENTINEL reference value used across both projects
        XCTAssertEqual(SHA256.hash(Data("abc".utf8)).hexString,
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testSHA512Vectors() {
        for (input, expected) in TestVectors.sha512 {
            XCTAssertEqual(SHA512.hash(Data(input.utf8)).hexString, expected, "sha512(\(input.prefix(12)))")
        }
    }

    func testKeccak256Vectors() {
        for (input, expected) in TestVectors.keccak {
            XCTAssertEqual(Keccak256.hash(Data(input.utf8)).hexString, expected, "keccak256(\(input))")
        }
    }

    func testRIPEMD160Vectors() {
        for (input, expected) in TestVectors.ripemd {
            XCTAssertEqual(RIPEMD160.hash(Data(input.utf8)).hexString, expected, "ripemd160(\(input))")
        }
    }

    /// Regression: Data slices keep the parent's start index, which used to read out of
    /// bounds inside the Keccak absorber.
    func testHashesAcceptDataSlices() {
        let buffer = Data([0xff, 0xfe]) + Data("abc".utf8) + Data([0x00])
        let slice = buffer[2..<5]
        XCTAssertEqual(SHA256.hash(slice).hexString, SHA256.hash(Data("abc".utf8)).hexString)
        XCTAssertEqual(SHA512.hash(slice).hexString, SHA512.hash(Data("abc".utf8)).hexString)
        XCTAssertEqual(RIPEMD160.hash(slice).hexString, RIPEMD160.hash(Data("abc".utf8)).hexString)
        XCTAssertEqual(Keccak256.hash(slice).hexString, Keccak256.hash(Data("abc".utf8)).hexString)
        XCTAssertEqual(SHA256.hash(Data("abcdef".utf8).dropLast()).hexString,
                       SHA256.hash(Data("abcde".utf8)).hexString)
    }

    func testHMACSHA512() {
        let key = Data(repeating: 0x0b, count: 20)
        let mac = HMAC.authenticate(.sha512, key: key, message: Data("Hi There".utf8))
        XCTAssertEqual(mac.hexString,
                       "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854")
    }

    func testPBKDF2Vectors() {
        for testCase in TestVectors.pbkdf2Cases {
            let derived = PBKDF2.derive(algorithm: .sha512,
                                        password: Data(testCase.password.utf8),
                                        salt: Data(testCase.salt.utf8),
                                        iterations: testCase.iterations,
                                        keyLength: testCase.length)
            XCTAssertEqual(derived.hexString, testCase.out,
                           "pbkdf2(\(testCase.iterations) rounds, \(testCase.length) bytes)")
        }
    }

    // MARK: base58 / bech32

    func testBase58CheckRoundTripAndVector() {
        let vector = TestVectors.base58check
        let payload = Data([UInt8(vector.version, radix: 16)!]) + Data(hex: vector.payload)!
        XCTAssertEqual(Base58.encodeCheck(payload), vector.out)
        XCTAssertEqual(Base58.decodeCheck(vector.out)?.hexString, payload.hexString)
        XCTAssertNil(Base58.decodeCheck(String(vector.out.dropLast()) + "1"), "bad checksum must fail")
    }

    func testBech32ReferenceVectors() {
        for address in TestVectors.bech32Valid {
            XCTAssertNotNil(Bech32.decode(address), "should decode: \(address.prefix(24))")
        }
        for address in TestVectors.bech32Invalid {
            XCTAssertNil(Bech32.decode(address), "should reject: \(address.prefix(24))")
        }
        XCTAssertEqual(Bech32.decode("A12UEL5L")?.variant, .bech32)
    }

    func testSegwitAddressRoundTrip() {
        // The two published encodings of a 20-byte witness v0 program (BIP-173 test vectors).
        let zeros = Data(repeating: 0x00, count: 20)
        XCTAssertEqual(Bech32.encodeSegwit(hrp: "bc", version: 0, program: zeros),
                       "bc1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9e75rs")
        let elevens = Data(repeating: 0x11, count: 20)
        XCTAssertEqual(Bech32.encodeSegwit(hrp: "bc", version: 0, program: elevens),
                       "bc1qzyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3h8ffkz")

        for program in [zeros, elevens] {
            let address = Bech32.encodeSegwit(hrp: "bc", version: 0, program: program)
            XCTAssertEqual(Bech32.decodeSegwit(address)?.program, program)
            XCTAssertEqual(Bech32.decodeSegwit(address)?.version, 0)
            XCTAssertEqual(Bech32.decodeSegwit(address)?.hrp, "bc")
        }

        // Witness v1 is bech32m (BIP-350): this is the BIP-86 taproot address the vault derives.
        let taproot = Bech32.decodeSegwit(TestVectors.btcTaprootAddress)
        XCTAssertEqual(taproot?.version, 1)
        XCTAssertEqual(taproot?.program.hexString, TestVectors.btcTaprootOutputKey)
        let v1 = Bech32.encodeSegwit(hrp: "bc", version: 1, program: Data(repeating: 0x22, count: 32))
        XCTAssertEqual(Bech32.decodeSegwit(v1)?.program, Data(repeating: 0x22, count: 32))

        XCTAssertNil(Bech32.decodeSegwit("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sL5k7"),
                     "mixed case must be rejected")
        XCTAssertNil(Bech32.decodeSegwit("bc1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq9e75rs" + String(repeating: "q", count: 40)),
                     "a segwit address is at most 90 characters")
        XCTAssertNil(Bech32.decodeSegwit("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5"),
                     "a bad checksum must be rejected")
    }

    // MARK: secp256k1

    func testGeneratorAndDoubling() {
        let one = UInt256(1)
        guard let g = Secp256k1.multiplyGenerator(one) else { return XCTFail("1·G failed") }
        XCTAssertEqual(Secp256k1.compressed(g).hexString,
                       "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
        guard let two = Secp256k1.multiplyGenerator(UInt256(2)) else { return XCTFail("2·G failed") }
        XCTAssertEqual(Secp256k1.compressed(two).hexString,
                       "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5")
    }

    func testMultiplyMatchesKnownScalarProducts() {
        // n−1 · G is −G, so the compressed key flips to the odd prefix with the same x
        let nMinusOne = Secp256k1.n.subtracting(UInt256(1)).value
        guard let point = Secp256k1.multiplyGenerator(nMinusOne) else { return XCTFail("(n−1)·G failed") }
        XCTAssertEqual(Secp256k1.compressed(point).hexString,
                       "0379be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
        XCTAssertNil(Secp256k1.multiplyGenerator(Secp256k1.n), "n·G must be rejected")
        XCTAssertNil(Secp256k1.multiplyGenerator(UInt256(0)), "0·G must be rejected")
    }

    func testLiftXRoundTrip() {
        for scalar in [UInt64(7), 999983, 1234567890123] {
            guard let point = Secp256k1.multiplyGenerator(UInt256(scalar)) else { continue }
            guard let lifted = Secp256k1.liftX(point.x) else { return XCTFail("lift_x failed") }
            XCTAssertEqual(lifted.x, point.x)
            XCTAssertFalse(lifted.y.isOdd, "lift_x returns the even-y point")
            // and parsing the compressed key gets back to the original point
            guard let parsed = Secp256k1.parseCompressed(Secp256k1.compressed(point)) else {
                return XCTFail("parseCompressed failed")
            }
            XCTAssertEqual(parsed, point)
        }
    }

    func testModularArithmeticConsistency() {
        // (a·b) mod p computed by the field code must agree with a·b mod p from adding
        let a = UInt256(Data(hex: "00000000000000000000000000000000000000000000000000000000deadbeef")!)
        let b = UInt256(Data(hex: "0000000000000000000000000000000000000000000000000000000012345678")!)

        let product = a.multipliedFullWidth(by: b)
        XCTAssertTrue(product.high.isZero)
        XCTAssertEqual(product.low.hexString,
                       "0000000000000000000000000000000000000000000000000fd5bdee5621ca08")

        // Full width: (2^256 − 1)^2 = 2^512 − 2^257 + 1 → high = 2^256 − 2, low = 1.
        let max = UInt256(Data(repeating: 0xff, count: 32))
        let wide = max.multipliedFullWidth(by: max)
        XCTAssertEqual(wide.low, UInt256(1))
        XCTAssertEqual(wide.high.hexString,
                       "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe")

        // Carry and borrow across the limb boundaries.
        let carried = max.adding(UInt256(1))
        XCTAssertEqual(carried.value, UInt256(0))
        XCTAssertEqual(carried.carry, 1)
        let borrowed = UInt256(0).subtracting(UInt256(1))
        XCTAssertEqual(borrowed.value, max)
        XCTAssertEqual(borrowed.borrow, 1)
        let lowLimbFull = UInt256(l0: 0xffff_ffff_ffff_ffff, l1: 0, l2: 0, l3: 0)
        let limbCarry = lowLimbFull.adding(UInt256(1))
        XCTAssertEqual(limbCarry.value, UInt256(l0: 0, l1: 1, l2: 0, l3: 0))
        XCTAssertEqual(limbCarry.carry, 0)

        // inverse: a · a⁻¹ ≡ 1
        let inverse = Secp256k1.inverse(a)
        XCTAssertEqual(Secp256k1.mulModP(a, inverse), UInt256(1))
    }

    // MARK: BIP-39

    func testBIP39SeedVectors() {
        XCTAssertEqual(BIP39.seed(phrase: TestVectors.mnemonic, passphrase: TestVectors.passphrase).hexString,
                       TestVectors.seedTrezor)
        XCTAssertEqual(BIP39.seed(phrase: TestVectors.mnemonic).hexString, TestVectors.seedNoPassphrase)
    }

    func testBIP39ValidationCases() {
        for testCase in TestVectors.phraseCases {
            let result = BIP39.validate(testCase.phrase)
            XCTAssertEqual(result.isValid, testCase.valid, "\(testCase.phrase.prefix(30))… → \(result)")
        }
        XCTAssertEqual(BIP39.validate(""), .empty)
        XCTAssertEqual(BIP39.validate("abandon about"), .wrongWordCount(2))
        if case .unknownWords(let words) = BIP39.validate("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon zzzz") {
            XCTAssertEqual(words, ["zzzz"])
        } else {
            XCTFail("unknown word not reported")
        }
    }

    func testBIP39ToleratesMessyInput() {
        let messy = "  1. abandon  2. abandon\n3. abandon, 4. abandon; 5. abandon 6. abandon 7. abandon 8. abandon 9. abandon 10. abandon 11. abandon 12. about "
        XCTAssertTrue(BIP39.validate(messy).isValid, "paste from a numbered note should still validate")
    }

    func testBIP39Suggestions() {
        let suggestions = BIP39.suggestions(for: "abandonn")
        XCTAssertEqual(suggestions.first, "abandon")
        XCTAssertTrue(BIP39.suggestions(for: "zooo").contains("zoo"))
    }

    // MARK: BIP-32

    func testBIP32MasterFromSeed() throws {
        let master = try ExtendedPrivateKey.master(seed: Data(hex: TestVectors.bip32Seed1)!)
        XCTAssertEqual(master.privateKey.hexString, TestVectors.bip32MasterPrivHex)
        XCTAssertEqual(master.chainCode.hexString, TestVectors.bip32MasterChainCode)
        XCTAssertEqual(master.serialized, TestVectors.bip32MasterXprv)
        XCTAssertEqual(master.publicSerialized, TestVectors.bip32MasterXpub)
    }

    func testBIP32ChildChainUsesPublishedVectors() throws {
        let master = try ExtendedPrivateKey.master(seed: Data(hex: TestVectors.bip32Seed1)!)
        var key = master
        for (path, expectedXprv, expectedXpub) in TestVectors.bip32DeepChain {
            let last = path.split(separator: "/").last!
            let indexText = last.hasSuffix("'") ? String(last.dropLast()) : String(last)
            var index = UInt32(indexText)!
            if last.hasSuffix("'") { index += 0x8000_0000 }
            key = try key.child(index)
            XCTAssertEqual(key.serialized, expectedXprv, "xprv at \(path)")
            XCTAssertEqual(key.publicSerialized, expectedXpub, "xpub at \(path)")
        }
        XCTAssertEqual(BIP32Path.describe([0x8000_0000, 1, 0x8000_0002]), "m/0'/1/2'")
    }

    func testBIP32VectorTwo() throws {
        let seed = Data(hex: "fffcf9f6f3f0edeae7e4e1dedbd8d5d2cfccc9c6c3c0bdbab7b4b1aeaba8a5a29f9c999693908d8a8784817e7b7875726f6c696663605d5a5754514e4b484542")!
        let master = try ExtendedPrivateKey.master(seed: seed)
        XCTAssertEqual(master.publicSerialized, TestVectors.bip32Vector2MasterXpub)
    }

    func testPathParsing() throws {
        XCTAssertEqual(try BIP32Path.components(of: "m/44'/60'/0'/0/0"),
                       [0x8000_002c, 0x8000_003c, 0x8000_0000, 0, 0])
        XCTAssertEqual(try BIP32Path.components(of: "M/84h/0h/0h/0/0"),
                       [0x8000_0054, 0x8000_0000, 0x8000_0000, 0, 0])
        XCTAssertEqual(try BIP32Path.components(of: "m"), [])
        XCTAssertEqual(try BIP32Path.components(of: "m/0/1"), [0, 1])
        XCTAssertThrowsError(try BIP32Path.components(of: "m/44//0"), "empty component")
        XCTAssertThrowsError(try BIP32Path.components(of: "m/2147483648"), "beyond the hardened range")
        XCTAssertThrowsError(try BIP32Path.components(of: "m/-1"))
        XCTAssertThrowsError(try BIP32Path.components(of: "m/x"))
        XCTAssertThrowsError(try BIP32Path.components(of: "m/"))
        XCTAssertThrowsError(try BIP32Path.components(of: "44/60"), "relative paths are not accepted")
        XCTAssertThrowsError(try BIP32Path.components(of: ""))
        XCTAssertEqual(BIP32Path.describe([0x8000_002c, 0x8000_003c, 0, 0, 0]), "m/44'/60'/0/0/0")
    }

    // MARK: addresses

    func testAddressVectorsFromTheStandardMnemonic() throws {
        let seed = BIP39.seed(phrase: TestVectors.mnemonic)
        let master = try ExtendedPrivateKey.master(seed: seed)

        let legacy = try master.derive(path: TestVectors.btcLegacyPath)
        XCTAssertEqual(Address.p2pkh(from: legacy.publicKey), TestVectors.btcLegacyAddress)

        let wrapped = try master.derive(path: TestVectors.btcP2SHPath)
        XCTAssertEqual(Address.p2shP2wpkh(from: wrapped.publicKey), TestVectors.btcP2SHAddress)

        let segwitVersion = Derivation.versionPrefix(for: .bip84)!
        let segwit = try master.derive(path: TestVectors.btcSegwitPath, version: segwitVersion)
        XCTAssertEqual(Address.p2wpkh(from: segwit.publicKey), TestVectors.btcSegwitAddress)
        XCTAssertEqual(Address.hash160(Secp256k1.compressed(segwit.publicKey)).hexString, TestVectors.bip84Hash160)

        let taproot = try master.derive(path: TestVectors.btcTaprootPath)
        XCTAssertEqual(Address.p2tr(from: taproot.publicKey), TestVectors.btcTaprootAddress)

        let evm = try master.derive(path: TestVectors.ethPath)
        XCTAssertEqual(Address.ethereum(from: evm.publicKey), TestVectors.ethAddress)

        // SLIP-132 account-level prefixes match the BIP-84 spec
        let account = try master.derive(path: "m/84'/0'/0'", version: segwitVersion)
        XCTAssertEqual(account.serialized, TestVectors.bip84AccountXprv)
        XCTAssertEqual(account.publicSerialized, TestVectors.bip84AccountXpub)
    }

    func testSolanaVector() throws {
        let seed = BIP39.seed(phrase: TestVectors.mnemonic)
        let master = try ExtendedPrivateKey.master(seed: seed)
        let key = try master.derive(path: TestVectors.solanaPath)
        XCTAssertEqual(Address.solana(fromSeed: key.privateKey.data), TestVectors.solanaAddress)
    }

    func testEIP55Checksum() {
        let lower = "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"
        XCTAssertEqual("0x" + Address.checksum(String(lower.dropFirst(2))),
                       "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
        let allCaps = "0x8617E340B3D01FA5F11F306F4090FD50E238070D"
        XCTAssertEqual("0x" + Address.checksum(allCaps.dropFirst(2).lowercased()),
                       allCaps)
    }

    func testAddressClassification() {
        XCTAssertEqual(Address.classify(TestVectors.ethAddress), .evm)
        XCTAssertEqual(Address.classify(TestVectors.btcLegacyAddress), .bitcoinP2PKH)
        XCTAssertEqual(Address.classify(TestVectors.btcP2SHAddress), .bitcoinP2SH)
        XCTAssertEqual(Address.classify(TestVectors.btcSegwitAddress), .bitcoinSegwit)
        XCTAssertEqual(Address.classify(TestVectors.btcTaprootAddress), .bitcoinTaproot)
        XCTAssertEqual(Address.classify(TestVectors.solanaAddress), .solana)
        XCTAssertNil(Address.classify("not an address"))
        XCTAssertNil(Address.classify("0x1234"))
    }

    func testShorten() {
        XCTAssertEqual(Address.shorten(TestVectors.ethAddress), "0x9858E…Eda94")
        XCTAssertEqual(Address.shorten(TestVectors.ethAddress, leading: 6, trailing: 4), "0x9858…da94")
        XCTAssertEqual(Address.shorten("short"), "short")
        XCTAssertEqual(Address.shorten(""), "")
        XCTAssertEqual(Address.shorten(TestVectors.btcSegwitAddress, leading: 10, trailing: 6),
                       "bc1qcr8te4…306fyu")
    }

    // MARK: credentials

    func testWIFImport() {
        // "5…" is the uncompressed mainnet form, "K…"/"L…" the compressed one.
        guard let plain = PrivateKeyImport.parseWIF(TestVectors.wif) else { return XCTFail("WIF rejected") }
        XCTAssertEqual(plain.key.hexString, TestVectors.privHex)
        XCTAssertFalse(plain.compressed)
        XCTAssertTrue(plain.mainnet)

        guard let compressed = PrivateKeyImport.parseWIF(TestVectors.wifCompressed) else {
            return XCTFail("compressed WIF rejected")
        }
        XCTAssertEqual(compressed.key.hexString, TestVectors.privHex)
        XCTAssertTrue(compressed.compressed)
        XCTAssertTrue(compressed.mainnet)

        // testnet prefix 0xef, the same scalar
        let testnetPayload = Data([0xef]) + Data(hex: TestVectors.privHex)! + Data([0x01])
        let testnet = Base58.encodeCheck(testnetPayload)
        XCTAssertEqual(PrivateKeyImport.parseWIF(testnet)?.mainnet, false)
        XCTAssertEqual(PrivateKeyImport.parseWIF(testnet)?.compressed, true)

        XCTAssertNil(PrivateKeyImport.parseWIF(String(TestVectors.wif.dropLast()) + "1"), "checksum must be verified")
        XCTAssertNil(PrivateKeyImport.parseWIF("not a key"))
        XCTAssertNil(PrivateKeyImport.parseWIF(Base58.encodeCheck(Data([0x80]) + Data(repeating: 0, count: 32))),
                     "zero is not a valid scalar")
        XCTAssertNil(PrivateKeyImport.parse(String(repeating: "0", count: 64)), "zero is not a valid scalar")
        XCTAssertNil(PrivateKeyImport.parse(String(repeating: "f", count: 64)), "n and above are not scalars")
        XCTAssertEqual(PrivateKeyImport.parse(TestVectors.privHex)?.key.hexString, TestVectors.privHex)
    }

    func testRawHexImport() {
        guard let parsed = PrivateKeyImport.parse(TestVectors.privHex) else { return XCTFail("hex key rejected") }
        XCTAssertEqual(parsed.key.hexString, TestVectors.privHex)
        XCTAssertNil(PrivateKeyImport.parse("0xdeadbeef"), "short keys are rejected")
        XCTAssertNil(PrivateKeyImport.parse(String(repeating: "0", count: 64)), "zero key is rejected")
        XCTAssertNil(PrivateKeyImport.parse(String(repeating: "f", count: 64)), "key ≥ n is rejected")
    }

    func testDerivationProducesEveryNetwork() throws {
        let accounts = try Derivation.accounts(for: .mnemonic(phrase: TestVectors.mnemonic, passphrase: ""))
        // six EVM chains + four Bitcoin address styles + Solana
        XCTAssertEqual(accounts.count, 11)
        XCTAssertEqual(Set(accounts.map(\.network.id)),
                       ["ethereum", "base", "arbitrum", "optimism", "polygon", "gnosis", "bitcoin", "solana"])
        XCTAssertEqual(Derivation.primaryAddress(of: accounts, network: Networks.ethereum), TestVectors.ethAddress)
        XCTAssertEqual(Derivation.primaryAddress(of: accounts, network: Networks.bitcoin), TestVectors.btcSegwitAddress)
        XCTAssertEqual(Derivation.primaryAddress(of: accounts, network: Networks.solana), TestVectors.solanaAddress)
        // all six EVM chains share one address
        XCTAssertEqual(Set(accounts.filter { $0.network.kind == .evm }.map(\.address)).count, 1)
        // every Bitcoin style has its own address
        XCTAssertEqual(Set(accounts.filter { $0.network.kind == .bitcoin }.map(\.address)).count, 4)
    }

    func testDerivationRejectsBadMnemonic() {
        XCTAssertThrowsError(try Derivation.accounts(for: .mnemonic(phrase: String(repeating: "abandon ", count: 12), passphrase: "")))
        XCTAssertThrowsError(try Derivation.accounts(for: .mnemonic(phrase: "hello world", passphrase: "")))
    }
}
