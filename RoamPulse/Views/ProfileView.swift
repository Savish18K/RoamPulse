import SwiftUI

struct ProfileView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(AppDependencies.self) private var dependencies
    @State private var confirmSignOut = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    AvatarView(member: store.me, size: 110)
                        .padding(4)
                        .overlay(Circle().strokeBorder(Color.blue, lineWidth: 3))
                    Button {
                        router.activeSheet = .editProfile
                    } label: {
                        HStack(spacing: 6) {
                            Text(store.profile.fullName).font(.title.bold())
                            Image(systemName: "pencil").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Change your name")
                    Text(store.profile.email).foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                HStack(spacing: 0) {
                    stat("\(store.travelledTrips.count)", "Trips")
                    Divider().frame(height: 36)
                    stat("\(store.placesVisited)", "Places")
                    Divider().frame(height: 36)
                    stat("\(store.memories.count)", "Memories")
                }

                group("Statistics") {
                    if let trip = store.currentTrip {
                        NavigationLink(value: AppRoute.analytics(trip.id)) {
                            SettingsRow(icon: "chart.bar", title: "Expense analytics")
                        }
                        Divider().padding(.leading, 56)
                    }
                    NavigationLink(value: AppRoute.statistics) {
                        SettingsRow(icon: "chart.line.text.clipboard", title: "Travel footprint")
                    }
                }

                group("Settings") {
                    NavigationLink(value: AppRoute.settings) {
                        SettingsRow(icon: "gearshape", title: "Preferences & variables")
                    }
                    Divider().padding(.leading, 56)
                    NavigationLink(value: AppRoute.settings) {
                        SettingsRow(icon: "lock.shield", title: "Privacy & offline lock")
                    }
                }

                group("Account") {
                    let status = dependencies.sync.status
                    SettingsRow(icon: status.icon, iconColor: status.color, title: "Cloud backup", showsChevron: false) {
                        Text(status.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                    if let detail = status.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider().padding(.leading, 56)
                    Button {
                        confirmSignOut = true
                    } label: {
                        SettingsRow(icon: "rectangle.portrait.and.arrow.right", iconColor: .red,
                                    title: "Sign out", titleColor: .red, showsChevron: false)
                    }
                }

                group("About") {
                    Button {
                        router.activeSheet = .about
                    } label: {
                        SettingsRow(icon: "questionmark.circle", title: "RoamPulse version \(appVersion)")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Profile")
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Sign out of RoamPulse?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                session.signOut()
            }
        } message: {
            Text("Your trips stay backed up to your account. Journal memories stay on this iPhone and come back when you sign in again.")
        }
        .safeAreaInset(edge: .bottom) {
            if let trip = store.currentTrip {
                FloatingActionBar(
                    primaryTitle: "Add Expense",
                    primaryAction: { router.activeSheet = .addExpense(tripID: trip.id) },
                    secondaryTitle: "Record Memory",
                    secondaryAction: { router.activeSheet = .newMemory(tripID: trip.id, start: .recording) }
                )
            }
        }
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold())
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            VStack(spacing: 0, content: content)
                .buttonStyle(.plain)
                .card(padding: 0)
        }
    }
}

/// Icon + title + optional trailing content + chevron. Used on Profile and Settings.
struct SettingsRow<Trailing: View>: View {
    let icon: String
    var iconColor: Color = .primary
    let title: String
    var titleColor: Color = .primary
    var showsChevron = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 26)
            Text(title).foregroundStyle(titleColor)
            Spacer()
            trailing
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(icon: String, iconColor: Color = .primary, title: String, titleColor: Color = .primary, showsChevron: Bool = true) {
        self.init(icon: icon, iconColor: iconColor, title: title, titleColor: titleColor, showsChevron: showsChevron) {
            EmptyView()
        }
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .previewEnvironment(.preview())
}

/// "About RoamPulse dev team" sheet.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 96)
                        .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(.top, 24)
                    VStack(spacing: 4) {
                        Text("RoamPulse").font(.title.bold())
                        Text("Plan the trip, share the costs, keep the memories.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        aboutRow("person", "Designed and developed by Savishka Kuruppu")
                        aboutRow("graduationcap", "NIBM • BSc (Hons) Computing • iOS Application Development")
                        aboutRow("icloud", "Trips are backed up to your account with Firebase and work offline.")
                        aboutRow("lock.shield", "Voice memories, transcripts and photos never leave this iPhone.")
                        aboutRow("cpu", "Speech, Natural Language, Vision and Core ML run on the device.")
                    }
                    .card()
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func aboutRow(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundStyle(.blue)
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .previewEnvironment(.preview())
}
