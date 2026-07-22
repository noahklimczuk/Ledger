import Foundation
import LocalAuthentication
import Observation

@MainActor
@Observable
final class AppLockService {
    enum LockState: Equatable {
        case locked
        case unlocked
        case unavailable(String)
    }

    private(set) var state: LockState = .locked

    var isUnlocked: Bool {
        state == .unlocked
    }

    func lock() {
        state = .locked
    }

    /// Authenticate with the device's passcode or password, skipping any biometric prompt.
    @discardableResult
    func authenticateWithPasscode() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            state = .unavailable("No passcode or biometrics are set up on this device.")
            return false
        }
        return await evaluate(context, policy: .deviceOwnerAuthentication)
    }

    @discardableResult
    func authenticate() async -> Bool {
        let context = LAContext()
        var policyError: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) {
            return await evaluate(context, policy: .deviceOwnerAuthenticationWithBiometrics)
        }

        // No biometrics enrolled/available on this device. Fall back to the system passcode
        // prompt so the app is still usable; there is no in-app PIN entry screen in this phase.
        let fallbackContext = LAContext()
        var fallbackError: NSError?
        guard fallbackContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fallbackError) else {
            state = .unavailable("No passcode or biometrics are set up on this device.")
            return false
        }
        return await evaluate(fallbackContext, policy: .deviceOwnerAuthentication)
    }

    private func evaluate(_ context: LAContext, policy: LAPolicy) async -> Bool {
        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: "Unlock Ledger")
            state = success ? .unlocked : .locked
            return success
        } catch {
            state = .locked
            return false
        }
    }
}
