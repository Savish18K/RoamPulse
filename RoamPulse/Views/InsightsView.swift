import Charts
import SwiftUI

struct InsightsView: View {
    @State private var viewModel: InsightsViewModel
    @State private var tab = 0
    @Environment(AppRouter.self) private var router

    init(viewModel: InsightsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SegmentedTabs(options: ["Search", "Timeline", "Mood", "Landmarks"], selection: $tab)

                if viewModel.tripsWithMemories.count > 1 && tab != 3 {
                    tripFilter
                }

                if !viewModel.hasMemories && tab != 3 {
                    ContentUnavailableView {
                        Label("Nothing to look back on yet", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("Write memories in the Journal and they'll show up here: searchable, by day and by mood.")
                    } actions: {
                        Button("Open Journal") { router.selectedTab = .journal }
                    }
                    .padding(.top, 30)
                } else {
                    switch tab {
                    case 0: MemorySearchView(viewModel: viewModel)
                    case 1: MemoryTimelineView(viewModel: viewModel)
                    case 2: MoodView(viewModel: viewModel)
                    default: LandmarksGridView()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Insights")
        // Tapping a place or person on a memory searches for it
        .onChange(of: router.insightsSearch, initial: true) { _, text in
            guard let text else { return }
            tab = 0
            viewModel.tripFilter = nil
            viewModel.query = text
            router.insightsSearch = nil
        }
    }

    private var tripFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { viewModel.tripFilter = nil } label: {
                    Chip("All trips", isSelected: viewModel.tripFilter == nil)
                }
                ForEach(viewModel.tripsWithMemories) { trip in
                    Button { viewModel.tripFilter = trip.id } label: {
                        Chip(trip.name, isSelected: viewModel.tripFilter == trip.id)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack { InsightsView(viewModel: InsightsViewModel(store: dependencies.store)) }
        .previewEnvironment(dependencies)
}

struct MemorySearchView: View {
    @Bindable var viewModel: InsightsViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search what happened, places, people…", text: $viewModel.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).tapTarget()
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !viewModel.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.suggestions, id: \.self) { suggestion in
                            Button { viewModel.query = suggestion } label: {
                                Chip(suggestion, isSelected: viewModel.query.caseInsensitiveCompare(suggestion) == .orderedSame)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if viewModel.query.trimmed.isEmpty {
                Text("Search your memories by what happened, a place or a person, or tap a suggestion.")
                    .foregroundStyle(.secondary)
            } else if viewModel.results.isEmpty {
                ContentUnavailableView.search(text: viewModel.query)
            } else {
                Text("\(viewModel.results.count) result\(viewModel.results.count == 1 ? "" : "s") for “\(viewModel.query)”")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            ForEach(viewModel.results) { memory in
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
                Text(viewModel.isLatest(memory) ? "Latest Memory" : viewModel.tripName(for: memory))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
                    .lineLimit(1)
                Spacer()
                Text("\(memory.date.text("EEE HH:mm")) • \(memory.place)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(highlighted(memory.title)).font(.title3.weight(.semibold))
            if memory.hasText {
                Text(highlighted(viewModel.snippet(for: memory)))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if !memory.people.isEmpty {
                Text(highlighted("With \(memory.peopleText)")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .card(padding: 18, cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }

    // Bold purple highlight on matches
    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let query = viewModel.query.trimmed
        guard !query.isEmpty else { return attributed }
        var searchStart = attributed.startIndex
        while let range = attributed[searchStart...].range(of: query, options: .caseInsensitive) {
            attributed[range].foregroundColor = Color.purple
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
            searchStart = range.upperBound
        }
        return attributed
    }
}

struct MemoryTimelineView: View {
    let viewModel: InsightsViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(viewModel.timeline) { day in
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(day.title)
                        .padding(.bottom, 10)
                    ForEach(day.memories) { memory in
                        Button {
                            router.activeSheet = .memory(memory.id)
                        } label: {
                            row(memory, isLast: memory.id == day.memories.last?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
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
            .accessibilityHidden(true)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(memory.date.text("HH:mm")) • \(memory.kindText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(memory.title).font(.headline).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(memory.place).foregroundStyle(.secondary)
                        if let mood = memory.mood { MoodBadge(mood: mood) }
                    }
                    .font(.subheadline)
                }
                Spacer()
                if let photo = memory.photos.first {
                    MemoryPhotoView(photo: photo, thumbnail: true)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.bottom, 18)
            .accessibilityElement(children: .combine)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }

    private func icon(for memory: Memory) -> String {
        switch (memory.photos.isEmpty, memory.hasVoice) {
        case (false, true): "photo.on.rectangle"
        case (false, false): "photo"
        case (true, true): "mic.fill"
        case (true, false): "text.alignleft"
        }
    }
}

struct MoodView: View {
    let viewModel: InsightsViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.dayMoods.isEmpty {
                ContentUnavailableView {
                    Label("No moods yet", systemImage: "face.smiling")
                } description: {
                    Text("Pick how it felt when you write a memory, and each day's mood appears here.")
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How each day felt").font(.headline)
                    Chart(viewModel.dayMoods) { day in
                        BarMark(
                            x: .value("Day", day.date.text("EEE d")),
                            y: .value("Mood", day.score),
                            width: .fixed(36)
                        )
                        .foregroundStyle(day.mood.color)
                        .cornerRadius(6)
                        .accessibilityLabel(day.date.text("EEEE d MMMM"))
                        .accessibilityValue("\(day.mood.rawValue), \(day.count) memor\(day.count == 1 ? "y" : "ies")")
                        RuleMark(y: .value("Neutral", 0))
                            .foregroundStyle(Color.secondary)
                    }
                    .chartYScale(domain: -1...1)
                    .chartYAxis {
                        AxisMarks(values: [-1, 0, 1]) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                switch value.as(Double.self) ?? 0 {
                                case 1: Text("Positive")
                                case -1: Text("Negative")
                                default: Text("Mixed")
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                }
                .card(padding: 18)

                HStack(spacing: 10) {
                    ForEach(Mood.allCases) { mood in
                        VStack(spacing: 4) {
                            Image(systemName: mood.icon).font(.title2).symbolRenderingMode(.multicolor)
                            Text("\(viewModel.count(of: mood))").font(.title3.bold())
                            Text(mood.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .card(padding: 12, cornerRadius: 16)
                        .accessibilityElement(children: .combine)
                    }
                }

                SectionLabel("Memories by mood")
                VStack(spacing: 0) {
                    let moodMemories = viewModel.memoriesWithMood
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
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(.plain)
                        if memory.id != moodMemories.last?.id { Divider() }
                    }
                }
                .card(padding: 0)
            }
        }
    }
}
