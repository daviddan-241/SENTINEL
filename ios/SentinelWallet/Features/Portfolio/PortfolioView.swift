import SwiftUI

/// The first tab: what the wallets are worth, and what needs attention.
struct PortfolioView: View {
    @EnvironmentObject private var state: AppState
    var goToScan: () -> Void
    var goToWallets: () -> Void

    @State private var showFlaggedTokens = false
    @State private var appliedSpamSetting = false
    @State private var expandedWallet: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if state.walletCount == 0 {
                    EmptyStateView(icon: .vault,
                                   title: "No wallets yet",
                                   message: "Add a recovery phrase or a private key. Sentinel derives every supported address on the device and never sends the phrase anywhere.",
                                   actionTitle: "Add a wallet",
                                   action: goToWallets)
                    .appearIn(0)
                } else {
                    hero.appearIn(0)
                    if !portfolio.reports.isEmpty {
                        attention.appearIn(1)
                        WalletBreakdownView(expandedWallet: $expandedWallet).appearIn(2)
                        NetworkBreakdownView().appearIn(3)
                        if !portfolio.tokenTotals.isEmpty || state.flaggedTokenCount > 0 {
                            tokens.appearIn(4)
                        }
                        if !portfolio.activityFeed.isEmpty {
                            activity.appearIn(5)
                        }
                        providers.appearIn(6)
                    } else if state.progress.isRunning {
                        scanningCard.appearIn(1)
                    } else {
                        EmptyStateView(icon: .scan,
                                       title: "Ready to scan",
                                       message: "\(state.addressCount) addresses across \(Networks.all.count) networks are waiting. Nothing leaves the device except the public addresses themselves.",
                                       actionTitle: "Run the first scan",
                                       action: goToScan)
                        .appearIn(1)
                    }
                }
            }
            .padding(.horizontal, Theme.padding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { state.scanAll() }
        .onAppear {
            // The setting is the default; the inline toggle is a per-visit override.
            guard !appliedSpamSetting else { return }
            showFlaggedTokens = !state.settings.hideFlaggedTokens
            appliedSpamSetting = true
        }
    }

    private var portfolio: Portfolio { state.portfolio }

    // MARK: hero

    private var hero: some View {
        GlassCard(tint: Theme.violet) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("TOTAL VALUE")
                        .font(Theme.Font.tiny).tracking(1.2).foregroundStyle(Theme.muted)
                    Spacer()
                    if let date = state.lastScanDate {
                        Text("scanned \(date.formatted(.relative(presentation: .named)))")
                            .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                    }
                }

                Text(Theme.usd(portfolio.totalUSD))
                    .font(Theme.Font.display)
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Chip(text: "\(portfolio.confirmedUSD.formatted(.currency(code: "USD").precision(.fractionLength(0)))) confirmed",
                         tint: Theme.green, icon: .check)
                    if portfolio.unconfirmedUSD > 0 {
                        Chip(text: "\(portfolio.unconfirmedUSD.formatted(.currency(code: "USD").precision(.fractionLength(0)))) single-source",
                             tint: Theme.cyan, icon: .info)
                    }
                    if !portfolio.needsAttention.isEmpty {
                        Chip(text: "\(portfolio.needsAttention.count) to verify", tint: Theme.amber, icon: .alert)
                    }
                }

                HStack(spacing: 8) {
                    StatTile(label: "Wallets", value: "\(state.walletCount)", icon: .vault)
                    StatTile(label: "Addresses", value: "\(portfolio.reports.count)", icon: .globe)
                    StatTile(label: "Funded", value: "\(portfolio.fundedReports.count)",
                             tint: portfolio.fundedReports.isEmpty ? Theme.text : Theme.green, icon: .sparkle)
                    StatTile(label: "Networks", value: "\(portfolio.networkTotals.count)", icon: .layers)
                }

                PrimaryButton(title: state.progress.isRunning ? "Scanning…" : "Scan every address",
                              icon: .scan, busy: state.progress.isRunning) {
                    state.scanAll()
                }
            }
        }
    }

    private var scanningCard: some View {
        GlassCard(tint: Theme.cyan) {
            HStack(spacing: 16) {
                ProgressRing(progress: state.progress.fraction, tint: Theme.cyan, label: "scanned")
                    .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reading the chains").font(Theme.Font.heading)
                    Text("\(state.progress.finished) of \(state.progress.total) addresses")
                        .font(Theme.Font.caption).foregroundStyle(Theme.muted)
                    Text("Two independent providers per network.")
                        .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                }
                Spacer()
            }
        }
    }

    // MARK: attention

    private var attention: some View {
        VStack(spacing: 10) {
            ForEach(portfolio.needsAttention) { report in
                attentionCard(report)
            }
            if !portfolio.duplicateAddresses.isEmpty {
                notice(tint: Theme.amber, icon: .alert,
                       title: "The same address appears twice",
                       message: "Two wallets derive \(portfolio.duplicateAddresses.count) identical address\(portfolio.duplicateAddresses.count == 1 ? "" : "es"). Scanning both is wasted work; check the labels.")
            }
            if !portfolio.dustedReports.isEmpty {
                notice(tint: Theme.pink, icon: .shield,
                       title: "\(portfolio.dustedReports.count) address\(portfolio.dustedReports.count == 1 ? "" : "es") only received junk tokens",
                       message: "Nothing real arrived. These airdrop tokens are advertising — do not visit their links or sign anything with them.")
            }
            if !portfolio.failures.isEmpty {
                notice(tint: Theme.red, icon: .alert,
                       title: "Some providers could not be reached",
                       message: portfolio.failures.prefix(2).joined(separator: " · "))
            }
        }
    }

    private func attentionCard(_ report: AddressReport) -> some View {
        GlassCard(tint: Theme.color(for: report.state)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconView(icon: .alert, size: 16, weight: 2.2, color: Theme.color(for: report.state))
                    Text("\(report.networkName) — \(report.state.title)")
                        .font(Theme.Font.bodyMedium)
                    Spacer()
                    Chip(text: report.verification.label, tint: Theme.color(for: report.verification))
                }
                Text(report.state.detail)
                    .font(Theme.Font.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                AddressLine(address: report.address, networkID: report.networkID) {
                    state.copy(report.address, label: "Address")
                }
                if !report.failures.isEmpty {
                    Text(report.failures.joined(separator: " · "))
                        .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func notice(tint: Color, icon: Icon, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            IconView(icon: icon, size: 17, weight: 2.1, color: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message).font(Theme.Font.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .glassCard(radius: Theme.radiusMedium, strength: 0.7, padding: 13)
        .overlay(alignment: .leading) {
            Capsule().fill(tint).frame(width: 3).padding(.vertical, 12).padding(.leading, 1)
        }
    }

    // MARK: tokens

    private var tokens: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tokens",
                          subtitle: portfolio.flaggedTokenCount > 0
                              ? "\(portfolio.flaggedTokenCount) flagged as junk and kept out of the total"
                              : nil,
                          trailing: portfolio.flaggedTokenCount > 0
                              ? AnyView(Button(showFlaggedTokens ? "hide junk" : "show junk") {
                                    withAnimation(Motion.smooth) { showFlaggedTokens.toggle() }
                                }
                                .font(Theme.Font.tiny)
                                .foregroundStyle(Theme.violetLight))
                              : nil)

            VStack(spacing: 8) {
                ForEach(visibleTokens) { token in
                    tokenRow(token)
                }
            }
        }
    }

    private var visibleTokens: [TokenHolding] {
        var seen = Set<String>()
        var out: [TokenHolding] = []
        for report in portfolio.reports {
            for token in report.tokens where showFlaggedTokens ? token.isFlagged : !token.isFlagged {
                guard token.amount > 0 else { continue }
                let key = "\(report.networkID):\(token.id)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                out.append(token)
            }
        }
        return out
    }

    private func tokenRow(_ token: TokenHolding) -> some View {
        HStack(spacing: 11) {
            Text(token.symbol.prefix(4).uppercased())
                .font(Theme.Font.tiny)
                .foregroundStyle(Theme.text)
                .frame(width: 42, height: 42)
                .background(Theme.glassBright, in: Circle())
                .overlay { Circle().strokeBorder(Theme.border, lineWidth: Theme.hairline) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(token.symbol).font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                    if token.isFlagged {
                        Chip(text: "junk", tint: Theme.red, icon: .alert)
                    } else if token.standard != "ERC-20" {
                        Chip(text: token.standard, tint: Theme.cyan)
                    }
                }
                Text(token.isFlagged ? (token.flaggedReason ?? "flagged") : token.name)
                    .font(Theme.Font.tiny)
                    .foregroundStyle(token.isFlagged ? Theme.red.opacity(0.85) : Theme.mutedDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Theme.amount(token.amount, symbol: "").trimmingCharacters(in: .whitespaces))
                    .font(Theme.Font.mono(12.5)).foregroundStyle(Theme.text)
                if let value = token.usdValue, !token.isFlagged {
                    Text(Theme.usd(value)).font(Theme.Font.tiny).foregroundStyle(Theme.muted)
                } else if token.isFlagged {
                    Text("no value").font(Theme.Font.tiny).foregroundStyle(Theme.red.opacity(0.8))
                }
            }
        }
        .glassCard(radius: Theme.radiusMedium, strength: 0.6, padding: 12)
        .opacity(token.isFlagged ? 0.85 : 1)
    }

    // MARK: activity and providers

    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent activity",
                          subtitle: portfolio.activityFeed.first?.timestamp.map {
                              "newest \($0.formatted(.relative(presentation: .named)))"
                          })
            VStack(spacing: 2) {
                ForEach(portfolio.activityFeed.prefix(12)) { item in
                    ActivityRow(item: item)
                        .padding(.vertical, 7)
                    if item.id != portfolio.activityFeed.prefix(12).last?.id {
                        Rectangle().fill(Theme.border).frame(height: Theme.hairline)
                    }
                }
            }
            .glassCard(radius: Theme.radiusMedium, strength: 0.6, padding: 13)
        }
    }

    private var providers: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sources", subtitle: "every balance is checked against two of them")
            VStack(spacing: 9) {
                ForEach(portfolio.providersUsed, id: \.self) { provider in
                    HStack(spacing: 9) {
                        Circle().fill(Theme.green).frame(width: 6, height: 6)
                        Text(provider).font(Theme.Font.caption).foregroundStyle(Theme.text)
                        Spacer()
                        Text("answered").font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                    }
                }
                if portfolio.providersUsed.isEmpty {
                    Text("No provider has answered yet.").font(Theme.Font.caption).foregroundStyle(Theme.muted)
                }
            }
            .glassCard(radius: Theme.radiusMedium, strength: 0.55, padding: 13)
        }
    }
}
