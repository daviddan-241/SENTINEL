import Foundation

/// Progressive slow-down after repeated wrong passwords.
///
/// The schedule is deliberately boring and predictable: the first three attempts are free
/// (typing a long password on a phone is error-prone), then the wait doubles up to a
/// fifteen-minute cap. Nothing here is security-critical — the vault's real defence is
/// PBKDF2 — it exists to make offline guessing through the UI pointless.
public struct LockoutPolicy: Equatable, Sendable {
    public private(set) var failedAttempts: Int = 0
    public private(set) var lockedUntil: Date?
    public var freeAttempts: Int = 3
    public var baseDelay: TimeInterval = 5
    public var maximumDelay: TimeInterval = 900

    public init(freeAttempts: Int = 3, baseDelay: TimeInterval = 5, maximumDelay: TimeInterval = 900) {
        self.freeAttempts = freeAttempts
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
    }

    public var isLocked: Bool {
        guard let lockedUntil else { return false }
        return lockedUntil > Date()
    }

    public func remainingLockout(from now: Date = Date()) -> TimeInterval {
        guard let lockedUntil, lockedUntil > now else { return 0 }
        return lockedUntil.timeIntervalSince(now)
    }

    public var attemptsUntilSlowdown: Int { max(0, freeAttempts - failedAttempts) }

    public mutating func recordFailure(now: Date = Date()) {
        failedAttempts += 1
        guard failedAttempts > freeAttempts else { return }
        let step = failedAttempts - freeAttempts - 1
        let delay = min(baseDelay * pow(2, Double(step)), maximumDelay)
        lockedUntil = now.addingTimeInterval(delay)
    }

    public mutating func recordSuccess() {
        failedAttempts = 0
        lockedUntil = nil
    }

    /// "4 minutes 20 seconds" — friendly copy for the unlock screen.
    public func describeLockout(from now: Date = Date()) -> String? {
        let remaining = remainingLockout(from: now)
        guard remaining > 0 else { return nil }
        let seconds = Int(remaining.rounded(.up))
        if seconds < 60 { return "Try again in \(seconds) second\(seconds == 1 ? "" : "s")" }
        let minutes = seconds / 60
        let rest = seconds % 60
        if rest == 0 { return "Try again in \(minutes) minute\(minutes == 1 ? "" : "s")" }
        return "Try again in \(minutes) min \(rest) s"
    }
}
