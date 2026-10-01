import XCTest
@testable import SentinelCore

/// The vault tests come in two flavours: byte-for-byte checks against the Python reference
/// (`ios/docs/vault.json`, copied into `VaultVectors.swift`) and behavioural tests for the
/// things a user actually does — create, unlock, change password, lose the password.
final class VaultTests: XCTestCase {

    // MARK: reference vectors

    func testKeyEncryptionKeyMatchesTheIndependentReference() {
        let kek = Vault.keyEncryptionKey(password: VaultVectors.password,
                                         salt: VaultVectors.salt,
                                         iterations: VaultVectors.iterations)
        XCTAssertEqual(kek, VaultVectors.kek)
        XCTAssertEqual(kek.count, 32)
    }

    func testWrapAADMatchesTheReferenceFormat() {
        let aad = Vault.wrapAAD(iterations: VaultVectors.iterations, salt: VaultVectors.salt)
        XCTAssertEqual(aad, VaultVectors.wrapAAD)
        XCTAssertEqual(String(data: aad.prefix(16), encoding: .utf8), "SentinelVault-v1")
    }

    func testWrappedMasterKeyMatchesTheReference() throws {
        let unlocked = try Vault.create(password: VaultVectors.password,
                                        iterations: VaultVectors.iterations,
                                        salt: VaultVectors.salt,
                                        wrapNonce: VaultVectors.nonce,
                                        masterKey: VaultVectors.masterKey)
        XCTAssertEqual(unlocked.vault.header.wrappedKey, VaultVectors.wrappedMasterCiphertext)
        XCTAssertEqual(unlocked.vault.header.wrapTag, VaultVectors.wrappedMasterTag)
        XCTAssertEqual(unlocked.vault.items.count, 0)
        XCTAssertEqual(unlocked.vault.revision, 1)
    }

    func testItemSealMatchesTheReference() throws {
        var unlocked = try Vault.create(password: VaultVectors.password,
                                        iterations: VaultVectors.iterations,
                                        salt: VaultVectors.salt,
                                        wrapNonce: VaultVectors.nonce,
                                        masterKey: VaultVectors.masterKey)
        let item = try unlocked.add(kind: .mnemonic,
                                    label: "Reference",
                                    hint: "1LqBGSKu…WeabA",
                                    secret: Data(VaultVectors.itemPlaintext.utf8),
                                    id: VaultVectors.itemID,
                                    nonce: VaultVectors.itemNonce)
        XCTAssertEqual(item.ciphertext, VaultVectors.itemCiphertext)
        XCTAssertEqual(item.tag, VaultVectors.itemTag)
        XCTAssertEqual(try unlocked.secret(of: item), Data(VaultVectors.itemPlaintext.utf8))
    }

    func testRawAESGCMAgainstTheReference() throws {
        // The same numbers, this time through the AES shim directly: tag included.
        let sealed = try AESGCM.seal(Data(VaultVectors.itemPlaintext.utf8),
                                     key: VaultVectors.masterKey,
                                     nonce: VaultVectors.itemNonce,
                                     aad: VaultVectors.itemAAD)
        XCTAssertEqual(sealed.ciphertext, VaultVectors.itemCiphertext)
        XCTAssertEqual(sealed.tag, VaultVectors.itemTag)
        XCTAssertEqual(try AESGCM.open(sealed, key: VaultVectors.masterKey, aad: VaultVectors.itemAAD),
                       Data(VaultVectors.itemPlaintext.utf8))
    }

    func testAESGCMRejectsATamperedTagAndWrongKey() throws {
        let sealed = try AESGCM.seal(Data("hello".utf8), key: VaultVectors.masterKey,
                                     nonce: VaultVectors.itemNonce, aad: Data("aad".utf8))
        var broken = sealed
        broken = AESGCM.Sealed(nonce: sealed.nonce,
                               ciphertext: sealed.ciphertext,
                               tag: Data(sealed.tag.dropLast() + [sealed.tag.last! ^ 0x01]))
        XCTAssertThrowsError(try AESGCM.open(broken, key: VaultVectors.masterKey, aad: Data("aad".utf8)))
        XCTAssertThrowsError(try AESGCM.open(sealed, key: Data(repeating: 9, count: 32), aad: Data("aad".utf8)))
        XCTAssertThrowsError(try AESGCM.open(sealed, key: VaultVectors.masterKey, aad: Data("other".utf8)),
                             "the additional data must be authenticated")
        XCTAssertThrowsError(try AESGCM.seal(Data(), key: Data(repeating: 0, count: 16), nonce: sealed.nonce, aad: Data()),
                             "AES-256 keys only")
        XCTAssertThrowsError(try AESGCM.seal(Data(), key: VaultVectors.masterKey, nonce: Data(repeating: 0, count: 8), aad: Data()),
                             "12-byte nonces only")
    }

    // MARK: behaviour

