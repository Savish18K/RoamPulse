import SwiftUI

// MARK: - ProfileView

struct ProfileView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router

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
                    Text(store.profile.fullName).font(.title.bold())
                    Text("\(store.profile.email) • Local User").foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                HStack(spacing: 0) {
                    stat("\(store.trips.filter { $0.status() != .upcoming }.count)", "Trips")
                    Divider().frame(height: 36)
                    stat("\(SampleData.placesVisited)", "Places")
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
        .safeAreaInset(edge: .bottom) {
            if let trip = store.currentTrip {
                FloatingActionBar(
                    primaryTitle: "Add Expense",
                    primaryAction: { router.activeSheet = .addExpense(tripID: trip.id) },
                    secondaryTitle: "Record Memory",
                    secondaryAction: { router.activeSheet = .recordMemory }
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
        .environment(TripStore())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

// MARK: - StatisticsView

struct StatisticsView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var range = 0

    /// Rough LKR → USD rate for the "equivalent" line.
    private let usdRate = 300.3

    private var trips: [Trip] {
        let travelled = store.trips.filter { $0.status() != .upcoming }
        guard range == 0 else { return travelled }
        return travelled.filter { DemoClock.calendar.component(.year, from: $0.startDate) == 2026 }
    }

    private var daysTravelled: Int {
        trips.reduce(0) { total, trip in
            total + (trip.status() == .active ? (trip.dayNumber() ?? 0) : trip.dayCount)
        }
    }

    private var totalSpent: Double { trips.reduce(0) { $0 + $1.totalSpent } }
    private var totalBudget: Double { trips.reduce(0) { $0 + $1.budget } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SegmentedTabs(options: ["2026", "All time"], selection: $range)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    tile("Trips", "\(trips.count)")
                    tile("Days", "\(daysTravelled)")
                    tile("Places", "\(SampleData.placesVisited)")
                    tile("Memories", "\(store.memories.count)")
                }

                landmarksCard
                spendingCard

                VStack(alignment: .leading, spacing: 4) {
                    Text("Explore travel memories").foregroundStyle(.secondary)
                    Button("Read the year back in Insights") { router.selectedTab = .insights }
                        .font(.headline)
                }
                .card()
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Statistics")
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.largeTitle.bold())
        }
        .card(padding: 18)
    }

    private var landmarksCard: some View {
        let found = store.landmarks.filter(\.isFound)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Landmarks recognised").foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "building.columns").foregroundStyle(.purple)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(found.count)").font(.largeTitle.bold())
                Text("of \(store.landmarks.count) Sri Lankan landmarks").foregroundStyle(.secondary)
            }
            ProgressView(value: Double(found.count), total: Double(max(store.landmarks.count, 1)))
                .tint(.purple)
            HStack(spacing: 8) {
                ForEach(found) { landmark in
                    PhotoView(photo: landmark.photo)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Text("\(store.landmarks.count - found.count) more to find")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 56)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .card(padding: 18)
    }

    private var spendingCard: some View {
        let largest = trips.map(\.totalSpent).max() ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Total Spending").foregroundStyle(.secondary)
                Spacer()
                Text(totalSpent <= totalBudget ? "On Budget" : "Over Budget")
                    .font(.subheadline)
                    .foregroundStyle(totalSpent <= totalBudget ? .green : .orange)
            }
            Text(totalSpent.lkr)
                .font(.system(size: 40, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("~ USD \((totalSpent / usdRate).grouped) equivalent")
                .foregroundStyle(.secondary)

            Text("By Trip").foregroundStyle(.secondary).padding(.top, 6)
            ForEach(trips) { trip in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(trip.name)
                        Spacer()
                        Text(trip.totalSpent.lkr).font(.subheadline.bold()).foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            ForEach(ExpenseCategory.allCases) { category in
                                Rectangle()
                                    .fill(category.color)
                                    .frame(width: proxy.size.width * trip.spent(on: category) / max(largest, 1))
                            }
                        }
                    }
                    .frame(height: 8)
                    .background(Theme.fill)
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 12) {
                ForEach(ExpenseCategory.allCases) { category in
                    HStack(spacing: 4) {
                        Circle().fill(category.color).frame(width: 8, height: 8)
                        Text(category.rawValue)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .card(padding: 18)
    }
}

#Preview {
    NavigationStack { StatisticsView() }
        .environment(TripStore())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    @AppStorage("smartAdvisories") private var smartAdvisories = true
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("lockDelayMinutes") private var lockDelayMinutes = 0
    @AppStorage("appTheme") private var appTheme: AppTheme = .dark
    @AppStorage("hasOnboarded") private var hasOnboarded = true
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Notifications")
                group {
                    Toggle(isOn: $smartAdvisories) {
                        Label("Enable smart advisories", systemImage: "bell")
                    }
                    .tint(.blue)
                    .padding(16)
                }

                SectionLabel("Privacy").padding(.top, 10)
                group {
                    Toggle(isOn: $appLockEnabled) {
                        Label("App lock with Face ID", systemImage: "faceid")
                    }
                    .tint(.green)
                    .padding(16)
                    Divider().padding(.leading, 56)
                    HStack {
                        Label("Require after", systemImage: "timer")
                        Spacer()
                        Picker("Require after", selection: $lockDelayMinutes) {
                            Text("Immediately").tag(0)
                            Text("After 1 minute").tag(1)
                            Text("After 5 minutes").tag(5)
                            Text("After 15 minutes").tag(15)
                        }
                        .labelsHidden()
                        .tint(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .disabled(!appLockEnabled)
                }
                Text("Uses Face ID or Touch ID, with your passcode as a backup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                SectionLabel("System Permissions").padding(.top, 10)
                group {
                    permissionRow("mic", "Microphone", status: "Allowed")
                    Divider().padding(.leading, 56)
                    permissionRow("waveform", "Speech recognition", status: "Allowed")
                    Divider().padding(.leading, 56)
                    permissionRow("photo", "Photos", status: "Selected only")
                    Divider().padding(.leading, 56)
                    permissionRow("bell.badge", "Notifications", status: "Allowed")
                }

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

                SectionLabel("Data").padding(.top, 10)
                group {
                    Button {
                        confirmDelete = true
                    } label: {
                        SettingsRow(icon: "trash", iconColor: .red, title: "Delete all data", titleColor: .red)
                    }
                    Divider().padding(.leading, 56)
                    ShareLink(item: exportSummary) {
                        SettingsRow(icon: "square.and.arrow.up", title: "Export local database")
                    }
                }

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
        .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete All Data", role: .destructive) {
                store.resetAll()
                appLockEnabled = false
                router.selectedTab = .home
                hasOnboarded = false
            }
        } message: {
            Text("This removes every trip, expense, memory and photo from this iPhone. It can't be undone.")
        }
    }

    private var themeIndex: Binding<Int> {
        Binding(
            get: { AppTheme.allCases.firstIndex(of: appTheme) ?? 0 },
            set: { appTheme = AppTheme.allCases[$0] }
        )
    }

    private var exportSummary: String {
        "RoamPulse export\nTrips: \(store.trips.count)\nMemories: \(store.memories.count)\nExpenses: \(store.trips.flatMap(\.expenses).count)"
    }

    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .buttonStyle(.plain)
            .card(padding: 0)
    }

    private func permissionRow(_ icon: String, _ title: String, status: String) -> some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            SettingsRow(icon: icon, title: title, showsChevron: false) {
                HStack(spacing: 6) {
                    Text(status)
                    if status == "Allowed" {
                        Image(systemName: "checkmark.circle")
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }
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
                        aboutRow("lock.shield", "No account. All trips, memories and photos stay on this iPhone.")
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
        .environment(TripStore())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
