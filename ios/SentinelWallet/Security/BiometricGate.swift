import LocalAuthentication

/// Face ID / Touch ID gate in front of the things that reveal secrets.
///
/// This is a second door, not the only one: the vault password is still required to open the
/// vault at all. If the device has no biometrics configured the gate reports `unavailable`
/// and the UI falls back to the password prompt alone.
enum BiometricGate {
    enum Outcome: Equatable {
        case success
        case cancelled
        case unavailable
        case failed(String)
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Biometrics"
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static func authenticate(reason: String) async -> Outcome {
        let context = LAContext()
        context.localizedFallbackTitle = "Use the vault password"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .unavailable
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                     localizedReason: reason)
            return ok ? .success : .cancelled
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel: return .cancelled
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout: return .unavailable
            default: return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
