import PhotosUI
import SwiftUI

struct JournalView: View {
    @State private var viewModel: JournalViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: JournalViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if viewModel.tripsWithMemories.count > 1 {
                    tripFilter
                }

                let memories = viewModel.memories
                ForEach(Array(memories.enumerated()), id: \.element.id) { index, memory in
                    Button {
                        router.activeSheet = .memory(memory.id)
                    } label: {
                        MemoryCard(memory: memory, tripName: viewModel.tripFilter == nil ? viewModel.tripName(for: memory) : nil,
                                   isFeatured: index == 0)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            router.activeSheet = .editMemory(memory.id)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            viewModel.memoryPendingDelete = memory
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                if viewModel.hasNoMemories {
                    emptyState
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .motionAnimation(.snappy, value: viewModel.memories)
        }
        .background(Theme.background)
        .navigationTitle("Journal")
        .safeAreaInset(edge: .bottom) {
            if viewModel.canWriteMemory {
                FloatingActionBar(
                    primaryTitle: "Record Memory",
                    primaryAction: { router.activeSheet = .newMemory(tripID: viewModel.tripForNewMemory, start: .recording) },
                    secondaryTitle: "Write",
                    secondaryAction: { router.activeSheet = .newMemory(tripID: viewModel.tripForNewMemory, start: .writing) }
                )
            }
        }
        .confirmationDialog(
            "Delete this memory?",
            isPresented: Binding(get: { viewModel.memoryPendingDelete != nil },
                                 set: { if !$0 { viewModel.memoryPendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: viewModel.memoryPendingDelete
        ) { memory in
            Button("Delete “\(memory.title)”", role: .destructive) {
                withMotion { viewModel.confirmDelete() }
            }
        } message: { _ in
            Text("Its text and photos will be removed from this \(Device.name). It can't be undone.")
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

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.canWriteMemory {
            ContentUnavailableView {
                Label("No memories yet", systemImage: "book.closed")
            } description: {
                Text("Write down what happened, add photos and tag who was there. They stay on this \(Device.name).")
            } actions: {
                Button("Write a Memory") {
                    router.activeSheet = .newMemory(tripID: viewModel.tripForNewMemory, start: .writing)
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false, height: 44))
            }
            .padding(.top, 40)
        } else {
            ContentUnavailableView {
                Label("No trips yet", systemImage: "suitcase")
            } description: {
                Text("Memories belong to a trip. Create one first.")
            } actions: {
                Button("Create Trip") { router.activeSheet = .createTrip }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false, height: 44))
            }
            .padding(.top, 40)
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack { JournalView(viewModel: JournalViewModel(store: dependencies.store)) }
        .previewEnvironment(dependencies)
}

struct MemoryCard: View {
    let memory: Memory
    // Only shown when several trips are listed
    var tripName: String?
    var isFeatured = false
    @Environment(AppRouter.self) private var router
    @Environment(VoiceJournalService.self) private var voice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(memory.title).font(.title3.bold()).lineLimit(2).multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: kindIcon)
                    .font(.title3)
                    .foregroundStyle(isFeatured ? .white : .secondary)
                    .frame(width: 40, height: 40)
                    .background(isFeatured ? Theme.purple : Theme.fill, in: Circle())
                    .accessibilityLabel(memory.kindText)
            }

            if memory.transcriptUnavailable {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This language can't be written down on this device yet. Recording saved.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Type it myself") { router.activeSheet = .typeNote(memory.id) }
                        .font(.subheadline.bold())
                        .tapTarget()
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if memory.hasText {
                Text(memory.transcript)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            } else if voice.isTranscribing(memory.id) {
                Label("Writing it down on your \(Device.name)…", systemImage: "waveform")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !memory.photos.isEmpty {
                photoStrip
            }

            let tags = chips
            if !tags.isEmpty || memory.landmark != nil {
                FlowLayout {
                    if let landmark = memory.landmark {
                        Chip(landmark, icon: "building.columns.fill", tint: .purple)
                    }
                    ForEach(tags, id: \.self) { Chip($0) }
                }
            }

            AdaptiveStack(spacing: 8) {
                if !memory.people.isEmpty {
                    AvatarStack(members: memory.people, size: 24)
                }
                Text(footerText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if let mood = memory.mood {
                    MoodBadge(mood: mood)
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.card)
                .overlay {
                    if isFeatured {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.purple.opacity(0.3), Color.teal.opacity(0.15)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.stroke))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the memory")
    }

    private var subtitle: String {
        var parts = ["\(memory.date.text("EEE HH:mm"))", memory.place]
        if let tripName, !tripName.isEmpty { parts.append(tripName) }
        return parts.joined(separator: " • ")
    }

    private var kindIcon: String {
        if memory.hasVoice { return "waveform" }
        return memory.photos.isEmpty ? "text.alignleft" : "photo"
    }

    private var photoStrip: some View {
        HStack(spacing: 10) {
            MemoryPhotoView(photo: memory.photos[0])
                .overlay(alignment: .bottomLeading) {
                    if let landmark = memory.landmark {
                        GlassPill(landmark, icon: "building.columns.fill")
                            .font(.caption)
                            .padding(10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if memory.photos.count > 1 {
                MemoryPhotoView(photo: memory.photos[1], thumbnail: true)
                    .frame(width: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if memory.photos.count > 2 {
                            GlassPill("+\(memory.photos.count - 2)").font(.caption).padding(8)
                        }
                    }
            }
        }
        .frame(height: 160)
    }

    private var chips: [String] {
        var tags = memory.placeTags
        if !memory.sceneTags.isEmpty {
            tags.append("Scene: " + memory.sceneTags.prefix(2).joined(separator: ", ").lowercased())
        }
        return tags
    }

    private var footerText: String {
        var parts: [String] = []
        if memory.hasVoice { parts.append(memory.duration.durationText) }
        if !memory.people.isEmpty { parts.append(memory.peopleText) }
        if parts.isEmpty { parts.append(memory.kindText) }
        return parts.joined(separator: " • ")
    }
}

// Tapping a place or person opens it in Insights
struct MemoryDetailView: View {
    let memoryID: UUID

    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(VoiceJournalService.self) private var voice
    @Environment(\.dismiss) private var dismiss
    @State private var playback = AudioPlayback()
    @State private var photoIndex = 0
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let memory = store.memory(memoryID) {
                content(memory)
            } else {
                ContentUnavailableView("Memory not found", systemImage: "book.closed")
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    private func content(_ memory: Memory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(memory.title).font(.title.bold())
                        Text("\(memory.date.text("EEEE HH:mm")) • \(memory.place) • Day \(memory.day)")
                            .foregroundStyle(.secondary)
                        if let trip = store.trip(memory.tripID) {
                            Text(trip.name).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Menu {
                        Button {
                            router.activeSheet = .editMemory(memory.id)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(Theme.fill, in: Circle())
                    }
                    .accessibilityLabel("Memory options")
                }
                .padding(.top, 12)

                if !memory.photos.isEmpty {
                    photos(memory)
                }

                if let mood = memory.mood {
                    HStack(spacing: 14) {
                        Image(systemName: mood.icon)
                            .font(.largeTitle)
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reads \(mood.rawValue)" + (memory.sentiment.map { String(format: " (%.2f)", $0) } ?? ""))
                                .font(.headline)
                            Text(mood.summary).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .card(fill: Theme.raised)
                    .accessibilityElement(children: .combine)
                }

                if memory.hasVoice {
                    VStack(spacing: 6) {
                        ProgressView(value: playback.progress).tint(.purple)
                        HStack {
                            Text(Int(playback.currentTime).timerText)
                            Spacer()
                            Text(memory.duration.timerText)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if store.recordingURL(for: memory) == nil {
                            Text("Sample memory: there's no recording to play.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let error = playback.errorMessage {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Recording, \(memory.duration) seconds")
                }

                FlowLayout {
                    if let landmark = memory.landmark {
                        chipButton(landmark, icon: "building.columns.fill", tint: .purple, search: landmark)
                    }
                    chipButton(memory.place, icon: "mappin.and.ellipse", search: memory.place)
                    ForEach(memory.placeTags.filter { $0 != memory.place }, id: \.self) { tag in
                        chipButton(tag, icon: nil, search: tag)
                    }
                    ForEach(memory.people) { person in
                        Button {
                            searchInsights(for: person.name)
                        } label: {
                            HStack(spacing: 6) {
                                AvatarView(member: person, size: 22)
                                Text(person.name)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.fill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows every memory with \(person.name)")
                    }
                }

                if !memory.sceneTags.isEmpty {
                    Text("Scene tags from Vision: " + memory.sceneTags.joined(separator: ", ").lowercased())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(memory.hasVoice ? "Full Transcript" : "What happened")
                    if voice.isTranscribing(memory.id) {
                        Label("Writing it down on your \(Device.name)…", systemImage: "waveform")
                            .foregroundStyle(.secondary)
                            .symbolEffect(.variableColor.iterative)
                    } else if memory.transcriptUnavailable || voice.problem(for: memory.id) != nil {
                        Text(voice.problem(for: memory.id)?.errorDescription
                             ?? "This language can't be written down on this device yet.")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 18) {
                            if !(voice.problem(for: memory.id)?.isPermanent ?? memory.transcriptUnavailable),
                               store.recordingURL(for: memory) != nil {
                                Button("Try Again") { Task { await voice.transcribe(memory.id) } }
                                    .tapTarget()
                            }
                            Button("Type it myself") { router.activeSheet = .typeNote(memory.id) }
                                .tapTarget()
                        }
                        .font(.subheadline.bold())
                    } else if !memory.hasText && memory.hasVoice && store.recordingURL(for: memory) != nil {
                        Text("Not written down yet.").foregroundStyle(.secondary)
                        Button("Write It Down") { Task { await voice.transcribe(memory.id) } }
                            .font(.subheadline.bold())
                            .tapTarget()
                    } else if !memory.hasText {
                        Text(memory.photos.isEmpty ? "No text yet." : "Photo memory, no text.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(memory.transcript)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let linked = memory.linkedActivity {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.checkmark")
                            .foregroundStyle(.purple)
                            .frame(width: 40, height: 40)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RELATED ITINERARY ITEM").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(linked).font(.subheadline.bold()).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if memory.isVisited {
                            StatusBadge(text: "Visited", color: .green)
                        }
                    }
                    .card(padding: 12, fill: Theme.raised, cornerRadius: 16)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            if let recording = store.recordingURL(for: memory) {
                Button {
                    playback.toggle(recording)
                } label: {
                    Label(playback.isPlaying ? "Pause" : "Play Recording",
                          systemImage: playback.isPlaying ? "pause.circle" : "play.circle")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .onDisappear { playback.stop() }
        .confirmationDialog("Delete this memory?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Memory", role: .destructive) {
                if store.deleteMemory(memory.id) { dismiss() }
            }
        } message: {
            Text("Its text, photos and recording will be removed from this \(Device.name). It can't be undone.")
        }
    }

    private func chipButton(_ title: String, icon: String?, tint: Color? = nil, search: String) -> some View {
        Button {
            searchInsights(for: search)
        } label: {
            Chip(title, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows every memory mentioning \(title)")
    }

    private func searchInsights(for text: String) {
        dismiss()
        router.searchInsights(for: text)
    }

    private func photos(_ memory: Memory) -> some View {
        TabView(selection: $photoIndex) {
            ForEach(Array(memory.photos.enumerated()), id: \.offset) { index, photo in
                MemoryPhotoView(photo: photo).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if memory.photos.count > 1 {
                GlassPill("\(photoIndex + 1) / \(memory.photos.count)").font(.caption).padding(12)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let landmark = memory.landmark {
                GlassPill(landmark + (memory.landmarkConfidence.map { "  \($0.percentText)" } ?? ""),
                          icon: "building.columns.fill")
                    .padding(12)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(memory.photos.count) photo\(memory.photos.count == 1 ? "" : "s")"
                            + (memory.landmark.map { ", recognised as \($0)" } ?? ""))
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    Text("Journal")
        .sheet(isPresented: .constant(true)) {
            MemoryDetailView(memoryID: dependencies.store.latestMemory?.id ?? UUID())
        }
        .previewEnvironment(dependencies)
}

struct MemoryFormView: View {
    @State private var viewModel: MemoryFormViewModel
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var showsPhotoPicker: Bool
    @State private var playback = AudioPlayback()
    @State private var didSave = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    private let start: MemoryFormStart

    private enum Field {
        case title, text, place
    }

    // start decides whether to record or open the picker straight away
    init(viewModel: MemoryFormViewModel, start: MemoryFormStart = .writing) {
        _viewModel = State(initialValue: viewModel)
        _showsPhotoPicker = State(initialValue: start == .photos)
        self.start = start
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.canRecord {
                        voiceSection
                    }
                    tripAndTime
                    FormField(label: viewModel.hasRecording ? "Title (optional)" : "Title") {
                        TextField(viewModel.hasRecording ? viewModel.automaticTitle : "Blue train at Nine Arch Bridge",
                                  text: $viewModel.title)
                            .focused($focusedField, equals: .title)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .text }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("What happened")
                        TextEditor(text: $viewModel.text)
                            .focused($focusedField, equals: .text)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
                            .overlay(alignment: .topLeading) {
                                if viewModel.text.isEmpty {
                                    Text("Waited on the ridge for the blue train…")
                                        .foregroundStyle(.tertiary)
                                        .padding(18)
                                        .allowsHitTesting(false)
                                }
                            }
                            .accessibilityLabel("What happened")
                    }
                    photosSection
                    if viewModel.showsLandmarkSection {
                        LandmarkRecognitionSection(viewModel: viewModel)
                    }
                    placeSection
                    if !viewModel.members.isEmpty {
                        peopleSection
                    }
                    moodSection
                    if !viewModel.activitiesOnDay.isEmpty {
                        activitySection
                    }
                    if let problem = viewModel.problem, !viewModel.title.isEmpty || viewModel.photoCount > 0 {
                        Text(problem).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.card)
            .navigationTitle(viewModel.formTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        playback.stop()
                        viewModel.discardUnsavedRecording()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        playback.stop()
                        if viewModel.save() {
                            didSave = true
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .alert("Couldn't save the memory", isPresented: Binding(
                get: { viewModel.saveProblem != nil },
                set: { if !$0 { viewModel.saveProblem = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.saveProblem ?? "")
            }
            .photosPicker(isPresented: $showsPhotoPicker, selection: $pickedPhotos,
                          maxSelectionCount: max(viewModel.remainingPhotoSlots, 1),
                          matching: .images, preferredItemEncoding: .compatible)
            .onChange(of: pickedPhotos) { _, items in
                guard !items.isEmpty else { return }
                pickedPhotos = []
                Task { await loadPhotos(items) }
            }
            .task {
                switch start {
                case .recording: await viewModel.startRecording()
                case .writing: if !viewModel.isEditing { focusedField = .title }
                case .photos: break
                }
            }
            // Swiping down = Cancel
            .onDisappear {
                playback.stop()
                if !didSave { viewModel.discardUnsavedRecording() }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Voice")
            VStack(spacing: 14) {
                if viewModel.isRecording {
                    LevelMeterView(levels: viewModel.recordingLevels)
                        .frame(height: 70)
                    Text(viewModel.recordingElapsed.timerText)
                        .scaledFont(size: 40, weight: .light, design: .rounded)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel("Recording, \(viewModel.recordingElapsed) seconds")
                    Button {
                        withMotion { viewModel.stopRecording() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false, height: 44))
                } else if viewModel.hasRecording {
                    HStack(spacing: 14) {
                        Button {
                            if let url = viewModel.recordingURL { playback.toggle(url) }
                        } label: {
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Theme.purple, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.recordingURL == nil)
                        .accessibilityLabel(playback.isPlaying ? "Pause" : "Play recording")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Recording • \(viewModel.recordingDuration.timerText)").font(.headline)
                            ProgressView(value: playback.progress).tint(.purple)
                        }
                        Menu {
                            Button {
                                playback.stop()
                                Task { await viewModel.startRecording() }
                            } label: {
                                Label("Record Again", systemImage: "mic")
                            }
                            Button(role: .destructive) {
                                playback.stop()
                                withMotion { viewModel.removeRecording() }
                            } label: {
                                Label("Remove Recording", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.title2).tapTarget()
                        }
                        .accessibilityLabel("Recording options")
                    }
                    Text("It's written down on this \(Device.name) after you save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await viewModel.startRecording() }
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(Theme.purple, in: Circle())
                            .padding(8)
                            .background(Theme.purple.opacity(0.25), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start recording")
                    Text("Tap to record. Recordings and transcripts stay on this \(Device.name).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let problem = viewModel.recordingProblem {
                    Text(problem).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .sensoryFeedback(.start, trigger: viewModel.isRecording)
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var files: [Data] = []
        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    files.append(data)
                }
            } catch {
                viewModel.reportPhotoProblem("Couldn't load a photo. \(error.localizedDescription)")
            }
        }
        await viewModel.addPhotos(files)
    }

    private var tripAndTime: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Trip")
            VStack(spacing: 0) {
                Picker(selection: $viewModel.tripID) {
                    ForEach(viewModel.trips) { trip in
                        Text(trip.name).tag(Optional(trip.id))
                    }
                } label: {
                    Label("Trip", systemImage: "suitcase")
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider().padding(.leading, 16)
                // Label beside the picker, or above it when large text leaves no room
                ViewThatFits(in: .horizontal) {
                    DatePicker(selection: $viewModel.date, in: viewModel.dateRange) { whenLabel }
                    VStack(alignment: .leading, spacing: 8) {
                        whenLabel
                        DatePicker("When", selection: $viewModel.date, in: viewModel.dateRange)
                            .labelsHidden()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .card(padding: 0, fill: Theme.raised, cornerRadius: 14)
        }
    }

    private var whenLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("When")
            Text(viewModel.dayText).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Photos")
                Spacer()
                if viewModel.photoCount > 0 {
                    Text("\(viewModel.photoCount) of \(MemoryFormViewModel.maxPhotos)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        showsPhotoPicker = true
                    } label: {
                        VStack(spacing: 6) {
                            if viewModel.isPreparingPhotos {
                                ProgressView()
                            } else {
                                Image(systemName: "photo.badge.plus").font(.title2)
                            }
                            Text("Add").font(.caption)
                        }
                        .foregroundStyle(.blue)
                        .frame(width: 84, height: 84)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(.blue.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.remainingPhotoSlots == 0 || viewModel.isPreparingPhotos)
                    .accessibilityLabel("Add photos")

                    ForEach(viewModel.existingPhotos, id: \.key) { photo in
                        thumbnail {
                            MemoryPhotoView(photo: photo, thumbnail: true)
                        } remove: {
                            withMotion { viewModel.removeExistingPhoto(photo) }
                        }
                    }
                    ForEach(Array(viewModel.newPhotos.enumerated()), id: \.offset) { index, photo in
                        thumbnail {
                            if let image = UIImage(data: photo.thumbnail) {
                                Image(uiImage: image).resizable().scaledToFill()
                            }
                        } remove: {
                            withMotion { viewModel.removeNewPhoto(at: index) }
                        }
                    }
                }
                .padding(.top, 6)
            }
            if let problem = viewModel.photoProblem {
                Text(problem).font(.caption).foregroundStyle(.red)
            } else {
                Text("Only the photos you pick are shared with RoamPulse. They're resized and kept on this \(Device.name).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func thumbnail<Content: View>(@ViewBuilder content: () -> Content, remove: @escaping () -> Void) -> some View {
        content()
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .tapTarget()
                }
                .accessibilityLabel("Remove photo")
            }
    }

    private var placeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FormField(label: "Place") {
                TextField("Ella", text: $viewModel.place)
                    .focused($focusedField, equals: .place)
            }
            if !viewModel.placeSuggestions.isEmpty {
                FlowLayout {
                    ForEach(viewModel.placeSuggestions, id: \.self) { place in
                        Button { viewModel.place = place } label: {
                            Chip(place, icon: "mappin", isSelected: viewModel.place == place)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Who was there")
            FlowLayout {
                ForEach(viewModel.members) { member in
                    let isSelected = viewModel.peopleIDs.contains(member.id)
                    Button {
                        viewModel.togglePerson(member)
                    } label: {
                        HStack(spacing: 6) {
                            AvatarView(member: member, size: 24)
                            Text(member.isMe ? "\(member.name) (me)" : member.name)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.blue.opacity(0.25) : Theme.fill, in: Capsule())
                        .overlay(Capsule().strokeBorder(isSelected ? Color.blue : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("How did it feel?")
            HStack(spacing: 8) {
                ForEach(Mood.allCases) { mood in
                    let isSelected = viewModel.mood == mood
                    Button {
                        viewModel.mood = isSelected ? nil : mood
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: mood.icon).font(.title3).symbolRenderingMode(.multicolor)
                            Text(mood.rawValue).font(.caption)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(isSelected ? mood.color.opacity(0.2) : Theme.raised,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? mood.color : Theme.stroke))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            Text("Optional. Tap again to clear.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Part of the plan")
            VStack(spacing: 0) {
                Picker(selection: $viewModel.linkedActivityID) {
                    Text("Not linked").tag(UUID?.none)
                    ForEach(viewModel.activitiesOnDay) { activity in
                        Text("\(activity.timeText) \(activity.title)").tag(Optional(activity.id))
                    }
                } label: {
                    Label("Activity", systemImage: "calendar")
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                if viewModel.linkedActivityID != nil {
                    Divider().padding(.leading, 16)
                    Toggle("Mark activity as visited", isOn: $viewModel.markVisited)
                        .tint(.green)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }
            .card(padding: 0, fill: Theme.raised, cornerRadius: 14)
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    Text("Journal")
        .sheet(isPresented: .constant(true)) {
            MemoryFormView(viewModel: MemoryFormViewModel(store: dependencies.store, clock: dependencies.clock))
        }
        .previewEnvironment(dependencies)
}

// Newest on the right
struct LevelMeterView: View {
    let levels: [Double]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.purple)
                    .frame(width: 4, height: max(6, 70 * level))
            }
        }
        .frame(maxHeight: .infinity)
        .motionAnimation(.linear(duration: 0.05), value: levels)
        .accessibilityHidden(true)
    }
}

// For when transcription isn't available
struct TypeNoteView: View {
    let memoryID: UUID
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding()
                .navigationTitle(store.memory(memoryID)?.title ?? "Type a note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            store.updateTranscript(text, for: memoryID)
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.card)
    }
}