    func testUnlockRoundTripThroughTheEncoder() throws {
        let password = "string of words nobody guesses"
        var unlocked = try Vault.create(password: password, iterations: 1_000)
        let mnemonic = TestVectors.mnemonic
        try unlocked.add(kind: .mnemonic, label: "Main", hint: TestVectors.btcLegacyAddress,
                         secret: Data(mnemonic.utf8))

        let file = try Vault.encode(unlocked.sealed)
        let reopened = try Vault.unlock(try Vault.decode(file), password: password)
        XCTAssertEqual(reopened.itemCount, 1)
        let item = try XCTUnwrap(reopened.vault.items.first)
        XCTAssertEqual(item.kind, .mnemonic)
        XCTAssertEqual(try reopened.secret(of: item), Data(mnemonic.utf8))
        XCTAssertFalse(String(data: file, encoding: .utf8)!.contains("abandon"),
                       "the plaintext phrase must never appear in the file")
    }

    func testWrongPasswordIsRejected() throws {
        let vault = try Vault.create(password: "right", iterations: 1_000).sealed
        XCTAssertThrowsError(try Vault.unlock(vault, password: "wrong")) { error in
            XCTAssertEqual(error as? VaultError, .wrongPassword)
        }
        XCTAssertNoThrow(try Vault.unlock(vault, password: "right"))
    }

    func testTamperedCiphertextIsRejected() throws {
        var unlocked = try Vault.create(password: "pw", iterations: 1_000)
        let item = try unlocked.add(kind: .mnemonic, label: "Main", hint: "hint",
                                    secret: Data("secret material".utf8))
        var vault = unlocked.sealed
        vault.items[0].ciphertext = Data(item.ciphertext.dropLast() + [item.ciphertext.last! ^ 0x01])
        let reopened = try Vault.unlock(vault, password: "pw")
        XCTAssertThrowsError(try reopened.secret(of: vault.items[0])) { error in
            XCTAssertEqual(error as? VaultError, .tamperedItem(id: item.id))
        }

        // The hint and label are metadata, and metadata is allowed to be edited.
        vault.items[0].label = "Renamed"
        XCTAssertNoThrow(try Vault.unlock(vault, password: "pw"))
    }

    func testTamperedHeaderIsRejected() throws {
        var vault = try Vault.create(password: "pw", iterations: 1_000).sealed
        vault.header.iterations = 1_001                       // bound into the AAD
        XCTAssertThrowsError(try Vault.unlock(vault, password: "pw")) { error in
            XCTAssertEqual(error as? VaultError, .wrongPassword)
        }
        var other = try Vault.create(password: "pw", iterations: 1_000).sealed
        other.header.salt = Data(repeating: 7, count: 32)
        XCTAssertThrowsError(try Vault.unlock(other, password: "pw"))
    }

    func testChangePasswordKeepsEveryItemReadable() throws {
        var unlocked = try Vault.create(password: "first", iterations: 1_000)
        let item = try unlocked.add(kind: .privateKey, label: "Imported", hint: "0x9858E…Eda94",
                                    secret: Data(TestVectors.privHex.utf8))
        let sealed = try unlocked.changePassword(to: "second", iterations: 2_000)

        XCTAssertThrowsError(try Vault.unlock(sealed, password: "first"))
        let reopened = try Vault.unlock(sealed, password: "second")
        XCTAssertEqual(reopened.vault.header.iterations, 2_000)
        XCTAssertEqual(try reopened.secret(of: reopened.vault.items[0]), Data(TestVectors.privHex.utf8))
        XCTAssertEqual(try reopened.secret(of: item), Data(TestVectors.privHex.utf8))
    }

    func testRemoveAndRename() throws {
        var unlocked = try Vault.create(password: "pw", iterations: 1_000)
        let a = try unlocked.add(kind: .note, label: "A", hint: "", secret: Data("a".utf8))
        let b = try unlocked.add(kind: .note, label: "B", hint: "", secret: Data("b".utf8))
        XCTAssertEqual(unlocked.vault.revision, 3)
        unlocked.rename(id: b.id, to: "B2")
        XCTAssertEqual(unlocked.vault.items.last?.label, "B2")
        unlocked.remove(id: a.id)
        XCTAssertEqual(unlocked.itemCount, 1)
        unlocked.remove(id: "not-there")
        XCTAssertEqual(unlocked.itemCount, 1)
        XCTAssertThrowsError(try unlocked.secret(of: a), "a removed item has no readable secret") { error in
            XCTAssertEqual(error as? VaultError, .itemRemoved(id: a.id))
        }
        XCTAssertNoThrow(try unlocked.secret(of: b), "the surviving item still reads")
    }

