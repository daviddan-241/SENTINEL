import SwiftUI

/// The second tab: run a scan and watch it happen, then read the per-address results.
struct ScanView: View {
    @EnvironmentObject private var state: AppState
    @State private var filter: Filter = .all
    @State private var showLookup = false

    enum Filter: String, CaseIterable, Identifiable {
        case all, funded, attention
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .funded: return "Funded"
            case .attention: return "Attention"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                control.appearIn(0)
                if state.progress.isRunning {
                    running.appearIn(1)
                }
                if !state.portfolio.reports.isEmpty {
                    summary.appearIn(1)
                    filters.appearIn(2)
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, report in
                        AddressReportCard(report: report)
                            .appearIn(3 + index)
                    }
                } else if !state.progress.isRunning {
                    EmptyStateView(icon: .globe,
                                   title: "No scan to show",
                                   message: "Sentinel asks two independent providers per network and shows you both answers. Start a scan, or look up any address below.",
                                   actionTitle: "Look up an address",
                                   action: { showLookup = true })
                    .appearIn(2)
                }
            }
            .padding(.horizontal, Theme.padding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showLookup) {
            AddressLookupSheet()
        }
    }

    private var filtered: [AddressReport] {
        let reports = state.portfolio.reports
        switch filter {
        case .all: return reports
        case .funded: return reports.filter { $0.state == .funded }
        case .attention: return reports.filter { $0.state == .verifying || $0.state == .invalid || $0.state == .unavailable }
        }
    }

    private var control: some View {
        GlassCard(tint: Theme.cyan) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scan control").font(Theme.Font.heading)
                        Text(state.walletCount == 0
                             ? "Add a wallet first"
                             : "\(state.addressCount) addresses · \(Networks.all.count) networks · two sources each")
                            .font(Theme.Font.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if state.progress.isRunning {
                        LiveDot(tint: Theme.cyan)
                    }
                }
                HStack(spacing: 10) {
                    PrimaryButton(title: state.progress.isRunning ? "Scanning…" : "Start scan",
                                  icon: .scan, busy: state.progress.isRunning) {
                        state.scanAll()
                    }
                    SecondaryButton(title: "Lookup", icon: .lookup) { showLookup = true }
                }
                if let failure = state.lastFailure {
                    Text(failure)
                        .font(Theme.Font.tiny).foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var running: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ProgressRing(progress: state.progress.fraction, tint: Theme.violet, label: "done")
                        .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reading every chain").font(Theme.Font.bodyMedium)
                        Text("\(state.progress.finished) of \(state.progress.total)")
                            .font(Theme.Font.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }
                Text("Balances are compared between an explorer and an independent node. A mismatch shows up as “verification required” rather than a guess.")
                    .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassCard(radius: Theme.radiusLarge, strength: 0.9, padding: 14)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                    .strokeBorder(Theme.cyan.opacity(0.35), lineWidth: 1)
                    .overlay(ScanSweep(tint: Theme.cyan).clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)))
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            StatTile(label: "Funded", value: "\(state.portfolio.fundedReports.count)", tint: Theme.green, icon: .sparkle)
            StatTile(label: "Value", value: Theme.usd(state.portfolio.totalUSD, compact: true), icon: .layers)
            StatTile(label: "Attention", value: "\(state.portfolio.needsAttention.count)",
                     tint: state.portfolio.needsAttention.isEmpty ? Theme.text : Theme.amber, icon: .alert)
        }
    }

    private var filters: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases) { option in
                Button {
                    withAnimation(Motion.snappy) { filter = option }
                } label: {
                    Text(option.title)
                        .font(Theme.Font.caption)
                        .foregroundStyle(filter == option ? .white : Theme.muted)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background {
                            Capsule().fill(filter == option ? Theme.violet.opacity(0.85) : Theme.glassStrong)
                        }
                        .overlay { Capsule().strokeBorder(Theme.border, lineWidth: Theme.hairline) }
                }
                .buttonStyle(PressableStyle(scale: 0.95))
            }
            Spacer()
            if !state.portfolio.reports.isEmpty {
                Text("\(filtered.count)").font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
            }
        }
    }
}

/// One address, one network, everything the providers said.
struct AddressReportCard: View {
    @EnvironmentObject private var state: AppState
    let report: AddressReport
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Circle().fill(Theme.color(for: report.networkID)).frame(width: 10, height: 10)
                Text(report.networkName).font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                if report.isPrimary {
                    Chip(text: report.schemeLabel, tint: Theme.violetLight)
                }
                Spacer()
                Chip(text: report.state.title, tint: Theme.color(for: report.state),
                     icon: report.state == .funded ? .check : nil)
            }

            AddressLine(address: report.address, compact: true) {
                state.copy(report.address, label: "Address")
            }

            HStack(spacing: 10) {
                Text(Theme.amount(report.native.amount, symbol: report.symbol))
                    .font(Theme.Font.mono(13)).foregroundStyle(Theme.text)
                if report.usdValue > 0 {
                    Text("≈ \(Theme.usd(report.usdValue))").font(Theme.Font.tiny).foregroundStyle(Theme.muted)
                }
                Spacer()
                Chip(text: report.verification.label, tint: Theme.color(for: report.verification))
            }

            if expanded {
                VStack(alignment: .leading, spacing: 9) {
                    Rectangle().fill(Theme.border).frame(height: Theme.hairline)
                    DetailRow(label: "Derivation", value: report.path, mono: true)
                    if let transactions = report.transactionCount {
                        DetailRow(label: "Transactions", value: "\(transactions)")
                    }
                    DetailRow(label: "Providers", value: report.providers.joined(separator: " · "))
                    if let block = report.native.blockNumber {
                        DetailRow(label: "Balance at block", value: "\(block)", mono: true)
                    }
                    if let price = report.native.usdPrice {
                        DetailRow(label: "Rate used", value: "\(Theme.usd(price)) per \(report.symbol)")
                    }
                    if !report.realTokens.isEmpty {
                        ForEach(report.realTokens) { token in
                            DetailRow(label: token.symbol,
                                      value: Theme.amount(token.amount, symbol: "").trimmingCharacters(in: .whitespaces),
                                      mono: true)
                        }
                    }
                    if !report.flaggedTokens.isEmpty {
                        ForEach(report.flaggedTokens) { token in
                            DetailRow(label: "\(token.symbol) (junk)", value: "not counted",
                                      tint: Theme.red, icon: .alert)
                        }
                    }
                    if let url = NetworkLookup.explorerURL(report) {
                        Link(destination: url) {
                            HStack(spacing: 7) {
                                IconView(icon: .globe, size: 15, color: Theme.violetLight)
                                Text("Open in the block explorer")
                                    .font(Theme.Font.caption).foregroundStyle(Theme.violetLight)
                                Spacer()
                                IconView(icon: .chevron, size: 12, weight: 2, color: Theme.mutedDim)
                            }
                        }
                    }
                    if !report.failures.isEmpty {
                        ForEach(report.failures, id: \.self) { failure in
                            Text(failure).font(Theme.Font.tiny).foregroundStyle(Theme.amber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                withAnimation(Motion.smooth) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(expanded ? "Hide details" : "Details")
                        .font(Theme.Font.tiny).foregroundStyle(Theme.violetLight)
                    IconView(icon: .chevron, size: 11, weight: 2.2, color: Theme.violetLight)
                        .rotationEffect(.degrees(expanded ? -90 : 90))
                    Spacer()
                }
            }
            .buttonStyle(PressableStyle(scale: 0.98))
        }
        .glassCard(radius: Theme.radiusLarge, strength: 0.7, padding: 14)
    }
}
