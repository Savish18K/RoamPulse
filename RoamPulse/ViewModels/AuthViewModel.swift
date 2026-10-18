import Foundation
import Observation

/// The sign-in / create-account form.
@MainActor
@Observable
final class AuthViewModel {
    enum Mode: Int, CaseIterable {
        case signIn, signUp

        var title: String {
            switch self {
            case .signIn: "Sign In"
            case .signUp: "Create Account"
            }
        }
    }

    var mode: Mode = .signIn {
        didSet {
            guard mode != oldValue else { return }
            errorMessage = nil
            infoMessage = nil
            showsProblems = false
        }
    }
    var name = ""
    var email = ""
    var password = ""

    private(set) var isWorking = false
    /// Shown in red under the form, e.g. "The email or password is incorrect."
    private(set) var errorMessage: String?
    /// Shown in green, e.g. after sending a password reset email.
    private(set) var infoMessage: String?
    /// Field problems only appear after the first try, so the form doesn't open covered in red.
    private(set) var showsProblems = false

    private let session: AppSession

    init(session: AppSession) {
        self.session = session
    }

    var isCloudAvailable: Bool { session.isCloudAvailable }

    var isNewAccount: Bool { mode == .signUp }

    // MARK: Validation

    var nameProblem: String? {
        guard showsProblems, isNewAccount else { return nil }
        return AuthValidator.nameProblem(name)
    }

    var emailProblem: String? {
        showsProblems ? AuthValidator.emailProblem(email) : nil
    }

    var passwordProblem: String? {
        showsProblems ? AuthValidator.passwordProblem(password, isNewAccount: isNewAccount) : nil
    }

    var formIsValid: Bool {
        (!isNewAccount || AuthValidator.nameProblem(name) == nil)
            && AuthValidator.emailProblem(email) == nil
            && AuthValidator.passwordProblem(password, isNewAccount: isNewAccount) == nil
    }

    // MARK: Actions

    /// Signs in or creates the account. When it works, `AppSession` switches to the main app.
    func submit() async {
        showsProblems = true
        errorMessage = nil
        infoMessage = nil
        guard formIsValid, !isWorking else { return }

        isWorking = true
        defer { isWorking = false }
        do {
            switch mode {
            case .signIn:
                try await session.signIn(email: email.trimmed, password: password)
            case .signUp:
                try await session.signUp(name: name.trimmed, email: email.trimmed, password: password)
            }
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// "Forgot password?" sends Firebase's reset email to the address typed in the form.
    func sendPasswordReset() async {
        errorMessage = nil
        infoMessage = nil
        if let problem = AuthValidator.emailProblem(email) {
            errorMessage = "\(problem) We'll send the reset link there."
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            try await session.sendPasswordReset(to: email.trimmed)
            infoMessage = "If \(email.trimmed) has an account, a link to reset the password is on its way."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
