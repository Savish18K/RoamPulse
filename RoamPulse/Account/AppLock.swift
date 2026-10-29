import Foundation
import LocalAuthentication
import Observation

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
    case noPasscode
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noPasscode: "Set a device passcode in Settings to use App Lock."
        case .cancelled: nil
        case .failed(let message): message
        }
    }
}

// Face ID / Touch ID behind a protocol so tests can fake it
@MainActor
protocol DeviceAuthenticating {
    var biometry: Biometry { get }
    func canAuthenticate() -> Bool
    func authenticate(reason: String) async throws
}

// Tries Face ID first, falls back to the passcode
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

// Optional app lock from Settings, locks on launch and after "Require after" in the background
@MainActor
@Observable
final class AppLock {
    private(set) var isLocked = false
    private(set) var isEnabled: Bool
    private(set) var isAuthenticating = false
    private(set) var errorMessage: String?
    // 0 means lock straight away
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

    // Returns false if the user couldn't confirm it's them
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

    func lockOnLaunch() {
        isLocked = isEnabled
    }

    func didEnterBackground() {
        backgroundedAt = clock.now
    }

    func didBecomeActive() {
        defer { backgroundedAt = nil }
        guard isEnabled, let since = backgroundedAt else { return }
        if clock.now.timeIntervalSince(since) >= Double(delayMinutes) * 60 {
            isLocked = true
        }
    }

    // Nothing to protect after sign out
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

    // User cancelling isn't an error
    private static func message(for error: Error) -> String? {
        if let error = error as? AppLockError {
            return error.errorDescription
        }
        return error.localizedDescription
    }
}
