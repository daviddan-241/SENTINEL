import UIKit

/// Copies a secret, then takes it back.
///
/// Anything copied to the iOS clipboard is readable by every other app and shows up in the
/// universal-clipboard handoff, so a recovery phrase must not stay there. Ninety seconds is
/// long enough to paste into a password manager and short enough to matter.
actor ClipboardGuard {
    static let shared = ClipboardGuard()

    private var task: Task<Void, Never>?
    private var lastCopied: String?
    private let lifetime: TimeInterval

    init(lifetime: TimeInterval = 90) {
        self.lifetime = lifetime
    }

    func copy(_ value: String) {
        UIPasteboard.general.string = value
        lastCopied = value
        task?.cancel()
        task = Task { [lifetime] in
            try? await Task.sleep(nanoseconds: UInt64(lifetime * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.clearIfUnchanged()
        }
    }

    /// Only clears the clipboard if it still holds what we put there — never wipes something
    /// the user copied themselves in the meantime.
    private func clearIfUnchanged() {
        if let lastCopied, UIPasteboard.general.string == lastCopied {
            UIPasteboard.general.items = []
        }
        lastCopied = nil
    }

    func clearNow() {
        task?.cancel()
        clearIfUnchanged()
    }
}
