import SwiftUI

/// The frosted surface everything sits on: a soft white fill over a blurred backdrop, a
/// hairline border, and a highlight along the top edge so it catches light like real glass.
struct GlassSurface: ViewModifier {
    var radius: CGFloat = Theme.radiusLarge
    var strength: Double = 1
    var interactive: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.glassStrong.opacity(strength))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [Theme.borderBright, Theme.border],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: Theme.hairline)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func glass(radius: CGFloat = Theme.radiusLarge, strength: Double = 1) -> some View {
        modifier(GlassSurface(radius: radius, strength: strength))
    }

    /// Standard inner padding for a glass card.
    func glassCard(radius: CGFloat = Theme.radiusLarge, strength: Double = 1,
                   padding: CGFloat = Theme.padding) -> some View {
        self.padding(padding).glass(radius: radius, strength: strength)
    }
}

/// A card with a small tinted glow behind it — used for the headline numbers.
struct GlassCard<Content: View>: View {
    var tint: Color = Theme.violet
    var radius: CGFloat = Theme.radiusLarge
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(LinearGradient(colors: [tint.opacity(0.22), Theme.glass],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Theme.borderBright, lineWidth: Theme.hairline)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: tint.opacity(0.18), radius: 22, x: 0, y: 12)
    }
}

/// Filled accent button — one per screen, at most.
struct PrimaryButton: View {
    let title: String
    var icon: Icon?
    var busy: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let icon {
                    IconView(icon: icon, size: 18, weight: 2, color: .white)
                }
                Text(title).font(Theme.Font.bodyMedium).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: Theme.hairline)
            }
            .shadow(color: Theme.violet.opacity(0.35), radius: 16, y: 8)
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled || busy)
    }
}

/// Quiet secondary action.
struct SecondaryButton: View {
    let title: String
    var icon: Icon?
    var tint: Color = Theme.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { IconView(icon: icon, size: 17, color: tint) }
                Text(title).font(Theme.Font.bodyMedium).foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glass(radius: Theme.radiusMedium, strength: 0.8)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Small round glass button, used in headers.
struct IconButton: View {
    let icon: Icon
    var size: CGFloat = 40
    var tint: Color = Theme.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(icon: icon, size: size * 0.46, color: tint)
                .frame(width: size, height: size)
                .glass(radius: size / 2, strength: 0.9)
        }
        .buttonStyle(PressableStyle())
    }
}

/// A tinted pill: network names, states, token symbols.
struct Chip: View {
    let text: String
    var tint: Color = Theme.violet
    var icon: Icon?
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon { IconView(icon: icon, size: 12, weight: 2.2, color: filled ? .white : tint) }
            Text(text)
                .font(Theme.Font.tiny)
                .foregroundStyle(filled ? .white : tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5.5)
        .background {
            Capsule().fill(filled ? AnyShapeStyle(tint.opacity(0.85)) : AnyShapeStyle(tint.opacity(0.14)))
        }
        .overlay {
            Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.34), lineWidth: Theme.hairline)
        }
    }
}

/// Section heading with an optional trailing action.
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var trailing: AnyView?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(Theme.Font.tiny)
                    .tracking(1.1)
                    .foregroundStyle(Theme.muted)
                if let subtitle {
                    Text(subtitle).font(Theme.Font.caption).foregroundStyle(Theme.mutedDim)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

/// A label and value row, the workhorse of the detail panels.
struct DetailRow: View {
    let label: String
    let value: String
    var mono: Bool = false
    var tint: Color = Theme.text
    var icon: Icon?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            if let icon { IconView(icon: icon, size: 15, color: Theme.muted) }
            Text(label).font(Theme.Font.caption).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? Theme.Font.mono(13) : Theme.Font.bodyMedium)
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.middle)
            if action != nil { IconView(icon: .chevron, size: 13, weight: 2, color: Theme.mutedDim) }
        }
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }
}

/// The dark backdrop with slow-moving colour clouds — cheap to draw, and it is what makes
/// the glass read as glass.
struct GlassBackdrop: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Theme.violet.opacity(0.32))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: drift ? 90 : -110, y: drift ? -230 : -170)
            Circle()
                .fill(Theme.cyan.opacity(0.24))
                .frame(width: 380, height: 380)
                .blur(radius: 130)
                .offset(x: drift ? -120 : 100, y: drift ? 220 : 160)
            Circle()
                .fill(Theme.pink.opacity(0.16))
                .frame(width: 320, height: 320)
                .blur(radius: 140)
                .offset(x: drift ? 120 : -60, y: drift ? 60 : -40)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// A tile used for the secondary statistics under the headline number.
struct StatTile: View {
    let label: String
    let value: String
    var tint: Color = Theme.text
    var icon: Icon?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let icon { IconView(icon: icon, size: 12, weight: 2, color: Theme.muted) }
                Text(label.uppercased()).font(Theme.Font.tiny).tracking(0.8).foregroundStyle(Theme.muted)
            }
            Text(value).font(Theme.Font.heading).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: Theme.radiusMedium, strength: 0.7, padding: 13)
    }
}

/// Empty-state block: icon, headline, one sentence, optional action.
struct EmptyStateView: View {
    let icon: Icon
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            IconView(icon: icon, size: 30, weight: 1.6, color: Theme.violetLight)
                .frame(width: 62, height: 62)
                .glass(radius: 31, strength: 1.1)
            Text(title).font(Theme.Font.heading).foregroundStyle(Theme.text)
            Text(message)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, action: action).padding(.top, 4).frame(maxWidth: 260)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .glass(radius: Theme.radiusLarge, strength: 0.5)
    }
}
