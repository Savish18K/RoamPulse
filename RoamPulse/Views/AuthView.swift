import SwiftUI

// MARK: - AuthView

/// Sign in or create an account. Shown after onboarding whenever nobody is signed in.
struct AuthView: View {
    @State private var viewModel: AuthViewModel
    @State private var showsPassword = false
    @FocusState private var focus: Field?

    private enum Field {
        case name, email, password
    }

    init(viewModel: AuthViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                VStack(alignment: .leading, spacing: 18) {
                    SegmentedTabs(options: AuthViewModel.Mode.allCases.map(\.title), selection: modeIndex)

                    if !viewModel.isCloudAvailable {
                        banner(AuthError.notConfigured.errorDescription ?? "", icon: "exclamationmark.triangle", color: .orange)
                    }

                    if viewModel.isNewAccount {
                        field("Name", problem: viewModel.nameProblem) {
                            TextField("Savishka Kuruppu", text: $viewModel.name)
                                .textContentType(.name)
                                .submitLabel(.next)
                                .focused($focus, equals: .name)
                                .onSubmit { focus = .email }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    field("Email", problem: viewModel.emailProblem) {
                        TextField("you@example.com", text: $viewModel.email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .email)
                            .onSubmit { focus = .password }
                    }

                    field("Password", problem: viewModel.passwordProblem) {
                        passwordField
                    }

                    if let error = viewModel.errorMessage {
                        banner(error, icon: "exclamationmark.circle", color: .red)
                    }
                    if let info = viewModel.infoMessage {
                        banner(info, icon: "envelope.badge", color: .green)
                    }

                    Button {
                        submit()
                    } label: {
                        if viewModel.isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Text(viewModel.mode.title)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.isWorking)

                    if viewModel.mode == .signIn {
                        Button("Forgot password?") {
                            Task { await viewModel.sendPasswordReset() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .disabled(viewModel.isWorking)
                    }

                    Label("Your trips are backed up to your account. Voice notes, photos and transcripts stay on this iPhone.",
                          systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
            .animation(.snappy, value: viewModel.mode)
            .animation(.snappy, value: viewModel.errorMessage)
        }
        .ignoresSafeArea(edges: .top)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            PhotoView(photo: .hillTrain, showsSymbol: false)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.isNewAccount ? "Create your account" : "Welcome back")
                    .font(.largeTitle.bold())
                Text(viewModel.isNewAccount
                     ? "Sign up to back up your trips and use them on any device."
                     : "Sign in to see your trips, plans and expenses.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .frame(height: 280)
        .accessibilityElement(children: .combine)
    }

    private var passwordField: some View {
        HStack {
            Group {
                if showsPassword {
                    TextField("Password", text: $viewModel.password)
                } else {
                    SecureField("Password", text: $viewModel.password)
                }
            }
            .textContentType(viewModel.isNewAccount ? .newPassword : .password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($focus, equals: .password)
            .onSubmit(submit)

            Button {
                showsPassword.toggle()
            } label: {
                Image(systemName: showsPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -12)
            .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
        }
    }

    private var modeIndex: Binding<Int> {
        Binding(
            get: { viewModel.mode.rawValue },
            set: { viewModel.mode = AuthViewModel.Mode(rawValue: $0) ?? .signIn }
        )
    }

    private func submit() {
        focus = nil
        Task { await viewModel.submit() }
    }

    /// Label, field and (after a failed try) the problem in red.
    private func field<Content: View>(_ label: String, problem: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label)
            content()
                .fieldStyle()
                .overlay {
                    if problem != nil {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.red.opacity(0.8))
                    }
                }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func banner(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(color)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    AuthView(viewModel: AuthViewModel(session: dependencies.session))
        .preferredColorScheme(.dark)
}
