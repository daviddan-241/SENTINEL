import SwiftUI

/// The side panel: scan history, security, settings, and what the app actually is.
struct DrawerContent: View {
    @EnvironmentObject private var state: AppState
    @State private var section: Section = .menu

    enum Section: String, CaseIterable, Identifiable {
        case menu, history, security, settings, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .menu: return "Menu"
            case .history: return "Scan history"
            case .security: return "Security"
            case .settings: return "Settings"
            case .about: return "About"
            }
        }
        var icon: Icon {
            switch self {
            case .menu: return .dots
            case .history: return .history
            case .security: return .shield
            case .settings: return .filter
            case .about: return .info
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    switch section {
                    case .menu: menu
                    case .history: history
                    case .security: security
                    case .settings: settingsPanel
                    case .about: about
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            if section != .menu {
                Button {
                    withAnimation(Motion.smooth) { section = .menu }
                } label: {
                    HStack(spacing: 7) {
                        IconView(icon: .chevron, size: 13, weight: 2.2, color: Theme.violetLight)
                            .rotationEffect(.degrees(180))
                        Text("Back").font(Theme.Font.caption).foregroundStyle(Theme.violetLight)
                    }
                    .padding(14)
                }
                .buttonStyle(PressableStyle(scale: 0.97))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                IconView(icon: .shield, size: 22, weight: 2, color: Theme.violetLight)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle().fill(LinearGradient(colors: [Theme.violet.opacity(0.4), Theme.cyan.opacity(0.2)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay { Circle().strokeBorder(Theme.borderBright, lineWidth: Theme.hairline) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sentinel").font(Theme.Font.heading).foregroundStyle(Theme.text)
                    Text("wallet scanner").font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                }
                Spacer()
                Button {
                    withAnimation(Motion.smooth) { state.isDrawerOpen = false }
                } label: {
                    IconView(icon: .close, size: 15, weight: 2.2, color: Theme.muted)
                        .frame(width: 34, height: 34)
                        .glass(radius: 17, strength: 0.9)
                }
                .buttonStyle(PressableStyle(scale: 0.92))
            }

            HStack(spacing: 8) {
                StatTile(label: "Wallets", value: "\(state.walletCount)", icon: .vault)
                StatTile(label: "Value", value: Theme.usd(state.portfolio.totalUSD, compact: true), icon: .layers)
            }
        }
        .padding(14)
        .background {
            Rectangle().fill(.ultraThinMaterial).opacity(0.5).ignoresSafeArea(edges: .top)
        }
    }

    private var menu: some View {
        VStack(spacing: 8) {
            ForEach([Section.history, .security, .settings, .about]) { option in
                Button {
                    withAnimation(Motion.smooth) { section = option }
                } label: {
                    HStack(spacing: 11) {
                        IconView(icon: option.icon, size: 17, weight: 2, color: Theme.violetLight)
                        Text(option.title).font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                        Spacer()
                        IconView(icon: .chevron, size: 12, weight: 2.2, color: Theme.mutedDim)
                    }
                    .padding(13)
                    .glass(radius: Theme.radiusMedium, strength: 0.7)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }

            Button {
                withAnimation(Motion.smooth) { state.isDrawerOpen = false }
                state.lock()
            } label: {
                HStack(spacing: 11) {
                    IconView(icon: .lock, size: 17, weight: 2, color: Theme.amber)
                    Text("Lock the vault").font(Theme.Font.bodyMedium).foregroundStyle(Theme.amber)
                    Spacer()
                }
                .padding(13)
                .glass(radius: Theme.radiusMedium, strength: 0.7)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Scans", subtitle: "\(state.history.count) kept on this device",
                          trailing: state.history.isEmpty ? nil : AnyView(
                            Button("clear") { state.clearHistory() }
                                .font(Theme.Font.tiny).foregroundStyle(Theme.red)))
            ForEach(state.history) { snapshot in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(snapshot.date.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                        Spacer()
                        Text(Theme.usd(snapshot.totalUSD)).font(Theme.Font.mono(13)).foregroundStyle(Theme.text)
                    }
                    HStack(spacing: 6) {
                        Chip(text: "\(snapshot.addressCount) addresses", tint: Theme.cyan)
                        Chip(text: "\(snapshot.fundedCount) funded", tint: Theme.green)
                        Chip(text: String(format: "%.1fs", snapshot.duration), tint: Theme.muted)
                    }
                    HStack(spacing: 4) {
                        ForEach(snapshot.states.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                            if let scanState = ScanState(rawValue: pair.key) {
                                Text("\(pair.value) \(scanState.title.lowercased())")
                                    .font(Theme.Font.tiny)
                                    .foregroundStyle(Theme.color(for: scanState))
                            }
                        }
                    }
                }
                .glassCard(radius: Theme.radiusMedium, strength: 0.6, padding: 13)
            }
            if state.history.isEmpty {
                EmptyStateView(icon: .history, title: "No scans yet",
                               message: "Each scan is summarised here with local-only history: nothing about it leaves the device.")
            }
        }
    }

    private var security: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Security", subtitle: "what each setting actually does")
            VStack(alignment: .leading, spacing: 11) {
                securityRow(.lock, "Vault encryption",
                            "AES-256-GCM. The key comes from your password through PBKDF2-HMAC-SHA512, 600,000 rounds, with a fresh 32-byte salt.")
                securityRow(.shield, "Verification",
                            "Every balance is read from an explorer and an independent node. If they disagree the address is marked “verification required” and left out of the total.")
                securityRow(.eyeOff, "Clipboard",
                            "A copied phrase is wiped after 90 seconds, and only if it is still what Sentinel put there.")
                securityRow(.alert, "Junk tokens",
                            "Airdrop lures, link-in-the-name tokens and anything an explorer marks as spam are flagged, hidden, and never counted.")
                securityRow(.info, "Face ID",
                            "Face ID re-gates the reveal screen only. The vault itself stays unlocked in memory until you lock it or the app is backgrounded.")
            }
            .glassCard(radius: Theme.radiusLarge, strength: 0.6, padding: 14)

            SecondaryButton(title: "Delete the vault and all scan history", icon: .trash, tint: Theme.red) {
                state.deleteVault()
                withAnimation(Motion.smooth) { state.isDrawerOpen = false }
            }
        }
    }

    private func securityRow(_ icon: Icon, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IconView(icon: icon, size: 15, weight: 2, color: Theme.violetLight).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                Text(text).font(Theme.Font.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Settings")
            VStack(spacing: 4) {
                toggle("Hide flagged tokens", subtitle: "Keep junk out of the totals and the list", isOn: $state.settings.hideFlaggedTokens)
                toggle("Lock when backgrounded", subtitle: "Require the password again on return", isOn: $state.settings.autoLockOnBackground)
                toggle("Require Face ID to reveal", subtitle: "Biometry in front of the reveal screen", isOn: $state.settings.requireBiometricsForReveal)
            }
            .glassCard(radius: Theme.radiusLarge, strength: 0.6, padding: 8)

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Activity depth", subtitle: "how many transactions per address to fetch")
                HStack(spacing: 8) {
                    ForEach([5, 8, 15, 25], id: \.self) { depth in
                        Button {
                            state.settings.activityLimit = depth
                        } label: {
                            Text("\(depth)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(state.settings.activityLimit == depth ? .white : Theme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background {
                                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                        .fill(state.settings.activityLimit == depth ? Theme.violet.opacity(0.85) : Theme.glassStrong)
                                }
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                    }
                }
            }
            .glassCard(radius: Theme.radiusLarge, strength: 0.6, padding: 13)
        }
    }

    private func toggle(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                Text(subtitle).font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.violet)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "About", subtitle: "Sentinel \(SentinelVersion.marketing)")
            VStack(alignment: .leading, spacing: 10) {
                Text("Sentinel derives every address from your phrase on the device — BIP-32, BIP-44, BIP-49, BIP-84 and BIP-86 for Bitcoin, the shared m/44'/60' account for six EVM chains, and the ed25519 account for Solana — then reads the chains to tell you what is really there.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("It never signs anything. There is no send button, no seed export to a server, no analytics: the only things that leave the phone are the public addresses being looked up.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                DetailRow(label: "Version", value: SentinelVersion.build)
                DetailRow(label: "Networks", value: "\(Networks.all.count) with two sources each")
                DetailRow(label: "Word list", value: "BIP-39 · 2,048 words · verified")
                DetailRow(label: "Providers", value: "Blockscout, publicnode, mempool.space, blockstream.info, Kraken")
            }
            .glassCard(radius: Theme.radiusLarge, strength: 0.6, padding: 14)
        }
    }
}

enum SentinelVersion {
    static let marketing = "1.0"
    static var build: String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let number = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(number))"
    }
}
