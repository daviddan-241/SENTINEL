import SwiftUI
import Combine

/// One wallet as the UI knows it: a vault item plus the addresses derived from it.
struct WalletSummary: Identifiable, Equatable {
    let id: String
    let label: String
    let kind: VaultKind
    let hint: String
    let createdAt: Date
    let accounts: [DerivedAccount]
    let item: VaultItem

    var addressCount: Int { accounts.count }
    var primaryAddress: String? { accounts.first(where: \.isPrimary)?.address }

    static func == (a: WalletSummary, b: WalletSummary) -> Bool {
        a.id == b.id && a.label == b.label && a.accounts.count == b.accounts.count
    }
}

/// What a running scan is doing, for the progress UI.
struct ScanProgress: Equatable {
    var total: Int = 0
    var finished: Int = 0
    var currentNetwork: String = ""
    var startedAt: Date?

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(finished) / Double(total))
    }

    var isRunning: Bool { startedAt != nil }
}

struct AppSettings: Codable, Equatable {
    var hideFlaggedTokens: Bool = true
    var autoLockOnBackground: Bool = true
    var requireBiometricsForReveal: Bool = true
    var activityLimit: Int = 8

    static let `default` = AppSettings()
}

@MainActor
final class AppState: ObservableObject {
    // vault
    @Published private(set) var hasVault = false
    @Published private(set) var unlocked: UnlockedVault?
    @Published private(set) var wallets: [WalletSummary] = []
    @Published var lockout = LockoutPolicy()

    // portfolio
    @Published private(set) var portfolio: Portfolio = .empty
    @Published private(set) var history: [ScanSnapshot] = []
    @Published private(set) var progress = ScanProgress()
    @Published private(set) var lastScanDate: Date?
    @Published var settings = AppSettings.default { didSet { persistSettings() } }

    // transient UI
    @Published var toast: Toast?
    @Published var isDrawerOpen = false
    @Published var isWorking = false
    @Published var lastFailure: String?

    // lookup tab
    @Published var lookupInput = ""
    @Published var lookupResult: AddressReport?
    @Published var lookupBusy = false

    private let vaultStore: VaultStore
    private let portfolioStore: PortfolioStore
    private let scanner: PortfolioScanner
    private let registry: ProviderRegistry
    private let transport: URLSessionTransport
    private var toastTask: Task<Void, Never>?

    init(vaultStore: VaultStore = .default(),
         portfolioStore: PortfolioStore = .default(),
         transport: URLSessionTransport = URLSessionTransport(),
         scanner: PortfolioScanner? = nil) {
        self.vaultStore = vaultStore
        self.portfolioStore = portfolioStore
        self.transport = transport
        let registry = ProviderRegistry.live(transport: transport)
        self.registry = registry
        self.scanner = scanner ?? PortfolioScanner(registry: registry)
        self.hasVault = vaultStore.exists
        loadSettings()
        loadStoredScans()
    }

    var isLocked: Bool { unlocked == nil }
    var walletCount: Int { wallets.count }
    var addressCount: Int { wallets.reduce(0) { $0 + $1.addressCount } }

    var visibleReports: [AddressReport] {
        portfolio.reports
    }

    var flaggedTokenCount: Int { portfolio.flaggedTokenCount }

    // MARK: vault lifecycle

    func createVault(password: String) {
        do {
            let vault = try Vault.create(password: password)
            try vaultStore.save(vault.sealed)
            unlocked = vault
            hasVault = true
            refreshWallets()
            show(.init(kind: .success, title: "Vault created", message: "Your recovery phrase is encrypted with AES-256-GCM."))
        } catch {
            show(.init(kind: .failure, title: "Could not create the vault", message: error.localizedDescription))
        }
    }

    func unlock(password: String) {
        guard !lockout.isLocked else { return }
        do {
            let stored = try vaultStore.load()
            guard let stored else {
                hasVault = false
                return
            }
            let opened = try Vault.unlock(stored, password: password)
            unlocked = opened
            hasVault = true
            lockout.recordSuccess()
            refreshWallets()
        } catch let error as VaultError where error == .wrongPassword {
            lockout.recordFailure()
            let message = lockout.describeLockout()
            show(.init(kind: .failure, title: "Wrong password", message: message))
        } catch {
            show(.init(kind: .failure, title: "Could not open the vault", message: error.localizedDescription))
        }
    }

