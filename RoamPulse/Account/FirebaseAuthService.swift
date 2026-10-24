import FirebaseAuth
import Foundation

// Email/password login using Firebase Auth
@MainActor
final class FirebaseAuthService: AuthService {
    private var listener: AuthStateDidChangeListenerHandle?

    private var auth: Auth { Auth.auth() }

    var currentUser: AppUser? {
        auth.currentUser.map(AppUser.init(firebaseUser:))
    }

    func observeUser(_ onChange: @escaping (AppUser?) -> Void) {
        if let listener {
            auth.removeStateDidChangeListener(listener)
        }
        // Called once straight away, then on every sign in / sign out
        listener = auth.addStateDidChangeListener { _, user in
            MainActor.assumeIsolated {
                onChange(user.map(AppUser.init(firebaseUser:)))
            }
        }
    }

    func signUp(name: String, email: String, password: String) async throws -> AppUser {
        let user: User
        do {
            user = try await auth.createUser(withEmail: email, password: password).user
        } catch {
            throw Self.authError(from: error)
        }

        // If this fails the account still works, name just falls back to the email
        let change = user.createProfileChangeRequest()
        change.displayName = name
        try? await change.commitChanges()

        return AppUser(uid: user.uid, email: user.email ?? email, displayName: name)
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        do {
            let user = try await auth.signIn(withEmail: email, password: password).user
            return AppUser(firebaseUser: user)
        } catch {
            throw Self.authError(from: error)
        }
    }

    func sendPasswordReset(to email: String) async throws {
        do {
            try await auth.sendPasswordReset(withEmail: email)
        } catch {
            throw Self.authError(from: error)
        }
    }

    func signOut() throws {
        do {
            try auth.signOut()
        } catch {
            throw Self.authError(from: error)
        }
    }

    func updateDisplayName(_ name: String) async throws -> AppUser {
        guard let user = auth.currentUser else { throw AuthError.notConfigured }
        let change = user.createProfileChangeRequest()
        change.displayName = name
        do {
            try await change.commitChanges()
        } catch {
            throw Self.authError(from: error)
        }
        return AppUser(uid: user.uid, email: user.email ?? "", displayName: name)
    }

    func reauthenticate(password: String) async throws {
        guard let user = auth.currentUser, let email = user.email else { throw AuthError.notConfigured }
        do {
            _ = try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: password))
        } catch {
            throw Self.authError(from: error)
        }
    }

    func deleteAccount() async throws {
        guard let user = auth.currentUser else { return }
        do {
            try await user.delete()
        } catch {
            throw Self.authError(from: error)
        }
    }

    static func authError(from error: Error) -> AuthError {
        let nsError = error as NSError
        print("Firebase Auth error:", nsError)
        guard nsError.domain == AuthErrors.domain, let code = AuthErrorCode(rawValue: nsError.code) else {
            return .other(error.localizedDescription)
        }
        switch code {
        case .operationNotAllowed: return .signInMethodNotEnabled
        case .requiresRecentLogin: return .needsRecentSignIn
        // Firebase reports a missing Auth setup as a generic internal error
        case .internalError where String(describing: nsError).contains("CONFIGURATION_NOT_FOUND"):
            return .signInMethodNotEnabled
        case .invalidEmail: return .invalidEmail
        case .wrongPassword, .userNotFound, .invalidCredential: return .wrongCredentials
        case .emailAlreadyInUse: return .emailAlreadyInUse
        case .weakPassword: return .weakPassword
        case .networkError: return .network
        case .tooManyRequests: return .tooManyAttempts
        case .userDisabled: return .accountDisabled
        default: return .other(error.localizedDescription)
        }
    }
}

private extension AppUser {
    init(firebaseUser user: User) {
        self.init(uid: user.uid, email: user.email ?? "", displayName: user.displayName)
    }
}
