import SwiftUI

@main
struct SentinelWalletApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(Theme.violet)
                .screenShield()
                .onChange(of: scenePhase) { _, phase in
                    // A wallet should not be readable from the app switcher, and an unlocked
                    // vault should not survive being backgrounded for long.
                    if phase == .background, state.settings.autoLockOnBackground, !state.isLocked {
                        state.lock()
                    }
                }
        }
    }
}
