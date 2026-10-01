import SwiftUI

/// The visual language, carried over from the web build so both halves of the project look
/// like one product: near-black glass, one violet accent with cyan support, generous radii,
/// and a single easing curve for the whole app.
enum Theme {
    // MARK: palette
    static let background = Color(hex: 0x05060B)
    static let glass = Color.white.opacity(0.055)
    static let glassStrong = Color.white.opacity(0.085)
    static let glassBright = Color.white.opacity(0.12)
    static let border = Color.white.opacity(0.11)
    static let borderBright = Color.white.opacity(0.18)
    static let text = Color(hex: 0xF5F7FC)
    static let muted = Color(hex: 0x9AA4BD)
    static let mutedDim = Color(hex: 0x6B7389)

    static let violet = Color(hex: 0x8B5CF6)
    static let violetLight = Color(hex: 0xA78BFA)
    static let cyan = Color(hex: 0x22D3EE)
    static let cyanLight = Color(hex: 0x67E8F9)
    static let pink = Color(hex: 0xF472B6)
    static let green = Color(hex: 0x34D399)
    static let amber = Color(hex: 0xFBBF24)
    static let red = Color(hex: 0xFB7185)

    /// State colours, one place so a state always looks the same everywhere.
    static func color(for state: ScanState) -> Color {
        switch state {
        case .funded: return green
        case .active: return cyan
        case .empty: return muted
        case .unused: return mutedDim
        case .invalid: return red
        case .verifying: return amber
        case .unavailable: return mutedDim
        }
    }

    static func color(for verification: Verification) -> Color {
        switch verification {
        case .agreed: return green
        case .singleSource: return cyan
        case .disagreed: return amber
        case .unavailable: return mutedDim
        }
    }

    static func color(for networkID: String) -> Color {
        switch networkID {
        case "ethereum": return Color(hex: 0x627EEA)
        case "base": return Color(hex: 0x0052FF)
        case "arbitrum": return Color(hex: 0x12AAFF)
        case "optimism": return Color(hex: 0xFF0420)
        case "polygon": return Color(hex: 0x8247E5)
        case "gnosis": return Color(hex: 0x04795B)
        case "bitcoin": return Color(hex: 0xF7931A)
        case "solana": return Color(hex: 0x14F195)
        default: return violet
        }
    }

    /// The hero gradient used on primary buttons and the total balance.
    static let accentGradient = LinearGradient(colors: [violet, cyan],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    static let warmGradient = LinearGradient(colors: [pink, violet],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: geometry
    static let radiusLarge: CGFloat = 26
    static let radiusMedium: CGFloat = 18
    static let radiusSmall: CGFloat = 13
    static let radiusPill: CGFloat = 999
    static let padding: CGFloat = 15
    static let tabBarHeight: CGFloat = 78
    static let hairline: CGFloat = 1

    // MARK: type
    enum Font {
        static let display = SwiftUI.Font.system(size: 40, weight: .bold, design: .rounded)
        static let title = SwiftUI.Font.system(size: 24, weight: .bold, design: .rounded)
        static let heading = SwiftUI.Font.system(size: 18, weight: .semibold, design: .rounded)
        static let body = SwiftUI.Font.system(size: 15, weight: .regular, design: .rounded)
        static let bodyMedium = SwiftUI.Font.system(size: 15, weight: .medium, design: .rounded)
        static let caption = SwiftUI.Font.system(size: 12.5, weight: .medium, design: .rounded)
        static let tiny = SwiftUI.Font.system(size: 11, weight: .semibold, design: .rounded)
        /// Addresses, hashes, mnemonics — anything where a wrong glyph matters.
        static func mono(_ size: CGFloat = 14, weight: SwiftUI.Font.Weight = .medium) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    // MARK: money
    static func usd(_ value: Decimal, compact: Bool = false) -> String {
        if compact, value >= 10_000 {
            return value.formatted(.currency(code: "USD").precision(.fractionLength(0)).notation(.compactName))
        }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// Amounts keep more precision the smaller they get — 0.000412 BTC is not "0".
    static func amount(_ value: Decimal, symbol: String) -> String {
        let magnitude = abs(value)
        let digits: Int
        if magnitude == 0 { digits = 2 }
        else if magnitude >= 1_000 { digits = 2 }
        else if magnitude >= 1 { digits = 4 }
        else if magnitude >= 0.001 { digits = 6 }
        else { digits = 9 }
        let text = value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.automatic))
        return "\(text) \(symbol)"
    }

    static func percent(_ value: Decimal) -> String {
        value.formatted(.percent.precision(.fractionLength(0...2)))
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// Reads a "#RRGGBB" or "RRGGBB" string, falling back to the accent colour.
    init(hexString: String, fallback: Color = Theme.violet) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            self = fallback
            return
        }
        self.init(hex: value)
    }
}
