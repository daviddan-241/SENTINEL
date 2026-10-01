import SwiftUI

/// The first thing anyone sees: create a vault, or open the one on the device.
struct LockView: View {
    @EnvironmentObject private var state: AppState
    @State private var password = ""
    @State private var confirmation = ""
    @State private var busy = false
    @FocusState private var focused: Bool

    private var creating: Bool { !state.hasVault }

    private var passwordIssue: String? {
        guard creating else { return nil }
        if password.count < 8 { return "At least eight characters. Length beats punctuation." }
        if password != confirmation { return "The two entries do not match." }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    IconView(icon: .shield, size: 40, weight: 1.7, color: Theme.violetLight)
                        .frame(width: 84, height: 84)
                        .background {
                            Circle().fill(LinearGradient(colors: [Theme.violet.opacity(0.4), Theme.cyan.opacity(0.2)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        .overlay { Circle().strokeBorder(Theme.borderBright, lineWidth: Theme.hairline) }
                        .shadow(color: Theme.violet.opacity(0.4), radius: 26, y: 12)
                    Text("Sentinel").font(Theme.Font.display).foregroundStyle(Theme.text)
                    Text(creating
                         ? "One password protects every phrase you add. It is never stored, and there is no recovery if you forget it."
                         : "Enter your vault password to decrypt the wallet list.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 40)
                .appearIn(0)

                VStack(spacing: 12) {
                    SecureField("vault password", text: $password)
                        .font(Theme.Font.body)
                        .focused($focused)
                        .submitLabel(creating ? .next : .go)
                        .onSubmit { creating ? nil : unlock() }
                        .padding(13)
                        .glass(radius: Theme.radiusMedium, strength: 0.95)

                    if creating {
                        SecureField("repeat the password", text: $confirmation)
                            .font(Theme.Font.body)
                            .submitLabel(.go)
                            .onSubmit { create() }
                            .padding(13)
                            .glass(radius: Theme.radiusMedium, strength: 0.95)
                        if let issue = passwordIssue, !password.isEmpty {
                            HStack(spacing: 8) {
                                IconView(icon: .info, size: 14, weight: 2, color: Theme.muted)
                                Text(issue).font(Theme.Font.tiny).foregroundStyle(Theme.muted)
                                Spacer()
                            }
                        }
                    }

                    if state.lockout.isLocked, let message = state.lockout.describeLockout() {
                        HStack(spacing: 8) {
                            IconView(icon: .alert, size: 15, weight: 2.2, color: Theme.amber)
                            Text(message).font(Theme.Font.caption).foregroundStyle(Theme.amber)
                            Spacer()
                        }
                        .glassCard(radius: Theme.radiusSmall, strength: 0.5, padding: 11)
                    }

                    PrimaryButton(title: creating ? "Create the vault" : "Unlock",
                                  icon: creating ? .lock : .key,
                                  busy: busy,
                                  disabled: password.isEmpty || (creating && passwordIssue != nil)) {
                        creating ? create() : unlock()
                    }

                    Text(creating
                         ? "AES-256-GCM, with the key stretched by PBKDF2-HMAC-SHA512 over 600,000 rounds."
                         : "\(state.lockout.attemptsUntilSlowdown) attempt\(state.lockout.attemptsUntilSlowdown == 1 ? "" : "s") before the wait starts to grow.")
                        .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .glassCard(radius: Theme.radiusLarge, strength: 0.85)
                .appearIn(1)

                VStack(alignment: .leading, spacing: 8) {
                    bullet(.shield, "Phrases stay on the device. No account, no sync, no server that could leak.")
                    bullet(.globe, "Balances come from public explorers and independent nodes, two per network.")
                    bullet(.alert, "Junk airdrop tokens are flagged and kept out of your total.")
                }
                .glassCard(radius: Theme.radiusLarge, strength: 0.55, padding: 14)
                .appearIn(2)
            }
            .padding(Theme.padding)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }

    private func bullet(_ icon: Icon, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            IconView(icon: icon, size: 15, weight: 2, color: Theme.violetLight)
            Text(text).font(Theme.Font.caption).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func create() {
        guard creating, passwordIssue == nil else { return }
        busy = true
        state.createVault(password: password)
        password = ""
        confirmation = ""
        busy = false
        focused = false
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        busy = true
        state.unlock(password: password)
        busy = false
        if !state.isLocked { focused = false }
    }
}