    func testUnsupportedVersionAndMalformedFiles() throws {
        var future = try Vault.create(password: "pw", iterations: 1_000).sealed
        future.header.version = 99
        XCTAssertThrowsError(try Vault.unlock(future, password: "pw")) { error in
            XCTAssertEqual(error as? VaultError, .unsupportedVersion(99))
        }
        XCTAssertThrowsError(try Vault.decode(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? VaultError, .malformed("vault file is not readable"))
        }
        var weird = try Vault.create(password: "pw", iterations: 1_000).sealed
        weird.header.kdf = "scrypt"
        XCTAssertThrowsError(try Vault.unlock(weird, password: "pw"))
    }

    /// End to end: seal the published test phrase, unlock it, and derive the addresses again.
    func testUnlockedPhraseStillDerivesTheReferenceAccounts() throws {
        var unlocked = try Vault.create(password: "a much longer passphrase 42", iterations: 1_000)
        let item = try unlocked.add(kind: .mnemonic, label: "Test vector", hint: TestVectors.btcLegacyAddress,
                                    secret: Data(TestVectors.mnemonic.utf8))
        let payload = String(data: try unlocked.secret(of: item), encoding: .utf8) ?? ""

        let accounts = try Derivation.accounts(for: .mnemonic(phrase: payload, passphrase: ""))
        XCTAssertEqual(accounts.count, 11)
        func address(_ network: String, _ path: String) -> String? {
            accounts.first { $0.network.id == network && $0.path == path }?.address
        }
        XCTAssertEqual(address("bitcoin", TestVectors.btcLegacyPath), TestVectors.btcLegacyAddress)
        XCTAssertEqual(address("bitcoin", TestVectors.btcP2SHPath), TestVectors.btcP2SHAddress)
        XCTAssertEqual(address("bitcoin", TestVectors.btcSegwitPath), TestVectors.btcSegwitAddress)
        XCTAssertEqual(address("bitcoin", TestVectors.btcTaprootPath), TestVectors.btcTaprootAddress)
        XCTAssertEqual(address("ethereum", TestVectors.ethPath), TestVectors.ethAddress)
        XCTAssertEqual(address("solana", TestVectors.solanaPath), TestVectors.solanaAddress)
    }

    func testJSONOnDiskContainsNoPlaintext() throws {
        var unlocked = try Vault.create(password: "pw", iterations: 1_000)
        try unlocked.add(kind: .mnemonic, label: "Main", hint: "hint",
                         secret: Data(TestVectors.mnemonic.utf8))
        let json = try Vault.encode(unlocked.sealed)
        let text = try XCTUnwrap(String(data: json, encoding: .utf8))
        for word in ["abandon", "about", "zoo"] {
            XCTAssertFalse(text.contains(word), "\(word) leaked into the vault file")
        }
        XCTAssertFalse(text.contains(TestVectors.privHex))
        XCTAssertTrue(text.contains("pbkdf2-hmac-sha512"))
    }
}

final class LockoutTests: XCTestCase {
    func testFreeAttemptsDoNotLock() {
        var policy = LockoutPolicy(freeAttempts: 3, baseDelay: 5, maximumDelay: 900)
        let now = Date()
        for _ in 0..<3 {
            policy.recordFailure(now: now)
            XCTAssertFalse(policy.isLocked)
        }
        XCTAssertEqual(policy.attemptsUntilSlowdown, 0)
        policy.recordFailure(now: now)
        XCTAssertTrue(policy.isLocked)
        XCTAssertEqual(policy.remainingLockout(from: now), 5, accuracy: 0.01)
    }

    func testDelayDoublesUpToTheCap() {
        var policy = LockoutPolicy(freeAttempts: 0, baseDelay: 5, maximumDelay: 60)
        let now = Date()
        var seen = [TimeInterval]()
        for _ in 0..<8 {
            policy.recordFailure(now: now)
            seen.append(policy.remainingLockout(from: now))
        }
        XCTAssertEqual(seen, [5, 10, 20, 40, 60, 60, 60, 60].map { $0 })
    }

    func testSuccessClearsTheLockout() {
        var policy = LockoutPolicy(freeAttempts: 0, baseDelay: 5)
        policy.recordFailure()
        XCTAssertTrue(policy.isLocked)
        policy.recordSuccess()
        XCTAssertFalse(policy.isLocked)
        XCTAssertEqual(policy.failedAttempts, 0)
        XCTAssertNil(policy.describeLockout())
    }

    func testLockoutCopy() {
        var policy = LockoutPolicy(freeAttempts: 0, baseDelay: 1, maximumDelay: 900)
        let now = Date()
        policy.recordFailure(now: now)
        XCTAssertEqual(policy.describeLockout(from: now), "Try again in 1 second")
        var long = LockoutPolicy(freeAttempts: 0, baseDelay: 130, maximumDelay: 900)
        long.recordFailure(now: now)
        XCTAssertEqual(long.describeLockout(from: now), "Try again in 2 min 10 s")
        var exact = LockoutPolicy(freeAttempts: 0, baseDelay: 120, maximumDelay: 900)
        exact.recordFailure(now: now)
        XCTAssertEqual(exact.describeLockout(from: now), "Try again in 2 minutes")
    }
}
