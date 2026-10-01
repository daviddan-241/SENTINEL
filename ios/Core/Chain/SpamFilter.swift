import Foundation

/// Flagging for the tokens nobody asked for.
///
/// A real wallet address receives junk constantly: airdrop lures, "claim your reward" tokens
/// whose *name* is a phishing URL, Telegram bot handles, and copycat tickers. They are worth
/// nothing, they cannot be sold, and their whole purpose is to get the owner to visit a link
/// and sign something. A portfolio that counts them is worse than useless, so they are
/// flagged, hidden behind a toggle, and never included in a total.
///
/// The rules are deterministic and testable. Explorer-published reputations win when they
/// exist (Blockscout publishes one per token); otherwise the name and symbol are checked
/// against the patterns these tokens actually use — see `SpamFilterTests`, which runs
/// against the names captured from a real dusted address.
public enum SpamFilter {
    /// Tokens an explorer has itself labelled. Always trusted over the heuristics.
    public static let flaggedReputations: Set<String> = ["spam", "scam", "suspicious", "unsafe", "honeypot"]

    /// Hosts and link shapes that appear in junk token names.
    private static let hostPatterns = [
        "http://", "https://", "www.", "t.me/", "telegram", ".eth.limo",
        ".com", ".io", ".cc", ".xyz", ".top", ".vip", ".cfd", ".store", ".lat", ".rest",
        ".site", ".online", ".click", ".link", ".lol", ".gift", ".gifts", ".fun", ".app",
        ".vercel.app", ".ltd", ".club", ".live", ".life",
    ]

    /// Words that only appear in lures, in combination with a link or a number.
    private static let lureWords = [
        "claim", "airdrop", "reward", "bonus", "visit", "unwrap", "free ", "redeem",
        "voucher", "giveaway", "win ", "get ", "swap for", "bridge for",
    ]

    /// "@something_bot", "$TICKER [via …]", bracketed instructions and the like.
    private static let noiseMarkers = ["@", "[", "]", "✅", "💰", "🎁", "🔥", "🚀"]

    public static func isFlagged(name: String, symbol: String, reputation: String?) -> Bool {
        if let reputation, flaggedReputations.contains(reputation.lowercased()) { return true }
        let haystack = (name + " " + symbol).lowercased()
        if haystack.trimmingCharacters(in: .whitespaces).isEmpty { return true }

        // A link in a token name is never a legitimate token.
        if hostPatterns.contains(where: { haystack.contains($0) }) { return true }

        // A lure word with a number attached ("10000 ZKsync airdrop").
        let hasDigit = haystack.contains(where: { $0.isNumber })
        if lureWords.contains(where: { haystack.contains($0) }) && hasDigit { return true }
        if haystack.contains("claim") || haystack.contains("airdrop") { return true }

        // Handle-style noise: an @, a bracket, an emoji used as punctuation.
        if noiseMarkers.contains(where: { haystack.contains($0) }) { return true }
        return false
    }

    /// The one-line explanation shown in the UI.
    public static func reason(name: String, symbol: String, reputation: String?) -> String {
        if let reputation, flaggedReputations.contains(reputation.lowercased()) {
            return "The explorer flagged this token as \(reputation)."
        }
        let haystack = (name + " " + symbol).lowercased()
        if hostPatterns.contains(where: { haystack.contains($0) }) {
            return "The name contains a link — this is an airdrop lure, not a holding."
        }
        if haystack.contains("claim") || haystack.contains("airdrop") || haystack.contains("reward") {
            return "The name is advertising a claim or airdrop."
        }
        if noiseMarkers.contains(where: { haystack.contains($0) }) {
            return "The name looks like a bot handle or advertising."
        }
        return "This token matched the spam patterns."
    }
}
