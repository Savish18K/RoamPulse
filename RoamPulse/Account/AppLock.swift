import Foundation
import LocalAuthentication
import Observation

/// Which biometric sensor the iPhone has.
enum Biometry: Equatable {
    case faceID, touchID, opticID, none

    var name: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .none: "Passcode"
        }
    }

    var icon: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .none: "lock"
        }
    }
}

enum AppLockError: LocalizedError, Equatable {
    /// The iPhone has no passcode, so nothing can protect the app.
    case noPasscode
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noPasscode: "Set a passcode in the iPhone's Settings to use App Lock."
        case .cancelled: nil
        case .failed(let message): message
        }
    }
}

/// Face ID / Touch ID with the passcode as a backup, behind a protocol so tests can say yes or no.
@MainActor
protocol DeviceAuthenticating {
    var biometry: Biometry { get }
    /// False when the iPhone has no passcode set.
    func canAuthenticate() -> Bool
    func authenticate(reason: String) async throws
}

/// LocalAuthentication. `.deviceOwnerAuthentication` tries Face ID or Touch ID first and offers
/// the passcode if that fails, so nobody is locked out if their face isn't recognised.
@MainActor
struct LocalDeviceAuthenticator: DeviceAuthenticating {
    var biometry: Biometry {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    func canAuthenticate() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel: throw AppLockError.cancelled
            case .passcodeNotSet: throw AppLockError.noPasscode
            default: throw AppLockError.failed(error.localizedDescription)
            }
        }
    }
}

/// The optional app lock (Settings → Privacy).
///
/// When it is on, the app locks on launch and when it comes back after being in the background for
/// longer than "Require after". The content is also hidden in the app switcher. Turning the lock on
/// or off needs Face ID / Touch ID / passcode, so someone borrowing the phone can't just switch it off.
@MainActor
@Observable
final class AppLock {
    private(set) var isLocked = false
    private(set) var isEnabled: Bool
    private(set) var isAuthenticating = false
    /// Why the last attempt failed, shown on the lock screen.
    private(set) var errorMessage: String?
    /// 0 = immediately, otherwise minutes in the background before locking.
    var delayMinutes: Int {
        didSet { defaults.set(delayMinutes, forKey: Key.delay) }
    }

    @ObservationIgnored private let authenticator: DeviceAuthenticating
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var backgroundedAt: Date?

    static let delayChoices = [0, 1, 5, 15]

    private enum Key {
        static let enabled = "appLockEnabled"
        static let delay = "lockDelayMinutes"
    }

    init(authenticator: DeviceAuthenticating, clock: Clock, defaults: UserDefaults = .standard) {
        self.authenticator = authenticator
        self.clock = clock
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.enabled)
        delayMinutes = defaults.integer(forKey: Key.delay)
    }

    var biometry: Biometry { authenticator.biometry }

    var canBeUsed: Bool { authenticator.canAuthenticate() }

    /// Returns false (and leaves the setting as it was) if the person couldn't confirm it's them.
    @discardableResult
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != isEnabled else { return true }
        errorMessage = nil
        guard authenticator.canAuthenticate() else {
            errorMessage = AppLockError.noPasscode.errorDescription
            return false
        }
        do {
            try await authenticator.authenticate(reason: enabled ? "Turn on App Lock for RoamPulse" : "Turn off App Lock")
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
        isEnabled = enabled
        defaults.set(enabled, forKey: Key.enabled)
        return true
    }

    /// The app opened with someone signed in.
    func lockOnLaunch() {
        isLocked = isEnabled
    }

    func didEnterBackground() {
        backgroundedAt = clock.now
    }

    /// Locks if the app was in the background for at least `delayMinutes`.
    func didBecomeActive() {
        defer { backgroundedAt = nil }
        guard isEnabled, let since = backgroundedAt else { return }
        if clock.now.timeIntervalSince(since) >= Double(delayMinutes) * 60 {
            isLocked = true
        }
    }

    /// Signed out: there is nothing to protect, and the next person shouldn't see a lock screen.
    func reset() {
        isLocked = false
        backgroundedAt = nil
        errorMessage = nil
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            try await authenticator.authenticate(reason: "Unlock your trips, memories and expenses")
            isLocked = false
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Cancelling isn't an error worth showing.
    private static func message(for error: Error) -> String? {
        if let error = error as? AppLockError {
            return error.errorDescription
        }
        return error.localizedDescription
    }
}
