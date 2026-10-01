import SwiftUI

/// Hides the app's content in the app switcher and while the device is locking, so a
/// screenshot of the switcher cannot show a phrase or a balance.
struct ScreenShield: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        ZStack {
            content
            if scenePhase != .active {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        VStack(spacing: 10) {
                            IconView(icon: .lock, size: 30, weight: 1.8, color: Theme.violetLight)
                            Text("Sentinel is locked")
                                .font(Theme.Font.heading).foregroundStyle(Theme.text)
                        }
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: scenePhase)
    }
}

extension View {
    func screenShield() -> some View { modifier(ScreenShield()) }
}
