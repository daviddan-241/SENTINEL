import SwiftUI

/// Three tabs, a drawer, and one glass bar at the bottom.
///
/// The tab bar is drawn by hand rather than using `TabView`'s, because the design needs a
/// morphing pill behind the selected tab, per-tab glyph animation, and a blur that follows
/// the scroll behind it. Everything else — the drawer, the toasts, the lock screen — is
/// layered on top of whichever tab is showing.
struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var tab: Tab = .portfolio
    @Namespace private var pillNamespace

    enum Tab: String, CaseIterable, Identifiable {
        case portfolio, scan, wallets

        var id: String { rawValue }
        var title: String {
            switch self {
            case .portfolio: return "Portfolio"
            case .scan: return "Scan"
            case .wallets: return "Wallets"
            }
        }
        var icon: Icon {
            switch self {
            case .portfolio: return .layers
            case .scan: return .scan
            case .wallets: return .vault
            }
        }
    }

    var body: some View {
        ZStack {
            GlassBackdrop()

            Group {
                if state.isLocked {
                    LockView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    content
                        .transition(.opacity)
                }
            }

            if state.isDrawerOpen {
                DrawerOverlay()
                    .zIndex(2)
            }

            if let toast = state.toast {
                VStack {
                    ToastView(toast: toast)
                        .onTapGesture { state.dismissToast() }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .padding(.top, 6)
                .zIndex(3)
            }
        }
        .animation(Motion.smooth, value: state.isLocked)
        .animation(Motion.smooth, value: state.isDrawerOpen)
        .animation(Motion.bouncy, value: state.toast)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HeaderBar(tab: $tab)
            ZStack {
                switch tab {
                case .portfolio:
                    PortfolioView(goToScan: { tab = .scan }, goToWallets: { tab = .wallets })
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                removal: .opacity))
                case .scan:
                    ScanView()
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                case .wallets:
                    WalletsView()
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlassTabBar(selection: $tab, namespace: pillNamespace)
        }
    }
}

/// The top bar: brand, lock state, and the drawer handle.
private struct HeaderBar: View {
    @EnvironmentObject private var state: AppState
    @Binding var tab: RootView.Tab

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(Motion.smooth) { state.isDrawerOpen = true }
            } label: {
                HStack(spacing: 10) {
                    IconView(icon: .shield, size: 20, weight: 2, color: Theme.violetLight)
                        .frame(width: 38, height: 38)
                        .background {
                            Circle().fill(LinearGradient(colors: [Theme.violet.opacity(0.35), Theme.cyan.opacity(0.18)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        .overlay { Circle().strokeBorder(Theme.borderBright, lineWidth: Theme.hairline) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sentinel")
                            .font(Theme.Font.heading)
                            .foregroundStyle(Theme.text)
                        HStack(spacing: 5) {
                            if state.progress.isRunning {
                                LiveDot(tint: Theme.cyan)
                                Text("scanning").font(Theme.Font.tiny).foregroundStyle(Theme.cyan)
                            } else {
                                LiveDot(tint: Theme.green)
                                Text("vault unlocked").font(Theme.Font.tiny).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
            .buttonStyle(PressableStyle(scale: 0.98))

            Spacer()

            if state.progress.isRunning {
                ProgressRing(progress: state.progress.fraction, tint: Theme.cyan)
                    .frame(width: 34, height: 34)
                    .transition(.scale.combined(with: .opacity))
            } else {
                IconButton(icon: .refresh, size: 38, tint: Theme.text) {
                    state.scanAll()
                    withAnimation(Motion.smooth) { tab = .scan }
                }
            }
            IconButton(icon: .lock, size: 38, tint: Theme.muted) { state.lock() }
        }
        .padding(.horizontal, Theme.padding)
        .padding(.bottom, 6)
        .padding(.top, 4)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.55)
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// The three-tab glass bar.
private struct GlassTabBar: View {
    @Binding var selection: RootView.Tab
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RootView.Tab.allCases) { tab in
                let selected = tab == selection
                Button {
                    withAnimation(Motion.bouncy) { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        IconView(icon: tab.icon, size: 21, weight: selected ? 2.3 : 1.9,
                                 color: selected ? .white : Theme.muted)
                            .scaleEffect(selected ? 1.06 : 1)
                        Text(tab.title)
                            .font(Theme.Font.tiny)
                            .foregroundStyle(selected ? .white : Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                                .fill(LinearGradient(colors: [Theme.violet.opacity(0.92), Theme.cyan.opacity(0.72)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .matchedGeometryEffect(id: "tab-pill", in: namespace)
                                .shadow(color: Theme.violet.opacity(0.45), radius: 14, y: 6)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.94))
                .sensoryFeedback(.selection, trigger: selection)
            }
        }
        .padding(6)
        .glass(radius: Theme.radiusLarge, strength: 1.15)
        .padding(.horizontal, Theme.padding)
        .padding(.bottom, 6)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.001)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// The side panel: everything that is not one of the three tabs.
private struct DrawerOverlay: View {
    @EnvironmentObject private var state: AppState
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                DrawerContent()
                    .frame(width: min(330, proxy.size.width * 0.86))
                    .background {
                        Rectangle().fill(.ultraThinMaterial)
                            .overlay(Theme.background.opacity(0.72))
                            .ignoresSafeArea()
                    }
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Theme.borderBright).frame(width: Theme.hairline).ignoresSafeArea()
                    }
                    .offset(x: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = min(0, value.translation.width)
                            }
                            .onEnded { value in
                                if value.translation.width < -70 {
                                    close()
                                } else {
                                    withAnimation(Motion.smooth) { dragOffset = 0 }
                                }
                            }
                    )
                    .transition(.move(edge: .leading))
            }
        }
    }

    private func close() {
        withAnimation(Motion.smooth) {
            dragOffset = 0
            state.isDrawerOpen = false
        }
    }
}
