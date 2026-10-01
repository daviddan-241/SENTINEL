import SwiftUI

/// The secondary way in: paste any address and read it, without importing anything.
struct AddressLookupSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Paste an address")
                                .font(Theme.Font.heading).foregroundStyle(Theme.text)
                            Text("EVM, Bitcoin or Solana. Sentinel reads the chain; it never asks for a key.")
                                .font(Theme.Font.caption).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            TextField("0x… / bc1… / 1… / 4nFZ…", text: $state.lookupInput)
                                .font(Theme.Font.mono(14))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .focused($focused)
                                .submitLabel(.search)
                                .onSubmit { state.lookup() }
                                .padding(13)
                                .glass(radius: Theme.radiusMedium, strength: 0.9)
                            HStack(spacing: 10) {
                                PrimaryButton(title: "Look up", icon: .lookup, busy: state.lookupBusy) {
                                    focused = false
                                    state.lookup()
                                }
                                SecondaryButton(title: "Paste") {
                                    if let text = UIPasteboard.general.string {
                                        state.lookupInput = text
                                    }
                                }
                            }
                        }
                        .glassCard(radius: Theme.radiusLarge, strength: 0.8)

                        if let report = state.lookupResult {
                            AddressReportCard(report: report)
                        }
                    }
                    .padding(Theme.padding)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Address lookup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.violetLight)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.clear)
    }
}
