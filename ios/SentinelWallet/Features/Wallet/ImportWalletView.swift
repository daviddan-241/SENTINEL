import SwiftUI

/// Import: a phrase or a single key, validated before it is accepted.
struct ImportWalletView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var kind: VaultKind = .mnemonic
    @State private var label = ""
    @State private var secret = ""
    @State private var passphrase = ""
    @State private var showPassphrase = false
    @FocusState private var focus: Field?

    private enum Field { case label, secret, passphrase }

    private var validation: BIP39.ValidationResult? {
        guard kind == .mnemonic, !secret.isEmpty else { return nil }
        return BIP39.validate(secret)
    }

    private var suggestions: [String] {
        guard kind == .mnemonic, case .unknownWords(let words) = validation ?? .empty else { return [] }
        return words.flatMap { BIP39.suggestions(for: $0).prefix(2) }
    }

    private var keyPreview: PrivateKeyImport.Parsed? {
        guard kind == .privateKey else { return nil }
        return PrivateKeyImport.parse(secret)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop()
                ScrollView {
                    VStack(spacing: 14) {
                        picker
                        fields
                        if let validation, kind == .mnemonic { validationCard(validation) }
                        if kind == .privateKey, keyPreview != nil { keyCard }
                        PrimaryButton(title: "Encrypt and add", icon: .lock,
                                      disabled: !canSubmit) { submit() }
                        Text("Nothing is written to disk until you press this. Sentinel derives addresses on the device and stores only public addresses in scan history.")
                            .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.padding)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Add a wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.muted)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }.foregroundStyle(Theme.violetLight)
                }
            }
        }
        .presentationBackground(.clear)
    }

    private var canSubmit: Bool {
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch kind {
        case .mnemonic: return validation == .valid
        case .privateKey: return keyPreview != nil
        default: return true
        }
    }

    private var picker: some View {
        HStack(spacing: 8) {
            ForEach([VaultKind.mnemonic, .privateKey], id: \.self) { option in
                Button {
                    withAnimation(Motion.snappy) { kind = option }
                } label: {
                    VStack(spacing: 4) {
                        IconView(icon: option == .mnemonic ? .key : .lock, size: 18, weight: 2,
                                 color: kind == option ? .white : Theme.muted)
                        Text(option == .mnemonic ? "Recovery phrase" : "Private key")
                            .font(Theme.Font.tiny)
                            .foregroundStyle(kind == option ? .white : Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                            .fill(kind == option ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.glassStrong))
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.97))
            }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NAME").font(Theme.Font.tiny).tracking(1).foregroundStyle(Theme.muted)
                TextField(kind == .mnemonic ? "Main wallet" : "Imported key", text: $label)
                    .font(Theme.Font.body)
                    .focused($focus, equals: .label)
                    .padding(12)
                    .glass(radius: Theme.radiusMedium, strength: 0.9)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .mnemonic ? "RECOVERY PHRASE" : "PRIVATE KEY")
                    .font(Theme.Font.tiny).tracking(1).foregroundStyle(Theme.muted)
                TextEditor(text: $secret)
                    .font(Theme.Font.mono(14))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: kind == .mnemonic ? 110 : 74)
                    .padding(10)
                    .glass(radius: Theme.radiusMedium, strength: 0.9)
                    .focused($focus, equals: .secret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .overlay(alignment: .topLeading) {
                        if secret.isEmpty {
                            Text(kind == .mnemonic ? "twelve or twenty-four words, separated by spaces" : "64 hex characters, or a WIF key starting with 5, K or L")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.mutedDim)
                                .padding(.horizontal, 15).padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
                if !suggestions.isEmpty {
                    HStack(spacing: 6) {
                        Text("Did you mean").font(Theme.Font.tiny).foregroundStyle(Theme.muted)
                        ForEach(suggestions.prefix(4), id: \.self) { word in
                            Chip(text: word, tint: Theme.amber)
                        }
                    }
                }
            }

            if kind == .mnemonic {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(Motion.smooth) { showPassphrase.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            IconView(icon: .plus, size: 13, weight: 2.2, color: Theme.violetLight)
                            Text(showPassphrase ? "Remove the BIP-39 passphrase" : "Add a BIP-39 passphrase")
                                .font(Theme.Font.caption).foregroundStyle(Theme.violetLight)
                            Spacer()
                        }
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    if showPassphrase {
                        TextField("passphrase", text: $passphrase)
                            .font(Theme.Font.mono(14))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .passphrase)
                            .padding(12)
                            .glass(radius: Theme.radiusMedium, strength: 0.9)
                        Text("A passphrase produces completely different addresses. It is stored as its own encrypted item.")
                            .font(Theme.Font.tiny).foregroundStyle(Theme.mutedDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .glassCard(radius: Theme.radiusLarge, strength: 0.75, padding: 14)
    }

    private func validationCard(_ result: BIP39.ValidationResult) -> some View {
        let valid = result == .valid
        return HStack(alignment: .top, spacing: 11) {
            IconView(icon: valid ? .check : .alert, size: 17, weight: 2.2,
                     color: valid ? Theme.green : Theme.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text(valid ? "Checksum verified" : "Not valid yet")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(valid ? Theme.green : Theme.amber)
                Text(result.explanation)
                    .font(Theme.Font.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .glassCard(radius: Theme.radiusMedium, strength: 0.6, padding: 13)
    }

    private var keyCard: some View {
        HStack(alignment: .top, spacing: 11) {
            IconView(icon: .check, size: 17, weight: 2.2, color: Theme.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Key accepted").font(Theme.Font.bodyMedium).foregroundStyle(Theme.green)
                Text("\(keyPreview?.compressed == true ? "Compressed" : "Uncompressed") · \(keyPreview?.mainnet == true ? "mainnet" : "testnet") · every EVM chain plus Bitcoin uses it.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .glassCard(radius: Theme.radiusMedium, strength: 0.6, padding: 13)
    }

    private func submit() {
        let name = label.trimmingCharacters(in: .whitespaces)
        let finalLabel = name.isEmpty ? (kind == .mnemonic ? "Recovery phrase" : "Imported key") : name
        if state.addWallet(kind: kind, label: finalLabel, secret: secret, passphrase: passphrase) {
            dismiss()
        }
    }
}