    func lock() {
        unlocked = nil
        wallets = []
        objectWillChange.send()
    }

    func deleteVault() {
        do {
            try vaultStore.delete()
            try portfolioStore.clear()
            unlocked = nil
            hasVault = false
            wallets = []
            portfolio = .empty
            history = []
            show(.init(kind: .info, title: "Vault deleted", message: "The file is gone; the key material went with it."))
        } catch {
            show(.init(kind: .failure, title: "Could not delete the vault", message: error.localizedDescription))
        }
    }

    // MARK: wallets

    /// Adds a phrase or a private key. Validation happens in the core, so the UI cannot
    /// accept something the crypto layer would reject.
    func addWallet(kind: VaultKind, label: String, secret: String,
                   passphrase: String = "") -> Bool {
        guard var vault = unlocked else { return false }
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let hint: String
        switch kind {
        case .mnemonic:
            let result = BIP39.validate(trimmed)
            guard result == .valid else {
                show(.init(kind: .failure, title: "That phrase is not valid", message: result.explanation))
                return false
            }
            guard let first = try? Derivation.accounts(for: .mnemonic(phrase: trimmed, passphrase: passphrase)).first else {
                show(.init(kind: .failure, title: "Could not derive addresses", message: nil))
                return false
            }
            hint = first.address
        case .privateKey:
            guard let parsed = PrivateKeyImport.parse(trimmed) else {
                show(.init(kind: .failure, title: "That key is not valid",
                           message: "It is not a 32-byte hex key or a WIF key."))
                return false
            }
            guard let first = try? Derivation.accounts(for: .privateKey(parsed)).first else {
                show(.init(kind: .failure, title: "Could not derive addresses", message: nil))
                return false
            }
            hint = first.address
        case .passphrase, .note:
            hint = String(trimmed.prefix(6)) + "…"
        }

        do {
            // The passphrase is sealed as its own item and referenced by label, so the phrase
            // itself never has to be stored with it.
            try vault.add(kind: kind, label: label, hint: hint, secret: Data(trimmed.utf8))
            if kind == .mnemonic, !passphrase.isEmpty {
                try vault.add(kind: .passphrase, label: "\(label) passphrase", hint: "",
                              secret: Data(passphrase.utf8))
            }
            try vaultStore.save(vault.sealed)
            unlocked = vault
            refreshWallets()
            show(.init(kind: .success, title: "Wallet added", message: "\(label) is encrypted and ready to scan."))
            return true
        } catch {
            show(.init(kind: .failure, title: "Could not save", message: error.localizedDescription))
            return false
        }
    }

    func deleteWallet(id: String) {
        guard var vault = unlocked else { return }
        vault.remove(id: id)
        do {
            try vaultStore.save(vault.sealed)
            unlocked = vault
            refreshWallets()
            show(.init(kind: .info, title: "Wallet removed"))
        } catch {
            show(.init(kind: .failure, title: "Could not save", message: error.localizedDescription))
        }
    }

    func renameWallet(id: String, to label: String) {
        guard var vault = unlocked else { return }
        vault.rename(id: id, to: label)
        do {
            try vaultStore.save(vault.sealed)
            unlocked = vault
            refreshWallets()
        } catch {
            show(.init(kind: .failure, title: "Could not save", message: error.localizedDescription))
        }
    }

    /// Reads a secret out of the vault. The password (or biometry) is required every time.
    func reveal(item: VaultItem, password: String, biometricsAlreadyChecked: Bool = false) -> String? {
        guard let vault = unlocked else { return nil }
        if !biometricsAlreadyChecked {
            do {
                let check = try Vault.unlock(vault.sealed, password: password)
                _ = check
            } catch {
                lockout.recordFailure()
                show(.init(kind: .failure, title: "Wrong password", message: lockout.describeLockout()))
                return nil
            }
        }
        do {
            let data = try vault.secret(of: item)
            lockout.recordSuccess()
            return String(data: data, encoding: .utf8)
        } catch {
            show(.init(kind: .failure, title: "Could not read that item", message: nil))
            return nil
        }
    }

