import SwiftUI

struct OnboardingView: View {
    var onGetStarted: () -> Void

    private struct Feature: Identifiable {
        let icon: String
        let tint: Color
        let title: String
        let text: String
        var id: String { title }
    }

    private let features = [
        Feature(icon: "cylinder.split.1x2", tint: .blue, title: "Offline planning",
                text: "Access schedules, maps, and tickets without cellular data."),
        Feature(icon: "rectangle.split.2x1", tint: .green, title: "Cost splitting",
                text: "Record shared expenses instantly. Settle up in local currency."),
        Feature(icon: "mic", tint: .purple, title: "Voice journal",
                text: "Dictate travel memories. Auto-transcribed and mapped."),
        Feature(icon: "photo", tint: .cyan, title: "Landmark photos",
                text: "Recognises Sri Lankan landmarks on your phone and links photos to your plan."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(features) { feature in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: feature.icon)
                                .font(.title3)
                                .foregroundStyle(feature.tint)
                                .frame(width: 56, height: 56)
                                .background(Theme.fill, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.title).font(.headline)
                                Text(feature.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                Text("Sign in to back up and share your trips. Voice notes, photos and transcripts never leave this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Get Started", action: onGetStarted)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .background(Theme.background)
        }
    }

    private var header: some View {
        ZStack(alignment: .bottom) {
            PhotoView(photo: .nineArchBridge)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(spacing: 8) {
                Text("RoamPulse")
                    .font(.system(size: 44, weight: .bold))
                Text("Plan the trip, share the costs, keep the memories.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .frame(height: 380)
    }
}

#Preview {
    OnboardingView {}
        .preferredColorScheme(.dark)
}

/// Shown over the blurred app when App Lock is on. Asks for Face ID / Touch ID straight away;
/// if that fails, the system offers the passcode.
struct LockView: View {
    @Environment(AppLock.self) private var appLock

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock")
                .font(.title)
                .frame(width: 76, height: 76)
                .background(.ultraThinMaterial, in: Circle())
                .accessibilityHidden(true)
            Text("RoamPulse is locked")
                .font(.title2.bold())
            Text("Your memories, photos and expenses\nstay private on this iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: appLock.biometry.icon)
                    .font(.system(size: 60, weight: .light))
                    .symbolEffect(.pulse, isActive: appLock.isAuthenticating)
                Text(appLock.biometry.name).font(.headline)
            }
            .frame(width: 150, height: 150)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .accessibilityHidden(true)
            if let error = appLock.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                Task { await appLock.unlock() }
            } label: {
                Label("Unlock with \(appLock.biometry.name)", systemImage: appLock.biometry.icon)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(appLock.isAuthenticating)
            Text("If \(appLock.biometry.name) doesn't work, you can use your iPhone passcode.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.4))
        .task { await appLock.unlock() }
    }
}

/// Covers the app in the app switcher when App Lock is on, so trips and expenses can't be seen there.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial)
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
