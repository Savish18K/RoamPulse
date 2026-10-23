import Foundation

// MARK: - AppUser

/// The signed-in person. A plain struct, so nothing above `FirebaseAuthService` depends on Firebase.
struct AppUser: Hashable {
    /// Firebase's id for the account. It never changes, so it names the account's database and cloud data.
    let uid: String
    var email: String
    var displayName: String?

    /// "Savishka Kuruppu", or the part of the email before the @ when no name was saved.
    var name: String {
        if let displayName, !displayName.trimmed.isEmpty {
            return displayName.trimmed
        }
        return email.components(separatedBy: "@").first ?? email
    }

    var firstName: String { name.components(separatedBy: " ").first ?? name }

    /// "Savishka Kuruppu" → "SK", "savishka" → "SA".
    var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2, let first = words[0].first, let second = words[1].first {
            return "\(first)\(second)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - AuthService

/// Signing in, signing up and signing out.
///
/// The app uses `FirebaseAuthService`. Tests use a fake, and the app falls back to
/// `UnavailableAuthService` when Firebase hasn't been set up (no GoogleService-Info.plist).
@MainActor
protocol AuthService: AnyObject {
    var currentUser: AppUser? { get }
    /// Calls `onChange` with the current user, and again every time someone signs in or out.
    func observeUser(_ onChange: @escaping (AppUser?) -> Void)
    func signUp(name: String, email: String, password: String) async throws -> AppUser
    func signIn(email: String, password: String) async throws -> AppUser
    func sendPasswordReset(to email: String) async throws
    func signOut() throws

    /// Changes the name saved on the account.
    func updateDisplayName(_ name: String) async throws -> AppUser
    /// Checks the password again. Firebase needs a recent sign-in before deleting an account.
    func reauthenticate(password: String) async throws
    /// Deletes the signed-in account for good.
    func deleteAccount() async throws
}

// MARK: - AuthError

/// Sign-in problems in plain words. `FirebaseAuthService` turns Firebase's error codes into these.
enum AuthError: LocalizedError, Equatable {
    case notConfigured
    case invalidEmail
    /// Wrong email or wrong password. Firebase doesn't say which, so that nobody can find out
    /// whether an email has an account (email enumeration protection).
    case wrongCredentials
    case emailAlreadyInUse
    case weakPassword
    case network
    case tooManyAttempts
    case accountDisabled
    /// Email/Password sign-in isn't turned on in the Firebase console.
    case signInMethodNotEnabled
    /// Deleting an account needs a fresh sign-in.
    case needsRecentSignIn
    case other(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Sign-in isn't set up yet. Add GoogleService-Info.plist to the project (see README → Firebase setup)."
        case .invalidEmail: "That email address doesn't look right."
        case .wrongCredentials: "The email or password is incorrect."
        case .emailAlreadyInUse: "There is already an account with this email. Sign in instead."
        case .weakPassword: "Choose a stronger password with at least \(AuthValidator.minimumPasswordLength) characters."
        case .network: "Couldn't reach the server. Check your connection and try again."
        case .tooManyAttempts: "Too many attempts. Wait a few minutes and try again."
        case .accountDisabled: "This account has been disabled."
        case .needsRecentSignIn: "For your security, enter your password again."
        case .signInMethodNotEnabled:
            "Email sign-in isn't turned on for this Firebase project. In the Firebase console, open Authentication → Get started → Sign-in method → Email/Password."
        case .other(let message): message
        }
    }
}

// MARK: - AuthValidator

/// Checks the sign-in form before anything is sent. Each function returns a message, or nil if the value is fine.
enum AuthValidator {
    /// Firebase accepts 6, but 8 is the usual minimum for a reasonable password.
    static let minimumPasswordLength = 8

    static func nameProblem(_ name: String) -> String? {
        name.trimmed.isEmpty ? "Enter your name." : nil
    }

    static func emailProblem(_ email: String) -> String? {
        let email = email.trimmed
        if email.isEmpty { return "Enter your email address." }
        // Something@something.something, with no spaces. The server does the real check.
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) == nil ? "Enter a valid email address." : nil
    }

    /// New accounts need a long enough password; signing in only needs one to be typed.
    static func passwordProblem(_ password: String, isNewAccount: Bool) -> String? {
        if password.isEmpty { return "Enter your password." }
        if isNewAccount && password.count < minimumPasswordLength {
            return "Use at least \(minimumPasswordLength) characters."
        }
        return nil
    }
}

// MARK: - UnavailableAuthService

/// Used when Firebase isn't set up, and in the unit-test host app. Nobody is ever signed in,
/// and every action explains that sign-in isn't set up.
@MainActor
final class UnavailableAuthService: AuthService {
    var currentUser: AppUser? { nil }

    func observeUser(_ onChange: @escaping (AppUser?) -> Void) {
        onChange(nil)
    }

    func signUp(name: String, email: String, password: String) async throws -> AppUser {
        throw AuthError.notConfigured
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        throw AuthError.notConfigured
    }

    func sendPasswordReset(to email: String) async throws {
        throw AuthError.notConfigured
    }

    func signOut() throws {}
    func updateDisplayName(_ name: String) async throws -> AppUser { throw AuthError.notConfigured }
    func reauthenticate(password: String) async throws { throw AuthError.notConfigured }
    func deleteAccount() async throws { throw AuthError.notConfigured }
}

// MARK: - PreviewAuthService

/// Always signed in as the sample user. Used by SwiftUI previews.
@MainActor
final class PreviewAuthService: AuthService {
    let currentUser: AppUser? = AppUser(uid: "preview", email: SampleData.profile.email,
                                        displayName: SampleData.profile.fullName)

    func observeUser(_ onChange: @escaping (AppUser?) -> Void) {
        onChange(currentUser)
    }

    func signUp(name: String, email: String, password: String) async throws -> AppUser { try user() }
    func signIn(email: String, password: String) async throws -> AppUser { try user() }
    func sendPasswordReset(to email: String) async throws {}
    func signOut() throws {}
    func updateDisplayName(_ name: String) async throws -> AppUser { try user() }
    func reauthenticate(password: String) async throws {}
    func deleteAccount() async throws {}

    private func user() throws -> AppUser {
        guard let currentUser else { throw AuthError.notConfigured }
        return currentUser
    }
}
