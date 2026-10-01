import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking     // URLSession lives here on Linux
#endif

public enum ChainError: Error, Equatable {
    case offline
    case timedOut
    case http(status: Int, provider: String)
    case rateLimited(provider: String)
    case decoding(provider: String, detail: String)
    case rejected(provider: String, detail: String)
    case cancelled

    public var message: String {
        switch self {
        case .offline: return "No internet connection."
        case .timedOut: return "The provider took too long to answer."
        case .http(let status, let provider): return "\(provider) answered HTTP \(status)."
        case .rateLimited(let provider): return "\(provider) is rate limiting, try again shortly."
        case .decoding(let provider, _): return "\(provider) sent something unexpected."
        case .rejected(let provider, let detail): return "\(provider) rejected the request: \(detail)"
        case .cancelled: return "Scan cancelled."
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .timedOut, .offline: return true
        case .http(let status, _): return status >= 500
        case .rateLimited: return true
        default: return false
        }
    }
}

/// Everything the network layer needs from a URLSession, so tests can swap it out.
public protocol ChainTransport: Sendable {
    func get(_ url: URL, timeout: TimeInterval) async throws -> (Data, Int)
    func post(_ url: URL, body: Data, timeout: TimeInterval) async throws -> (Data, Int)
}

/// The real transport. One URLSession is created for the whole app: it keeps connections
/// alive between providers, and creating a session per request leaks sockets (which Linux
/// Foundation punishes at exit).
public final class URLSessionTransport: ChainTransport, @unchecked Sendable {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = URLSessionTransport.defaultConfiguration) {
        self.session = URLSession(configuration: configuration)
    }

    public static var defaultConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["accept": "application/json"]
        return configuration
    }

    /// Lets a command-line caller (and tests) shut the socket pool down cleanly.
    public func invalidate() {
        session.invalidateAndCancel()
    }

    public func get(_ url: URL, timeout: TimeInterval = 15) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await run(request, timeout: timeout)
    }

    public func post(_ url: URL, body: Data, timeout: TimeInterval = 15) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body
        return try await run(request, timeout: timeout)
    }

    private func run(_ request: URLRequest, timeout: TimeInterval) async throws -> (Data, Int) {
        var request = request
        request.timeoutInterval = timeout
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ChainError.decoding(provider: request.url?.host ?? "provider", detail: "no HTTP response")
            }
            return (data, http.statusCode)
        } catch let error as ChainError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dataNotAllowed, .internationalRoamingOff:
                throw ChainError.offline
            case .timedOut:
                throw ChainError.timedOut
            case .cancelled:
                throw ChainError.cancelled
            default:
                throw ChainError.decoding(provider: request.url?.host ?? "provider", detail: error.localizedDescription)
            }
        } catch is CancellationError {
            throw ChainError.cancelled
        } catch {
            throw ChainError.decoding(provider: request.url?.host ?? "provider", detail: error.localizedDescription)
        }
    }
}

/// A provider that can answer for one family of networks.
public protocol AddressProvider: Sendable {
    var name: String { get }
    func supports(_ network: Network) -> Bool
    func report(address: String, network: Network, limit: Int) async throws -> ProviderReport
}

/// Anything that can price a coin in USD when the explorer cannot.
public protocol PriceSource: Sendable {
    var name: String { get }
    /// Whole-coin price in USD, keyed by symbol: "BTC", "ETH", "SOL".
    func prices(symbols: [String]) async throws -> [String: Decimal]
}

/// Fails a call that runs past the deadline instead of leaving the UI spinning.
public func withTimeout<T: Sendable>(_ seconds: TimeInterval,
                                     operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            throw ChainError.timedOut
        }
        guard let first = try await group.next() else { throw ChainError.timedOut }
        group.cancelAll()
        return first
    }
}

/// Retries the provider errors that are worth retrying, with a short backoff.
public func withRetry<T: Sendable>(attempts: Int = 2,
                                   delay: TimeInterval = 0.4,
                                   operation: @escaping @Sendable () async throws -> T) async throws -> T {
    var lastError: Error = ChainError.timedOut
    for attempt in 1...max(1, attempts) {
        do {
            return try await operation()
        } catch let error as ChainError {
            lastError = error
            if !error.isRetryable || attempt == attempts { break }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000 * Double(attempt)))
        }
    }
    throw lastError
}

// MARK: - decimal helpers

public enum DecimalParsing {
    /// Base units as a decimal string → a Decimal amount. Never goes through Double.
    public static func amount(raw: String, decimals: Int) -> Decimal {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        let negative = trimmed.hasPrefix("-")
        let digits = negative ? String(trimmed.dropFirst()) : trimmed
        guard digits.allSatisfy(\.isNumber) else { return 0 }
        let value = Decimal(string: digits) ?? 0
        let scaled = value / pow(Decimal(10), decimals)
        return negative ? -scaled : scaled
    }

    public static func decimal(_ string: String?) -> Decimal? {
        guard let string, !string.isEmpty else { return nil }
        return Decimal(string: string)
    }

    public static func uint64(_ string: String?) -> UInt64? {
        guard let string else { return nil }
        return UInt64(string)
    }
}