    private func refreshWallets() {
        guard let vault = unlocked else {
            wallets = []
            return
        }
        var summaries: [WalletSummary] = []
        for item in vault.vault.items where item.kind == .mnemonic || item.kind == .privateKey {
            guard let secret = try? vault.secret(of: item),
                  let text = String(data: secret, encoding: .utf8) else { continue }
            let credential: Credential
            if item.kind == .mnemonic {
                let passphrase = passphraseFor(walletID: item.id, label: item.label) ?? ""
                credential = .mnemonic(phrase: text, passphrase: passphrase)
            } else if let parsed = PrivateKeyImport.parse(text) {
                // Credential.privateKey carries the raw scalar; the compressed/mainnet flags
                // only matter for how the imported key is *labelled*.
                credential = .privateKey(parsed.key.data)
            } else {
                continue
            }
            guard let accounts = try? Derivation.accounts(for: credential) else { continue }
            summaries.append(WalletSummary(id: item.id, label: item.label, kind: item.kind,
                                           hint: item.hint, createdAt: item.createdAt,
                                           accounts: accounts, item: item))
        }
        wallets = summaries.sorted { $0.createdAt < $1.createdAt }
    }

    private func passphraseFor(walletID: String, label: String) -> String? {
        guard let vault = unlocked else { return nil }
        let expected = "\(label) passphrase"
        guard let item = vault.vault.items.first(where: { $0.kind == .passphrase && $0.label == expected }),
              let data = try? vault.secret(of: item) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: scanning

    func scanAll() {
        guard !wallets.isEmpty else {
            show(.init(kind: .info, title: "Nothing to scan yet", message: "Add a wallet first."))
            return
        }
        guard !progress.isRunning else { return }

        let inputs = wallets.flatMap { wallet in
            wallet.accounts.map { ScanInput(walletID: wallet.id, walletLabel: wallet.label, account: $0) }
        }
        progress = ScanProgress(total: inputs.count, finished: 0, currentNetwork: "", startedAt: Date())
        lastFailure = nil

        Task {
            let result = await scanner.scan(inputs, activityLimit: self.settings.activityLimit)
            await MainActor.run {
                self.portfolio = result
                self.progress = ScanProgress()
                self.lastScanDate = result.scannedAt
                if let failure = result.failures.first {
                    self.lastFailure = failure
                }
                do {
                    let stored = try self.portfolioStore.record(result)
                    self.history = stored.history
                } catch {
                    self.show(.init(kind: .failure, title: "Scan worked, saving did not", message: error.localizedDescription))
                }
                let funded = result.fundedReports.count
                self.show(.init(kind: funded > 0 ? .success : .info,
                                title: funded > 0 ? "Scan complete" : "Scan complete — nothing funded",
                                message: funded > 0
                                    ? "\(funded) of \(result.reports.count) addresses hold something."
                                    : "All \(result.reports.count) addresses are empty or untouched."))
            }
        }
    }

    func lookup() {
        let text = lookupInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let network = Networks.all.first(where: { candidate in
            guard let kind = Address.classify(text) else { return false }
            switch candidate.kind {
            case .evm: return kind == .evm
            case .bitcoin: return kind != .evm && kind != .solana
            case .solana: return kind == .solana
            }
        }) else {
            lookupResult = nil
            show(.init(kind: .failure, title: "Not a wallet address",
                       message: "Sentinel reads EVM, Bitcoin and Solana addresses."))
            return
        }
        lookupBusy = true
        Task {
            let report = await scanner.lookup(address: text, network: network)
            await MainActor.run {
                self.lookupResult = report
                self.lookupBusy = false
            }
        }
    }

    // MARK: clipboard, settings, scan history

    func copy(_ value: String, label: String, isSecret: Bool = false) {
        Task {
            await ClipboardGuard.shared.copy(value)
        }
        show(.init(kind: .success, title: isSecret ? "Copied — clears in 90 seconds" : "\(label) copied",
                   message: isSecret ? "The clipboard is wiped automatically." : nil))
    }

    func show(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.toast = nil }
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    func clearHistory() {
        try? portfolioStore.clear()
        history = []
        portfolio = .empty
        lastScanDate = nil
    }

    var portfolioStoreURL: URL { portfolioStore.url }

    private func loadStoredScans() {
        guard let stored = try? portfolioStore.load() else { return }
        history = stored.history
        if let last = stored.lastPortfolio {
            portfolio = last
            lastScanDate = last.scannedAt
        }
    }

    private var settingsKey: String { "sentinel.settings" }

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
        settings = decoded
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }
}
