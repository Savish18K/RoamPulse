import SwiftUI

// MARK: - JournalView

struct JournalView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(Array(store.sortedMemories.enumerated()), id: \.element.id) { index, memory in
                    MemoryCard(memory: memory, isFeatured: index == 0)
                        .contentShape(Rectangle())
                        .onTapGesture { router.activeSheet = .memory(memory.id) }
                        .accessibilityAddTraits(.isButton)
                }
                if store.memories.isEmpty {
                    ContentUnavailableView("No memories yet", systemImage: "waveform",
                                           description: Text("Record a voice memory or add a photo from your trip."))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Journal")
        .safeAreaInset(edge: .bottom) {
            FloatingActionBar(
                primaryTitle: "Record Memory",
                primaryAction: { router.activeSheet = .recordMemory },
                secondaryTitle: "Add Photo",
                secondaryAction: { router.activeSheet = .addPhoto(memoryID: store.latestMemory?.id) }
            )
        }
    }
}

/// Card for one memory in the Journal list.
struct MemoryCard: View {
    let memory: Memory
    var isFeatured = false
    @Environment(AppRouter.self) private var router
    @State private var isPlaying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(memory.title).font(.title3.bold()).lineLimit(1)
                    Text("\(memory.date.text("EEE HH:mm")) • \(memory.place)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if memory.hasVoice {
                    Button {
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                            .font(.title2)
                            .foregroundStyle(isFeatured ? .white : .secondary)
                            .frame(width: 44, height: 44)
                            .background(isFeatured ? Theme.purple : Theme.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "Pause" : "Play recording")
                }
            }

