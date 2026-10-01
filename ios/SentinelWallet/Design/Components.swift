import SwiftUI

/// The animated sweep line used while a scan is running.
struct ScanSweep: View {
    var tint: Color = Theme.cyan
    @State private var position: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(colors: [.clear, tint.opacity(0.9), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 46)
                .offset(y: position * proxy.size.height - 23)
                .blur(radius: 2)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: false)) {
                        position = 1.15
                    }
                }
        }
        .allowsHitTesting(false)
    }
}

/// Progress ring with a percentage in the middle; used by the scan screen.
struct ProgressRing: View {
    let progress: Double
    var tint: Color = Theme.violet
    var label: String?

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.glassBright, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(AngularGradient(colors: [tint, Theme.cyan, tint], center: .center),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.smooth, value: progress)
            VStack(spacing: 1) {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(Theme.Font.heading).foregroundStyle(Theme.text)
                if let label {
                    Text(label).font(Theme.Font.tiny).foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

/// A small dot that pulses while something is live.
struct LiveDot: View {
    var tint: Color = Theme.green
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .stroke(tint.opacity(0.6), lineWidth: 1.5)
                    .scaleEffect(pulse ? 2.4 : 1)
                    .opacity(pulse ? 0 : 0.9)
            }
            .onAppear {
                withAnimation(Motion.pulse.repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}

/// A one-line message that slides in from the top, used for copy confirmations and errors.
struct Toast: Identifiable, Equatable {
    enum Kind: Equatable { case info, success, failure }
    let id = UUID()
    var kind: Kind = .info
    var title: String
    var message: String?

    var tint: Color {
        switch kind {
        case .info: return Theme.violet
        case .success: return Theme.green
        case .failure: return Theme.red
        }
    }

    var icon: Icon {
        switch kind {
        case .info: return .info
        case .success: return .check
        case .failure: return .alert
        }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            IconView(icon: toast.icon, size: 17, weight: 2, color: toast.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title).font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                if let message = toast.message {
                    Text(message).font(Theme.Font.caption).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glass(radius: Theme.radiusMedium, strength: 1.2)
        .overlay(alignment: .leading) {
            Capsule().fill(toast.tint).frame(width: 3).padding(.vertical, 10).padding(.leading, 1)
        }
        .padding(.horizontal, Theme.padding)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }
}

/// Address line: monospaced, middle-truncated, tap to copy.
struct AddressLine: View {
    let address: String
    var networkID: String?
    var compact: Bool = true
    var onCopy: (() -> Void)?

    var body: some View {
        HStack(spacing: 7) {
            if let networkID {
                Circle().fill(Theme.color(for: networkID)).frame(width: 8, height: 8)
            }
            Text(compact ? Address.shorten(address, leading: 10, trailing: 8) : address)
                .font(Theme.Font.mono(13))
                .foregroundStyle(Theme.text.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                onCopy?()
            } label: {
                IconView(icon: .copy, size: 14, weight: 1.9, color: Theme.muted)
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .disabled(onCopy == nil)
        }
    }
}

/// Tiny bar chart for the network breakdown.
struct MiniBars: View {
    let values: [Double]
    var tint: Color = Theme.violet

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(values.max() ?? 1, 0.0001)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    Capsule()
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.35)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: max(3, proxy.size.height * (value / maxValue)))
                        .opacity(0.5 + 0.5 * (Double(index + 1) / Double(values.count)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Row showing one activity entry.
struct ActivityRow: View {
    let item: ChainActivity

    private var tint: Color {
        switch item.direction {
        case .incoming: return Theme.green
        case .outgoing: return Theme.pink
        case .selfTransfer: return Theme.cyan
        case .unknown: return Theme.muted
        }
    }

    private var icon: Icon {
        switch item.direction {
        case .incoming: return .arrowDown
        case .outgoing: return .arrowUp
        default: return .refresh
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            IconView(icon: icon, size: 15, weight: 2.2, color: tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.direction == .incoming ? "Received" : item.direction == .outgoing ? "Sent" : "Transaction")
                    .font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    Text(NetworkLookup.shortName(item.networkID))
                        .font(Theme.Font.tiny).foregroundStyle(Theme.muted)
                    if item.isContractCall {
                        Text("contract").font(Theme.Font.tiny).foregroundStyle(Theme.cyan)
                    }
                    if item.status == "failed" {
                        Text("failed").font(Theme.Font.tiny).foregroundStyle(Theme.red)
                    } else if item.status == "pending" {
                        Text("pending").font(Theme.Font.tiny).foregroundStyle(Theme.amber)
                    }
                    if let timestamp = item.timestamp {
                        Text(timestamp.formatted(.relative(presentation: .named)))
                            .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                if item.amount > 0 {
                    Text(Theme.amount(item.amount, symbol: item.symbol))
                        .font(Theme.Font.mono(12.5)).foregroundStyle(Theme.text)
                }
                Text(Address.shorten(item.hash, leading: 6, trailing: 5))
                    .font(Theme.Font.mono(11)).foregroundStyle(Theme.mutedDim)
            }
        }
        .contentShape(Rectangle())
    }
}

enum NetworkLookup {
    static func shortName(_ id: String) -> String {
        switch id {
        case "ethereum": return "Ethereum"
        case "base": return "Base"
        case "arbitrum": return "Arbitrum"
        case "optimism": return "OP Mainnet"
        case "polygon": return "Polygon"
        case "gnosis": return "Gnosis"
        case "bitcoin": return "Bitcoin"
        case "solana": return "Solana"
        default: return id.capitalized
        }
    }

    static func network(_ id: String) -> Network? {
        Networks.network(id: id)
    }

    static func explorerURL(_ report: AddressReport) -> URL? {
        guard let network = network(report.networkID) else { return nil }
        return URL(string: network.explorerAddressURL(report.address))
    }
}
