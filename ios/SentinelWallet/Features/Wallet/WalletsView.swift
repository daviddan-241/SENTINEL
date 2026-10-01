import SwiftUI

/// The third tab: the vault itself — what is stored, and what can be revealed.
struct WalletsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showImport = false
    @State private var revealItem: VaultItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header.appearIn(0)
                if state.wallets.isEmpty {
                    EmptyStateView(icon: .key,
                                   title: "The vault is empty",
                                   message: "Add a recovery phrase or a single private key. Everything is encrypted with a key stretched from your vault password before it touches the disk.",
                                   actionTitle: "Add the first wallet",
                                   action: { showImport = true })
                    .appearIn(1)
                } else {
                    ForEach(Array(state.wallets.enumerated()), id: \.element.id) { index, wallet in
                        WalletRow(wallet: wallet,
                                  onReveal: { revealItem = wallet.item },
                                  onDelete: { state.deleteWallet(id: wallet.id) })
                            .appearIn(index + 1)
                    }
                }
                if let vault = state.unlocked {
                    storage(vault).appearIn(state.wallets.count + 2)
                }
            }
            .padding(.horizontal, Theme.padding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showImport) {
            ImportWalletView()
        }
        .sheet(item: $revealItem) { item in
            RevealSheet(item: item)
        }
    }

    private var header: some View {
        GlassCard(tint: Theme.violet) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Vault").font(Theme.Font.heading)
                        Text("\(state.wallets.count) wallet\(state.wallets.count == 1 ? "" : "s") · \(state.addressCount) addresses")
                            .font(Theme.Font.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    IconView(icon: .shield, size: 22, weight: 2, color: Theme.green)
                }
                PrimaryButton(title: "Add a wallet", icon: .plus) { showImport = true }
            }
        }
    }

    private func storage(_ vault: UnlockedVault) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "How this is stored",
                          subtitle: "no phrase ever leaves the device")
            VStack(alignment: .leading, spacing: 9) {
                DetailRow(label: "Cipher", value: "AES-256-GCM")
                DetailRow(label: "Key stretch", value: "PBKDF2-HMAC-SHA512 · \(vault.vault.header.iterations.formatted()) rounds")
                DetailRow(label: "Items sealed", value: "\(vault.itemCount)")
                DetailRow(label: "File", value: state.portfolioStoreURL.deletingLastPathComponent().lastPathComponent + "/vault.json", mono: true)
                Text("The file holds a salt, a nonce and ciphertext. Opening it needs the password; changing the password re-wraps the key without touching the items.")
                    .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassCard(radius: Theme.radiusMedium, strength: 0.6, padding: 13)
        }
    }
}

/// A single wallet in the list.
private struct WalletRow: View {
    @EnvironmentObject private var state: AppState
    let wallet: WalletSummary
    let onReveal: () -> Void
    let onDelete: () -> Void

    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                IconView(icon: wallet.kind == .mnemonic ? .key : .lock, size: 17, weight: 2, color: Theme.violetLight)
                    .frame(width: 40, height: 40)
                    .background(Theme.glassBright, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallet.label).font(Theme.Font.bodyMedium).foregroundStyle(Theme.text)
                    Text(wallet.kind == .mnemonic ? "Recovery phrase" : "Imported key")
                        .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                }
                Spacer()
                Chip(text: "\(wallet.addressCount) addresses", tint: Theme.cyan)
            }

            if let primary = wallet.primaryAddress {
                AddressLine(address: primary, compact: true) {
                    state.copy(primary, label: "Address")
                }
            }

            HStack(spacing: 9) {
                Button(action: onReveal) {
                    HStack(spacing: 6) {
                        IconView(icon: .eye, size: 14, weight: 2, color: Theme.violetLight)
                        Text("Reveal").font(Theme.Font.caption).foregroundStyle(Theme.violetLight)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glass(radius: Theme.radiusPill, strength: 0.8)
                }
                .buttonStyle(PressableStyle(scale: 0.95))

                Button { confirmingDelete = true } label: {
                    HStack(spacing: 6) {
                        IconView(icon: .trash, size: 14, weight: 2, color: Theme.red)
                        Text("Remove").font(Theme.Font.caption).foregroundStyle(Theme.red)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glass(radius: Theme.radiusPill, strength: 0.6)
                }
                .buttonStyle(PressableStyle(scale: 0.95))

                Spacer()
                Text("added \(wallet.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
            }
        }
        .glassCard(radius: Theme.radiusLarge, strength: 0.72, padding: 14)
        .confirmationDialog("Remove \(wallet.label)?",
                            isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Remove from the vault", role: .destructive) { onDelete() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The encrypted item is deleted. Any funds it controls stay on chain — keep a backup of the phrase elsewhere.")
        }
    }
}