            if memory.transcriptUnavailable {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This language can't be written down on this device yet. Recording saved.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Type it myself") { router.activeSheet = .typeNote(memory.id) }
                        .font(.subheadline.bold())
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if !memory.transcript.isEmpty {
                Text(memory.transcript)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !memory.photos.isEmpty {
                photoStrip
            }

            let tags = chips
            if !tags.isEmpty {
                FlowLayout {
                    if let landmark = memory.landmark {
                        Chip(landmark, icon: "building.columns.fill", tint: .purple)
                    }
                    ForEach(tags, id: \.self) { Chip($0) }
                }
            }

            HStack(spacing: 8) {
                if !memory.people.isEmpty {
                    AvatarStack(members: memory.people, size: 24)
                }
                Text(footerText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
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
    }

    private var photoStrip: some View {
        HStack(spacing: 10) {
            PhotoView(photo: memory.photos[0])
                .overlay(alignment: .bottomLeading) {
                    if let landmark = memory.landmark {
                        GlassPill(landmark, icon: "building.columns.fill")
                            .font(.caption)
                            .padding(10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if memory.photos.count > 1 {
                PhotoView(photo: memory.photos[1])
                    .frame(width: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(height: 160)
    }

    /// Place tags plus a "Scene: …" chip.
    private var chips: [String] {
        var tags = memory.placeTags
        if !memory.sceneTags.isEmpty {
            tags.append("Scene: " + memory.sceneTags.prefix(2).joined(separator: ", ").lowercased())
        }
        if memory.landmark != nil && tags.isEmpty {
            tags.append(memory.place)
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

#Preview {
    NavigationStack { JournalView() }
        .environment(TripStore())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

// MARK: - MemoryDetailView

/// Memory detail sheet: photos, mood, playback, tags, transcript and linked activity.
struct MemoryDetailView: View {
    let memoryID: UUID

    @Environment(TripStore.self) private var store
    @State private var isEditing = false
    @State private var draft = ""
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var photoIndex = 0

    var body: some View {
        Group {
            if let memory = store.memory(memoryID) {
                content(memory)
            } else {
                ContentUnavailableView("Memory not found", systemImage: "waveform")
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
                    }
                    Spacer()
                    Button(isEditing ? "Done" : "Edit") {
                        if isEditing {
                            store.updateTranscript(draft, for: memory.id)
                        } else {
                            draft = memory.transcript
                        }
                        withAnimation { isEditing.toggle() }
                    }
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
                }

                if memory.hasVoice {
                    VStack(spacing: 6) {
                        ProgressView(value: progress).tint(.purple)
                        HStack {
                            Text(Int(progress * Double(memory.duration)).timerText)
                            Spacer()
                            Text(memory.duration.timerText)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                FlowLayout {
                    if let landmark = memory.landmark {
                        Chip(landmark, icon: "building.columns.fill", tint: .purple)
                    }
                    Chip(memory.place, icon: "mappin.and.ellipse")
                    if !memory.people.isEmpty {
                        HStack(spacing: 6) {
                            AvatarStack(members: memory.people, size: 22)
                            Text(memory.peopleText)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Theme.fill, in: Capsule())
                    }
                }

                if !memory.sceneTags.isEmpty {
                    Text("Scene tags from Vision: " + memory.sceneTags.joined(separator: ", ").lowercased())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Full Transcript")
                    if isEditing {
                        TextEditor(text: $draft)
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if memory.transcriptUnavailable {
                        Text("This language can't be written down on this device yet. Tap Edit to type it yourself.")
                            .foregroundStyle(.secondary)
                    } else if memory.transcript.isEmpty {
                        Text(memory.hasVoice ? "Transcribing on this iPhone…" : "Photo memory — no recording.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(memory.transcript)
                            .font(.body)
                            .foregroundStyle(.secondary)
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
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            if memory.hasVoice {
                Button {
                    isPlaying.toggle()
                } label: {
                    Label(isPlaying ? "Pause" : "Play Recording", systemImage: isPlaying ? "pause.circle" : "play.circle")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        // Simulated playback progress until AVFoundation playback is added.
        .task(id: isPlaying) {
            while isPlaying, !Task.isCancelled, progress < 1 {
                try? await Task.sleep(for: .milliseconds(100))
                progress = min(progress + 0.1 / Double(max(memory.duration, 1)), 1)
            }
            if progress >= 1 {
                isPlaying = false
                progress = 0
            }
        }
    }

    private func photos(_ memory: Memory) -> some View {
        TabView(selection: $photoIndex) {
            ForEach(Array(memory.photos.enumerated()), id: \.offset) { index, photo in
                PhotoView(photo: photo).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 230)
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
    }
}

#Preview {
    Text("Journal")
        .sheet(isPresented: .constant(true)) {
            MemoryDetailView(memoryID: SampleData.memories.last!.id).environment(TripStore())
        }
        .preferredColorScheme(.dark)
}

// MARK: - RecordMemoryView

/// Record a voice memory. The recording is simulated for now —
/// AVFoundation + Speech will replace the timer and waveform.
struct RecordMemoryView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var place = ""
    @State private var isRecording = false
    @State private var elapsed = 0

    private var trip: Trip? { store.currentTrip }
    private var day: Int { trip?.dayNumber() ?? 1 }

    var body: some View {
        VStack(spacing: 18) {
            FormField(label: "Memory Title") {
                TextField("View from the homestay balcony", text: $title)
            }

            HStack(spacing: 12) {
                FormField(label: "Trip & Day") {
                    Text("\(trip?.name ?? "No trip") • Day \(day)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                FormField(label: "Place") {
                    TextField("Ella", text: $place)
                }
                .frame(maxWidth: 150)
            }

            WaveformView(isAnimating: isRecording)
                .frame(height: 100)

            Text(elapsed.timerText)
                .font(.system(size: 52, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("Recordings and transcripts stay on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    withAnimation { isRecording.toggle() }
                } label: {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .background(Theme.purple, in: Circle())
                        .padding(10)
                        .background(Theme.purple.opacity(0.25), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")

                Spacer()

                Button("Save Memory", action: save)
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                    .disabled(elapsed == 0)
            }
        }
        .padding(24)
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
        .sensoryFeedback(.start, trigger: isRecording)
        .task(id: isRecording) {
            while isRecording, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if isRecording && !Task.isCancelled { elapsed += 1 }
            }
        }
    }

    private func save() {
        guard let trip else { return }
        let memory = Memory(
            tripID: trip.id,
            title: title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled memory" : title,
            date: DemoClock.now,
            day: day,
            place: place.isEmpty ? trip.destination : place,
            transcript: "",
            duration: elapsed,
            people: []
        )
        store.addMemory(memory)
        dismiss()
    }
}

/// Animated purple bars shown while recording.
struct WaveformView: View {
    var isAnimating: Bool
    var barCount = 26

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = Double(index) * 0.55
                    let level = isAnimating
                        ? 0.2 + 0.8 * abs(sin(time * 3 + phase) * cos(time * 1.3 + phase * 0.5))
                        : 0.15 + 0.1 * abs(sin(phase))
                    Capsule()
                        .fill(Color.purple)
                        .frame(width: 4, height: max(6, 96 * level))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// Lets the user type a note when on-device transcription isn't available.
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

#Preview {
    Text("Journal")
        .sheet(isPresented: .constant(true)) {
            RecordMemoryView().environment(TripStore())
        }
        .preferredColorScheme(.dark)
}
