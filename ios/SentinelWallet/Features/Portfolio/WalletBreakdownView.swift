import SwiftUI

/// One card per wallet, with the per-network rows underneath.
struct WalletBreakdownView: View {
    @EnvironmentObject private var state: AppState
    @Binding var expandedWallet: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Wallets", subtitle: "\(state.walletCount) in the vault")
            ForEach(state.wallets) { wallet in
                card(for: wallet)
            }
        }
    }

    private func reports(for wallet: WalletSummary) -> [AddressReport] {
        let addresses = Set(wallet.accounts.map { "\($0.network.id):\($0.address)" })
        return state.portfolio.reports.filter { addresses.contains($0.id) }
    }

    private func card(for wallet: WalletSummary) -> some View {
        let walletReports = reports(for: wallet)
        let total = walletReports.reduce(Decimal(0)) { $0 + $1.usdValue }
        let funded = walletReports.filter { $0.state == .funded }.count
        let expanded = expandedWallet == wallet.id

        return VStack(spacing: 0) {
            Button {
                withAnimation(Motion.smooth) {
                    expandedWallet = expanded ? nil : wallet.id
                }
            } label: {
                HStack(spacing: 12) {
                    IconView(icon: wallet.kind == .mnemonic ? .key : .lock, size: 18, weight: 2,
                             color: Theme.violetLight)
                        .frame(width: 40, height: 40)
                        .background(Theme.glassBright, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(wallet.label).font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                        Text(wallet.kind == .mnemonic ? "Recovery phrase" : "Imported private key")
                            .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(Theme.usd(total)).font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                        Text(funded > 0 ? "\(funded) funded" : "nothing funded")
                            .font(Theme.Font.tiny)
                            .foregroundStyle(funded > 0 ? Theme.green : Theme.mutedDim)
                    }
                    IconView(icon: .chevron, size: 13, weight: 2.2, color: Theme.mutedDim)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(13)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.99))

            if expanded {
                VStack(spacing: 8) {
                    ForEach(walletReports) { report in
                        row(report)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.bottom, 13)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glass(radius: Theme.radiusLarge, strength: 0.75)
    }

    private func row(_ report: AddressReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle().fill(Theme.color(for: report.networkID)).frame(width: 9, height: 9)
                Text(report.networkName).font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                Spacer()
                Chip(text: report.state.title, tint: Theme.color(for: report.state))
            }
            AddressLine(address: report.address, compact: true) {
                state.copy(report.address, label: "Address")
            }
            HStack(spacing: 8) {
                Text(Theme.amount(report.native.amount, symbol: report.symbol))
                    .font(Theme.Font.mono(12.5)).foregroundStyle(Theme.text)
                if report.usdValue > 0 {
                    Text("≈ \(Theme.usd(report.usdValue))")
                        .font(Theme.Font.tiny).foregroundStyle(Theme.muted)
                }
                Spacer()
                if report.native.usdPrice == nil && report.native.amount > 0 {
                    Chip(text: "no price", tint: Theme.mutedDim)
                }
                Text(report.providers.count > 1 ? "2 sources" : "1 source")
                    .font(Theme.Font.tiny)
                    .foregroundStyle(report.providers.count > 1 ? Theme.green : Theme.amber)
            }
            if !report.realTokens.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(report.realTokens.prefix(8)) { token in
                            Chip(text: "\(Theme.amount(token.amount, symbol: token.symbol))", tint: Theme.cyan)
                        }
                        if report.flaggedTokens.count > 0 {
                            Chip(text: "+\(report.flaggedTokens.count) junk", tint: Theme.red, icon: .alert)
                        }
                    }
                }
            }
            Text(report.path).font(Theme.Font.mono(11)).foregroundStyle(Theme.mutedDim)
        }
        .glassCard(radius: Theme.radiusSmall, strength: 0.5, padding: 11)
    }
}

/// Value per network, as bars.
struct NetworkBreakdownView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "By network", subtitle: "where the value sits")
            let totals = state.portfolio.networkTotals
            let peak = (totals.map { NSDecimalNumber(decimal: $0.usd).doubleValue }.max() ?? 0)
            VStack(spacing: 10) {
                ForEach(totals) { total in
                    HStack(spacing: 10) {
                        Circle().fill(Theme.color(for: total.networkID)).frame(width: 9, height: 9)
                        Text(NetworkLookup.shortName(total.networkID))
                            .font(Theme.Font.caption).foregroundStyle(Theme.text)
                            .frame(width: 74, alignment: .leading)
                        GeometryReader { proxy in
                            let value = NSDecimalNumber(decimal: total.usd).doubleValue
                            let fraction = peak > 0 ? value / peak : 0
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.glassBright)
                                Capsule()
                                    .fill(LinearGradient(colors: [Theme.color(for: total.networkID), Theme.violet.opacity(0.7)],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, proxy.size.width * fraction))
                            }
                        }
                        .frame(height: 8)
                        Text(Theme.usd(total.usd, compact: true))
                            .font(Theme.Font.mono(12)).foregroundStyle(Theme.text)
                            .frame(width: 78, alignment: .trailing)
                        if !total.confirmed {
                            IconView(icon: .alert, size: 13, weight: 2.2, color: Theme.amber)
                        }
                    }
                }
                if totals.isEmpty {
                    Text("Nothing scanned yet.").font(Theme.Font.caption).foregroundStyle(Theme.muted)
                }
            }
            .glassCard(radius: Theme.radiusMedium, strength: 0.6, padding: 13)
        }
    }
}
