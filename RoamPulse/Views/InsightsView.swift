import SwiftUI
import Charts

// MARK: - InsightsView

/// Search, Timeline, Mood and Landmarks views over the journal.
struct InsightsView: View {
    @State private var tab = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SegmentedTabs(options: ["Search", "Timeline", "Mood", "Landmarks"], selection: $tab)

                switch tab {
                case 0: MemorySearchView()
                case 1: MemoryTimelineView()
                case 2: MoodView()
                default: LandmarksGridView()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Insights")
    }
}

#Preview {
    NavigationStack { InsightsView() }
        .environment(TripStore())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

// MARK: - MemorySearchView

/// Search memories by what was said, a place or a person.
struct MemorySearchView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var query = "tea"

    private let suggestions = ["tea", "Kandy", "train", "Suresha"]

    private var results: [Memory] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        return store.sortedMemories.filter { memory in
            let haystack = [memory.title, memory.transcript, memory.place, memory.peopleText]
                + memory.placeTags
            return haystack.contains { $0.localizedCaseInsensitiveContains(text) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search what was said, places, people…", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { query = suggestion } label: {
                            Chip(suggestion, icon: suggestion == "tea" ? "cup.and.saucer" : nil,
                                 isSelected: query.caseInsensitiveCompare(suggestion) == .orderedSame)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if query.isEmpty {
                Text("Search your memories by what was said, a place or a person.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(results.count) result\(results.count == 1 ? "" : "s") found for “\(query)”")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            ForEach(results) { memory in
                Button {
                    router.activeSheet = .memory(memory.id)
                } label: {
                    resultCard(memory)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func resultCard(_ memory: Memory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(memory.id == store.latestMemory?.id ? "Latest Memory" : "\(memory.place) • Day \(memory.day)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
                Spacer()
                Text("\(memory.date.text("EEE HH:mm")) • Near \(memory.place)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(memory.title).font(.title3.weight(.semibold))
            let snippetText = snippet(for: memory)
            if !snippetText.isEmpty {
                Text(highlighted(snippetText))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .card(padding: 18, cornerRadius: 24)
    }

    /// The sentence of the transcript that contains the search text.
    private func snippet(for memory: Memory) -> String {
        let sentences = memory.transcript.components(separatedBy: ". ")
        guard let index = sentences.firstIndex(where: { $0.localizedCaseInsensitiveContains(query) }) else {
            return String(memory.transcript.prefix(120))
        }
        let sentence = sentences[index]
        return (index > 0 ? "… " : "") + sentence + (sentence.hasSuffix(".") ? "" : ".")
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        var searchStart = attributed.startIndex
        while let range = attributed[searchStart...].range(of: query, options: .caseInsensitive) {
            attributed[range].foregroundColor = Color.purple
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
            searchStart = range.upperBound
        }
        return attributed
    }
}

// MARK: - MemoryTimelineView

/// All memories by day, newest first.
struct MemoryTimelineView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router

    private var days: [Date] {
        Set(store.memories.map { DemoClock.calendar.startOfDay(for: $0.date) }).sorted(by: >)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(days, id: \.self) { day in
                let memories = store.sortedMemories.filter { DemoClock.calendar.isDate($0.date, inSameDayAs: day) }
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("\(day.text("EEEE d MMM")) • Day \(memories.first?.day ?? 1)")
                        .padding(.bottom, 10)
                    ForEach(memories) { memory in
                        Button {
                            router.activeSheet = .memory(memory.id)
                        } label: {
                            row(memory, isLast: memory.id == memories.last?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if store.memories.isEmpty {
                ContentUnavailableView("Nothing on the timeline yet", systemImage: "clock")
            }
        }
    }

    private func row(_ memory: Memory, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: icon(for: memory))
                    .font(.footnote)
                    .foregroundStyle(memory.hasVoice ? .purple : .cyan)
                    .frame(width: 32, height: 32)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke))
                if !isLast {
                    Rectangle().fill(Theme.stroke).frame(width: 2).frame(maxHeight: .infinity)
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(memory.date.text("HH:mm")) • \(memory.kindText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(memory.title).font(.headline)
                    HStack(spacing: 6) {
                        Text(memory.place).foregroundStyle(.secondary)
                        if let mood = memory.mood { MoodBadge(mood: mood) }
                    }
                    .font(.subheadline)
                }
                Spacer()
                if let photo = memory.photos.first {
                    PhotoView(photo: photo)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.bottom, 18)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }

    private func icon(for memory: Memory) -> String {
        switch (memory.photos.isEmpty, memory.hasVoice) {
        case (false, true): "photo.on.rectangle"
        case (false, false): "photo"
        default: "mic.fill"
        }
    }
}

// MARK: - MoodView

/// How each day felt, based on the sentiment of that day's memories.
struct MoodView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router

    private struct DayMood: Identifiable {
        let date: Date
        let score: Double
        var id: Date { date }
        var color: Color { score > 0.2 ? .green : (score < -0.2 ? .red : .gray) }
    }

    private var dayMoods: [DayMood] {
        let scored = store.memories.filter { $0.sentiment != nil }
        let groups = Dictionary(grouping: scored) { DemoClock.calendar.startOfDay(for: $0.date) }
        return groups.map { date, memories in
            let total = memories.compactMap(\.sentiment).reduce(0, +)
            return DayMood(date: date, score: total / Double(memories.count))
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("How each day felt").font(.headline)
                Chart(dayMoods) { day in
                    BarMark(
                        x: .value("Day", day.date.text("EEE d")),
                        y: .value("Mood", day.score),
                        width: .fixed(44)
                    )
                    .foregroundStyle(day.color)
                    .cornerRadius(6)
                    RuleMark(y: .value("Neutral", 0))
                        .foregroundStyle(Color.secondary)
                }
                .chartYScale(domain: -1...1)
                .frame(height: 180)
                .accessibilityLabel("Average mood per day")
            }
            .card(padding: 18)

            HStack(spacing: 10) {
                ForEach(Mood.allCases) { mood in
                    let count = store.memories.filter { $0.mood == mood }.count
                    VStack(spacing: 4) {
                        Image(systemName: mood.icon).font(.title2).symbolRenderingMode(.multicolor)
                        Text("\(count)").font(.title3.bold())
                        Text(mood.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .card(padding: 12, cornerRadius: 16)
                }
            }

            SectionLabel("Memories by mood")
            VStack(spacing: 0) {
                let moodMemories = store.sortedMemories.filter { $0.mood != nil }
                ForEach(moodMemories) { memory in
                    Button {
                        router.activeSheet = .memory(memory.id)
                    } label: {
                        HStack {
                            Image(systemName: memory.mood?.icon ?? "circle")
                                .symbolRenderingMode(.multicolor)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(memory.title).font(.subheadline.bold())
                                Text("\(memory.date.text("EEE HH:mm")) • \(memory.place)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let mood = memory.mood { MoodBadge(mood: mood) }
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if memory.id != moodMemories.last?.id { Divider() }
                }
            }
            .card(padding: 0)
        }
    }
}
