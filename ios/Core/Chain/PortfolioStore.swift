import Foundation

/// Last scan per wallet and the history the app shows in the "more" panel.
public struct PortfolioStore: Sendable {
    public let url: URL
    private let historyLimit: Int

    public init(url: URL, historyLimit: Int = 30) {
        self.url = url
        self.historyLimit = historyLimit
    }

    public static func `default`() -> PortfolioStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("SentinelWallet", isDirectory: true)
        return PortfolioStore(url: directory.appendingPathComponent("scans.json"))
    }

    public static func inMemory() -> PortfolioStore {
        PortfolioStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sentinel-scans-\(UUID().uuidString).json"))
    }

    public struct Stored: Codable, Equatable, Sendable {
        public var lastPortfolio: Portfolio?
        public var history: [ScanSnapshot]

        public static let empty = Stored(lastPortfolio: nil, history: [])
    }

    public func load() throws -> Stored {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Stored.self, from: try Data(contentsOf: url))
    }

    public func record(_ portfolio: Portfolio) throws -> Stored {
        var stored = (try? load()) ?? .empty
        stored.lastPortfolio = portfolio
        stored.history.insert(ScanSnapshot(from: portfolio), at: 0)
        if stored.history.count > historyLimit {
            stored.history = Array(stored.history.prefix(historyLimit))
        }
        try save(stored)
        return stored
    }

    public func save(_ stored: Stored) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(stored)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        #if os(iOS) || os(macOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
