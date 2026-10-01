import SwiftUI

/// Reading a secret back out: password (or Face ID), then a ninety-second clipboard.
struct RevealSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let item: VaultItem

    @State private var password = ""
    @State private var revealed: String?
    @State private var busy = false
    @State private var biometricName = BiometricGate.biometryName
    @FocusState private var focused: Bool

    private var words: [String] {
        guard let revealed, item.kind == .mnemonic else { return [] }
        return revealed.split(separator: " ").map(String.init)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop()
                ScrollView {
                    VStack(spacing: 14) {
                        if let revealed {
                            revealedCard(revealed)
                        } else {
                            gate
                        }
                    }
                    .padding(Theme.padding)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(item.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.violetLight)
                }
            }
        }
        .presentationBackground(.clear)
        .onDisappear {
            // Leaving the screen must not leave the secret in memory.
            revealed = nil
            password = ""
        }
        .onAppear {
            if state.settings.requireBiometricsForReveal, BiometricGate.isAvailable {
                Task { await attemptBiometrics() }
            }
        }
    }

    private var gate: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                IconView(icon: .lock, size: 20, weight: 2, color: Theme.violetLight)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirm it is you").font(Theme.Font.heading)
                    Text("The vault password is required to decrypt \(item.label).")
                        .font(Theme.Font.caption).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            SecureField("vault password", text: $password)
                .font(Theme.Font.body)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit { unlock() }
                .padding(12)
                .glass(radius: Theme.radiusMedium, strength: 0.9)

            if state.lockout.isLocked, let message = state.lockout.describeLockout() {
                HStack(spacing: 8) {
                    IconView(icon: .alert, size: 15, weight: 2.2, color: Theme.amber)
                    Text(message).font(Theme.Font.caption).foregroundStyle(Theme.amber)
                    Spacer()
                }
                .glassCard(radius: Theme.radiusSmall, strength: 0.5, padding: 11)
            }

            PrimaryButton(title: "Unlock this item", icon: .eye, busy: busy,
                          disabled: password.isEmpty || state.lockout.isLocked) { unlock() }

            if BiometricGate.isAvailable {
                SecondaryButton(title: "Use \(biometricName)", icon: .shield) {
                    Task { await attemptBiometrics() }
                }
            }

            Text("A wrong password costs you a progressively longer wait. A correct one resets it.")
                .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard(radius: Theme.radiusLarge, strength: 0.8)
    }

    private func revealedCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                IconView(icon: .check, size: 17, weight: 2.2, color: Theme.green)
                Text("Decrypted").font(Theme.Font.bodyMedium).foregroundStyle(Theme.green)
                Spacer()
                Text("clears in 90s").font(Theme.Font.tiny).foregroundStyle(Theme.muted)
            }

            if item.kind == .mnemonic {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        HStack(spacing: 6) {
                            Text("\(index + 1)").font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                            Text(word).font(Theme.Font.mono(13)).foregroundStyle(Theme.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 8)
                        .glass(radius: Theme.radiusSmall, strength: 0.6)
                    }
                }
            } else {
                Text(text)
                    .font(Theme.Font.mono(14))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(radius: Theme.radiusMedium, strength: 0.7)
            }

            HStack(spacing: 10) {
                PrimaryButton(title: "Copy for 90 seconds", icon: .copy) {
                    state.copy(text, label: item.kind.title, isSecret: true)
                }
                SecondaryButton(title: "Hide") {
                    withAnimation(Motion.smooth) { revealed = nil }
                }
            }

            Text("Copying anything here is visible to other apps until the clipboard is wiped. Prefer writing the words down.")
                .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard(radius: Theme.radiusLarge, tint: Theme.green, strength: 0.8)
    }

    private func unlock() {
        busy = true
        defer { busy = false }
        if let text = state.reveal(item: item, password: password) {
            withAnimation(Motion.smooth) { revealed = text }
            focused = false
        }
    }

    private func attemptBiometrics() async {
        let outcome = await BiometricGate.authenticate(reason: "Reveal \(item.label)")
        switch outcome {
        case .success:
            if let text = state.reveal(item: item, password: "", biometricsAlreadyChecked: true) {
                withAnimation(Motion.smooth) { revealed = text }
            }
        case .unavailable:
            biometricName = "Biometrics"
        case .cancelled, .failed:
            break
        }
    }
}
