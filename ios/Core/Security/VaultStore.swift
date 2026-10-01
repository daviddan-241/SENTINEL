import Foundation

/// Where the sealed vault lives.
///
/// - Application Support directory, written atomically, with complete file protection on
///   Apple platforms (`.completeUnlessOpen` is deliberately *not* used: the vault must be
///   unreadable while the device is locked).
/// - Tests and the command-line tool get the same behaviour in a temp directory.
public struct VaultStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func `default`() -> VaultStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("SentinelWallet", isDirectory: true)
        return VaultStore(url: directory.appendingPathComponent("vault.json"))
    }

    public static func inMemory() -> VaultStore {
        VaultStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sentinel-vault-\(UUID().uuidString).json"))
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func load() throws -> Vault? {
        guard exists else { return nil }
        return try Vault.decode(try Data(contentsOf: url))
    }

    public func save(_ vault: Vault) throws {
        let data = try Vault.encode(vault)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS) || os(macOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    public func delete() throws {
        guard exists else { return }
        try FileManager.default.removeItem(at: url)
    }
}
