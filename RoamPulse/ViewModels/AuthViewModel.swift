import Foundation
import Observation

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
    private(set) var errorMessage: String?
    // e.g. after sending a reset email
    private(set) var infoMessage: String?
    // Don't show errors until the first submit
    private(set) var showsProblems = false

    private let session: AppSession

    init(session: AppSession) {
        self.session = session
    }

    var isCloudAvailable: Bool { session.isCloudAvailable }

    var isNewAccount: Bool { mode == .signUp }

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
