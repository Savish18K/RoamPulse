import AVFAudio
import Speech
import SwiftUI

// MARK: - SettingsView

/// Profile → Settings: account, notifications, app lock, permissions, appearance and data.
/// Everything here reads and changes real state; nothing is a placeholder.
struct SettingsView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(ReminderService.self) private var reminders
    @Environment(AppLock.self) private var appLock
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("appTheme") private var appTheme: AppTheme = .dark
    @State private var confirmDeleteData = false
    @State private var passwordResetMessage: String?
    @State private var exportURL: URL?

    var body: some View {
        @Bindable var reminders = reminders

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                accountSection
                notificationsSection(reminders)
                privacySection
                permissionsSection
                appearanceSection
                dataSection

                group {
                    Button {
                        router.activeSheet = .about
                    } label: {
                        SettingsRow(icon: "heart.text.square", title: "About RoamPulse dev team")
                    }
                }
                .padding(.top, 14)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Settings")
        // Permissions can be changed in the iPhone's Settings app, so check again on return.
        .task(id: scenePhase) {
            if scenePhase == .active { await reminders.refreshPermission() }
        }
        .task(id: store.trips) { exportURL = try? DataExporter.writeFile(store: store, now: store.now) }
        .confirmationDialog("Delete all trips?", isPresented: $confirmDeleteData, titleVisibility: .visible) {
            Button("Delete All Trips", role: .destructive) {
                store.deleteAllData()
                router.selectedTab = .home
            }
        } message: {
            Text("This removes every trip, expense, memory and photo from this iPhone and deletes your trips from the cloud backup. Your account stays. It can't be undone.")
        }
        .alert("Check your email", isPresented: Binding(get: { passwordResetMessage != nil },
                                                        set: { if !$0 { passwordResetMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(passwordResetMessage ?? "")
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Account")
            group {
                Button {
                    router.activeSheet = .editProfile
                } label: {
                    SettingsRow(icon: "person", title: "Name") {
                        Text(store.profile.fullName).foregroundStyle(.secondary)
                    }
                }
                Divider().padding(.leading, 56)
                SettingsRow(icon: "envelope", title: "Email", showsChevron: false) {
                    Text(store.profile.email).foregroundStyle(.secondary).lineLimit(1)
                }
                Divider().padding(.leading, 56)
                Button {
                    Task { await sendPasswordReset() }
                } label: {
                    SettingsRow(icon: "key", title: "Change password", showsChevron: false)
                }
                Divider().padding(.leading, 56)
                Button {
                    router.activeSheet = .deleteAccount
                } label: {
                    SettingsRow(icon: "person.crop.circle.badge.xmark", iconColor: .red, title: "Delete account",
                                titleColor: .red)
                }
            }
        }
    }

    private func sendPasswordReset() async {
        do {
            try await session.sendPasswordReset(to: store.profile.email)
            passwordResetMessage = "We sent a link to \(store.profile.email). Open it to choose a new password."
        } catch {
            passwordResetMessage = error.localizedDescription
        }
    }

    // MARK: - Notifications

    private func notificationsSection(_ reminders: ReminderService) -> some View {
        @Bindable var reminders = reminders
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Notifications").padding(.top, 10)
            group {
                Toggle(isOn: askingPermission(for: $reminders.settings.tripReminders)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trip reminders")
                            Text("Packing the evening before, and before each activity")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bell")
                    }
                }
                .tint(.blue)
                .padding(16)
                Divider().padding(.leading, 56)
                HStack {
                    Label("Before activities", systemImage: "clock")
                    Spacer()
                    Picker("Before activities", selection: $reminders.settings.minutesBefore) {
                        ForEach(ReminderSettings.minutesBeforeChoices, id: \.self) { minutes in
                            Text(ReminderPlanner.minutesText(minutes)).tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .tint(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .disabled(!reminders.settings.tripReminders)
                Divider().padding(.leading, 56)
                DatePicker(selection: packingTime(reminders), displayedComponents: .hourAndMinute) {
                    Label("Packing reminder", systemImage: "bag")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .disabled(!reminders.settings.tripReminders)
                Divider().padding(.leading, 56)
                Toggle(isOn: askingPermission(for: $reminders.settings.weatherAlerts)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weather alerts")
                            Text("When rain or heat puts today's or tomorrow's plans at risk")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "cloud.bolt.rain")
                    }
                }
                .tint(.blue)
                .padding(16)
            }
            if reminders.permission == .denied {
                Button {
                    openSystemSettings()
                } label: {
                    Label("Notifications are turned off for RoamPulse. Tap to turn them on in Settings.",
                          systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    /// Turning a reminder on asks for notification permission the first time.
    private func askingPermission(for setting: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { setting.wrappedValue },
            set: { isOn in
                setting.wrappedValue = isOn
                if isOn {
                    Task { await reminders.requestPermissionIfNeeded() }
                }
            }
        )
    }

    /// The packing reminder time as a Date for the picker (only hour and minute matter).
    private func packingTime(_ reminders: ReminderService) -> Binding<Date> {
        Binding(
            get: { Calendar.trip.date(Calendar.trip.startOfDay(for: store.now), atMinutes: reminders.settings.packingTime) },
            set: { reminders.settings.packingTime = Calendar.trip.minutesSinceMidnight($0) }
        )
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Privacy").padding(.top, 10)
            group {
                Toggle(isOn: Binding(get: { appLock.isEnabled },
                                     set: { isOn in Task { await appLock.setEnabled(isOn) } })) {
                    Label("App lock with \(appLock.biometry.name)", systemImage: appLock.biometry.icon)
                }
                .tint(.green)
                .padding(16)
                Divider().padding(.leading, 56)
                HStack {
                    Label("Require after", systemImage: "timer")
                    Spacer()
                    Picker("Require after", selection: Binding(get: { appLock.delayMinutes },
                                                               set: { appLock.delayMinutes = $0 })) {
                        ForEach(AppLock.delayChoices, id: \.self) { minutes in
                            Text(minutes == 0 ? "Immediately" : "After \(minutes) min").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .tint(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .disabled(!appLock.isEnabled)
            }
            Text(appLock.errorMessage ?? privacyFootnote)
                .font(.footnote)
                .foregroundStyle(appLock.errorMessage == nil ? Color.secondary : Color.red)
                .padding(.horizontal, 4)
        }
    }

    private var privacyFootnote: String {
        if appLock.biometry == .none {
            return "Face ID or Touch ID isn't set up on this device, so your passcode is used. Also hides RoamPulse in the app switcher."
        }
        return "Uses \(appLock.biometry.name), with your passcode as a backup. Also hides RoamPulse in the app switcher."
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("System Permissions").padding(.top, 10)
            group {
                permissionRow("bell.badge", "Notifications", status: reminders.permission.title,
                              isAllowed: reminders.permission == .allowed)
                Divider().padding(.leading, 56)
                permissionRow("mic", "Microphone", status: SystemPermissions.microphone.title,
                              isAllowed: SystemPermissions.microphone == .allowed)
                Divider().padding(.leading, 56)
                permissionRow("waveform", "Speech recognition", status: SystemPermissions.speech.title,
                              isAllowed: SystemPermissions.speech == .allowed)
                Divider().padding(.leading, 56)
                // PhotosPicker only gives the app the photos you pick, so no permission is needed.
                permissionRow("photo", "Photos", status: "Only photos you pick", isAllowed: true)
                Divider().padding(.leading, 56)
                permissionRow(appLock.biometry.icon, appLock.biometry.name,
                              status: appLock.canBeUsed ? "Available" : "Set a passcode",
                              isAllowed: appLock.canBeUsed)
            }
        }
    }

    private func permissionRow(_ icon: String, _ title: String, status: String, isAllowed: Bool) -> some View {
        Button {
            openSystemSettings()
        } label: {
            SettingsRow(icon: icon, title: title, showsChevron: false) {
                HStack(spacing: 6) {
                    Text(status)
                    if isAllowed {
                        Image(systemName: "checkmark.circle")
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityHint("Opens RoamPulse in the iPhone's Settings")
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Appearance").padding(.top, 10)
            group {
                HStack {
                    Text("Theme")
                    Spacer()
                    SegmentedTabs(options: AppTheme.allCases.map(\.title), selection: themeIndex)
                        .frame(maxWidth: 230)
                }
                .padding(12)
                .padding(.leading, 4)
            }
        }
    }

    private var themeIndex: Binding<Int> {
        Binding(
            get: { AppTheme.allCases.firstIndex(of: appTheme) ?? 0 },
            set: { appTheme = AppTheme.allCases[$0] }
        )
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Data").padding(.top, 10)
            group {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        SettingsRow(icon: "square.and.arrow.up", title: "Export my data (JSON)")
                    }
                    Divider().padding(.leading, 56)
                }
                if store.trips.isEmpty {
                    Button {
                        store.loadSampleData()
                    } label: {
                        SettingsRow(icon: "tray.and.arrow.down", title: "Load sample trips")
                    }
                    Divider().padding(.leading, 56)
                }
                Button {
                    confirmDeleteData = true
                } label: {
                    SettingsRow(icon: "trash", iconColor: .red, title: "Delete all trips", titleColor: .red)
                }
                .disabled(store.trips.isEmpty && store.memories.isEmpty)
            }
        }
    }

    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .buttonStyle(.plain)
            .card(padding: 0)
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .previewEnvironment(.preview())
}

// MARK: - System permissions

/// The microphone and speech recognition permissions the voice journal will ask for.
enum SystemPermissions {
    enum Status: Equatable {
        case notAsked, allowed, denied

        var title: String {
            switch self {
            case .notAsked: "Asked when needed"
            case .allowed: "Allowed"
            case .denied: "Off"
            }
        }
    }

    static var microphone: Status {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .allowed
        case .denied: .denied
        default: .notAsked
        }
    }

    static var speech: Status {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .allowed
        case .denied, .restricted: .denied
        default: .notAsked
        }
    }
}

// MARK: - EditProfileView

/// Settings → Name.
struct EditProfileView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                FormField(label: "Name") {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .onSubmit(save)
                }
                Text("Shown on your profile and to friends you share trips with.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(20)
            .background(Theme.card)
            .navigationTitle("Your Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(AuthValidator.nameProblem(name) != nil || name.trimmed == store.profile.fullName)
                    }
                }
            }
            .onAppear { name = store.profile.fullName }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard AuthValidator.nameProblem(name) == nil else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await session.updateName(name.trimmed)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - DeleteAccountView

/// Settings → Delete account. Explains what is deleted and asks for the password again.
struct DeleteAccountView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    Text("This permanently deletes:").font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Your account (\(store.profile.email))", systemImage: "person.crop.circle")
                        Label("Your trips, plans and expenses in the cloud backup", systemImage: "icloud")
                        Label("Everything on this iPhone: trips, journal memories and photos", systemImage: "iphone")
                    }
                    .font(.subheadline)
                    Text("Trips other people shared with you stay for them; you are removed from them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    FormField(label: "Enter your password to confirm") {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }

                    Button(role: .destructive) {
                        delete()
                    } label: {
                        if isDeleting {
                            ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 54)
                        } else {
                            Text("Delete My Account").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                        }
                    }
                    .foregroundStyle(.white)
                    .background(Color.red, in: Capsule())
                    .disabled(password.isEmpty || isDeleting)
                    .opacity(password.isEmpty ? 0.5 : 1)
                }
                .padding(20)
            }
            .background(Theme.card)
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isDeleting)
                }
            }
            .interactiveDismissDisabled(isDeleting)
        }
    }

    private func delete() {
        isDeleting = true
        errorMessage = nil
        Task {
            defer { isDeleting = false }
            do {
                try await session.deleteAccount(password: password)
                // Signing out closes this sheet and shows the sign-in screen.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Export

/// Settings → Export my data: everything on this iPhone as a readable JSON file.
enum DataExporter {
    struct Export: Encodable {
        var app = "RoamPulse"
        var exportedAt: Date
        var account: String
        var trips: [Trip]
        var memories: [Memory]
    }

    static func json(trips: [Trip], memories: [Memory], account: String, now: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Export(exportedAt: now, account: account, trips: trips, memories: memories))
    }

    /// Writes the export to a temporary file for the share sheet.
    @MainActor
    static func writeFile(store: TripStore, now: Date) throws -> URL {
        let data = try json(trips: store.trips, memories: store.memories, account: store.profile.email, now: now)
        let url = FileManager.default.temporaryDirectory.appending(path: "RoamPulse-export-\(now.text("yyyy-MM-dd")).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
