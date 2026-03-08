import Foundation
import LocalAuthentication

class AuthState: ObservableObject {
    @Published var isUnlocked = false
    @Published var authError: String?

    private(set) var authenticatedContext: LAContext?

    /// How long the app stays unlocked after authentication (seconds)
    private let lockTimeout: TimeInterval = 60
    private var lockTimer: Timer?

    func authenticate() {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Do NOT auto-unlock — require authentication
            DispatchQueue.main.async {
                self.authError = error?.localizedDescription ?? "Authentication not available on this device."
            }
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock OpenAuthenticator to view your codes"
        ) { success, evalError in
            DispatchQueue.main.async {
                if success {
                    self.authenticatedContext = context
                    self.isUnlocked = true
                    self.authError = nil
                    self.startLockTimer()
                } else {
                    self.authError = evalError?.localizedDescription
                }
            }
        }
    }

    func lock() {
        isUnlocked = false
        authenticatedContext = nil
        lockTimer?.invalidate()
        lockTimer = nil
    }

    private func startLockTimer() {
        lockTimer?.invalidate()
        lockTimer = Timer.scheduledTimer(withTimeInterval: lockTimeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.lock()
            }
        }
    }

    /// Call when the user interacts — resets the auto-lock countdown
    func resetLockTimer() {
        if isUnlocked {
            startLockTimer()
        }
    }
}
