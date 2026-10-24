import Foundation

// Our own user type so the rest of the app doesn't depend on Firebase
struct AppUser: Hashable {
    // Firebase uid, also used as the database folder name
    let uid: String
    var email: String
    var displayName: String?

    // Falls back to the start of the email if no name was saved
    var name: String {
        if let displayName, !displayName.trimmed.isEmpty {
            return displayName.trimmed
        }
        return email.components(separatedBy: "@").first ?? email
    }

    var firstName: String { name.components(separatedBy: " ").first ?? name }

    var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2, let first = words[0].first, let second = words[1].first {
            return "\(first)\(second)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// Auth protocol, Firebase in the app and a fake in tests
@MainActor
protocol AuthService: AnyObject {
    var currentUser: AppUser? { get }
    func observeUser(_ onChange: @escaping (AppUser?) -> Void)
    func signUp(name: String, email: String, password: String) async throws -> AppUser
    func signIn(email: String, password: String) async throws -> AppUser
    func sendPasswordReset(to email: String) async throws
    func signOut() throws

    func updateDisplayName(_ name: String) async throws -> AppUser
    // Firebase needs a recent sign in before deleting an account
    func reauthenticate(password: String) async throws
    func deleteAccount() async throws
}

enum AuthError: LocalizedError, Equatable {
    case notConfigured
    case invalidEmail
    // Firebase doesn't say which one was wrong (email enumeration protection)
    case wrongCredentials
    case emailAlreadyInUse
    case weakPassword
    case network
    case tooManyAttempts
    case accountDisabled
    case signInMethodNotEnabled
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

// Returns an error message or nil if the value is ok
enum AuthValidator {
    // Firebase allows 6 but 8 is safer
    static let minimumPasswordLength = 8

    static func nameProblem(_ name: String) -> String? {
        name.trimmed.isEmpty ? "Enter your name." : nil
    }

    static func emailProblem(_ email: String) -> String? {
        let email = email.trimmed
        if email.isEmpty { return "Enter your email address." }
        // Basic check only, Firebase does the real one
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) == nil ? "Enter a valid email address." : nil
    }

    static func passwordProblem(_ password: String, isNewAccount: Bool) -> String? {
        if password.isEmpty { return "Enter your password." }
        if isNewAccount && password.count < minimumPasswordLength {
            return "Use at least \(minimumPasswordLength) characters."
        }
        return nil
    }
}

// Used when Firebase isn't set up (and in the test host)
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

// For previews
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
