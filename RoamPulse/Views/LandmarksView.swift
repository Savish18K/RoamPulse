import SwiftUI

// MARK: - LandmarksGridView

/// Grid of the 10 landmarks the model knows, showing which ones were found.
struct LandmarksGridView: View {
    @Environment(TripStore.self) private var store
    @State private var filter: LandmarkCategory?

    private var filtered: [Landmark] {
        store.landmarks.filter { filter == nil || $0.category == filter }
    }

    private var summary: String {
        let found = store.landmarks.filter(\.isFound)
        let trips = Set(found.compactMap(\.tripName)).count
        return "\(found.count) of \(store.landmarks.count) landmarks recognised across \(trips) trips"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { filter = nil } label: { Chip("All", isSelected: filter == nil) }
                    ForEach(LandmarkCategory.allCases) { category in
                        Button { filter = category } label: {
                            Chip(category.rawValue, isSelected: filter == category)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Text(summary)
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                ForEach(filtered) { landmark in
                    NavigationLink(value: AppRoute.landmark(landmark.id)) {
                        LandmarkCard(landmark: landmark)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct LandmarkCard: View {
    let landmark: Landmark

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            image
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topLeading) { badge.padding(10) }

            VStack(alignment: .leading, spacing: 4) {
                Text(landmark.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                details
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
    }

    @ViewBuilder
    private var image: some View {
        switch landmark.status {
        case .recognised, .confirmedByUser:
            PhotoView(photo: landmark.photo)
        case .voiceOnly:
            Theme.raised.overlay { Image(systemName: "mic").font(.largeTitle).foregroundStyle(.secondary) }
        case .planned:
            PhotoView(photo: landmark.photo).saturation(0.2).opacity(0.5)
        case .notVisited:
            Theme.raised.overlay { Image(systemName: "binoculars").font(.title).foregroundStyle(.tertiary) }
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch landmark.status {
        case .recognised(let confidence):
            GlassPill("● \(confidence.percentText)").font(.caption)
        case .confirmedByUser:
            GlassPill("● Confirmed by you").font(.caption)
        default:
            EmptyView()
        }
    }

    private var subtitle: String {
        switch landmark.status {
        case .planned(let trip): "Planned: \(trip)"
        case .notVisited: "Not in a trip yet"
        default: landmark.tripName ?? ""
        }
    }

    @ViewBuilder
    private var details: some View {
        switch landmark.status {
        case .voiceOnly:
            Label("\(landmark.voiceCount) voice memory", systemImage: "mic.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Add a photo").font(.subheadline.bold())
        case .recognised, .confirmedByUser:
            Label(countText, systemImage: "building.columns.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var countText: String {
        var parts = ["\(landmark.photoCount) photo\(landmark.photoCount == 1 ? "" : "s")"]
        if landmark.voiceCount > 0 { parts.append("\(landmark.voiceCount) voice") }
        return parts.joined(separator: " • ")
    }
}

// MARK: - LandmarkDetailView

struct LandmarkDetailView: View {
    let landmarkID: UUID

    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var filter = 0

    var body: some View {
        if let landmark = store.landmarks.first(where: { $0.id == landmarkID }) {
            content(landmark)
        } else {
            ContentUnavailableView("Landmark not found", systemImage: "building.columns")
        }
    }

    private func content(_ landmark: Landmark) -> some View {
        let memories = store.sortedMemories.filter { $0.landmark == landmark.name }
        let people = uniquePeople(in: memories)
        let activity = store.trips.flatMap(\.activities).first { $0.title.localizedCaseInsensitiveContains(landmark.name) }
        let visitedDay = memories.first?.day

        return GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HeroHeader(photo: landmark.photo,
                               pill: visitedDay.map { "Visited • Day \($0)" } ?? "Not visited yet",
                               height: 300,
                               topInset: proxy.safeAreaInsets.top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(landmark.name).font(.largeTitle.bold())
                            Text(subtitle(landmark)).foregroundStyle(.white.opacity(0.75))
                            if !people.isEmpty {
                                HStack(spacing: 10) {
                                    AvatarStack(members: people)
                                    Text("Visited with " + people.map(\.name).joined(separator: " and "))
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        StatTile(icon: "photo", tint: .cyan, title: "Photos", value: "\(landmark.photoCount) photos")
                        StatTile(icon: "mic", tint: .purple, title: "Voice memories",
                                 value: "\(landmark.voiceCount) recording\(landmark.voiceCount == 1 ? "" : "s")")
                        StatTile(icon: "calendar", tint: .blue, title: "Itinerary",
                                 value: activity.map { "Day \($0.day) • \($0.timeText)" } ?? "Not planned")
                        StatTile(icon: "sparkle", tint: .green, title: "Top match",
                                 value: landmark.confidence.map { "\($0.percentText) confidence" } ?? "—")
                    }
                    .padding(.horizontal)

                    SegmentedTabs(options: ["All", "Photos", "Voice"], selection: $filter)
                        .padding(.horizontal)

                    HStack {
                        Text("Memories here").font(.title2.bold())
                        Spacer()
                        if visitedDay != nil {
                            Text("Visited")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .overlay(Capsule().strokeBorder(.green))
                        }
                    }
                    .padding(.horizontal)

                    let shown = filtered(memories)
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(shown) { memory in
                            Button {
                                router.activeSheet = .memory(memory.id)
                            } label: {
                                memoryRow(memory)
                            }
                            .buttonStyle(.plain)
                        }
                        if shown.isEmpty {
                            Text("No memories here yet. Add a photo to start.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom) {
                BackActionBar(actionTitle: "+ Add Photo") {
                    router.activeSheet = .addPhoto(memoryID: nil)
                }
            }
        }
        .background(Theme.background)
        .navigationTitle(landmark.name)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private func subtitle(_ landmark: Landmark) -> String {
        switch landmark.status {
        case .recognised(let confidence): "\(landmark.location) • Recognised on device (\(confidence.percentText))"
        case .confirmedByUser: "\(landmark.location) • Confirmed by you"
        case .voiceOnly: "\(landmark.location) • Mentioned in a voice memory"
        case .planned(let trip): "\(landmark.location) • Planned for \(trip)"
        case .notVisited: "\(landmark.location) • Not visited yet"
        }
    }

    private func filtered(_ memories: [Memory]) -> [Memory] {
        switch filter {
        case 1: memories.filter { !$0.photos.isEmpty }
        case 2: memories.filter(\.hasVoice)
        default: memories
        }
    }

    private func uniquePeople(in memories: [Memory]) -> [Member] {
        var seen = Set<UUID>()
        return memories.flatMap(\.people).filter { seen.insert($0.id).inserted }
    }

    private func memoryRow(_ memory: Memory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(memory.date.text("HH:mm")) • \(memory.kindText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(memory.title).font(.headline)
            }
            Spacer()
            Group {
                if let photo = memory.photos.first {
                    PhotoView(photo: photo)
                } else {
                    Theme.card.overlay { Image(systemName: "mic").foregroundStyle(.purple) }
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { LandmarkDetailView(landmarkID: SampleData.landmarks[0].id) }
        .environment(TripStore())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
