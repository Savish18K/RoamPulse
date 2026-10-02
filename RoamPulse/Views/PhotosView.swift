import SwiftUI

// MARK: - PhotoPickerView

/// Mock photo picker that matches the prototype.
/// In the real app this becomes PhotosUI's `PhotosPicker`.
struct PhotoPickerView: View {
    let memoryID: UUID?

    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [SamplePhoto] = []
    @State private var tab = 0
    @State private var showRecognition = false

    private let recents: [SamplePhoto] = [
        .nineArchBridge, .blueTrainBridge, .teaSunset, .trainWindow, .hillTrain, .sigiriya,
        .colomboSkyline, .jaffnaKovil, .teaEstate, .mistyHills, .ellaRidge, .galleFort,
    ]

    private var targetTitle: String {
        memoryID.flatMap { store.memory($0)?.title } ?? "New memory"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SegmentedTabs(options: ["Photos", "Collections"], selection: $tab)

                    if tab == 0 {
                        photosGrid
                    } else {
                        collections
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.secondary)
                        Text("RoamPulse only sees the photos you pick. Landmark recognition runs on this iPhone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .card(padding: 14, fill: Theme.raised, cornerRadius: 14)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Photos").font(.headline)
                        Text("Adding to: \(targetTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selection.count))") { showRecognition = true }
                        .disabled(selection.isEmpty)
                }
            }
            .navigationDestination(isPresented: $showRecognition) {
                PhotoRecognitionView(photos: selection, memoryID: memoryID)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    private var photosGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recents").font(.title2.bold())
                    Text("Sun 13 Dec • \(store.currentTrip?.name ?? "All photos")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(selection.count) selected").font(.subheadline.bold())
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(recents) { photo in
                    Button {
                        toggle(photo)
                    } label: {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { PhotoView(photo: photo) }
                            .clipped()
                            .overlay(alignment: .bottomTrailing) { selectionBadge(for: photo) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.rawValue)
                    .accessibilityAddTraits(selection.contains(photo) ? .isSelected : [])
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func selectionBadge(for photo: SamplePhoto) -> some View {
        Group {
            if let index = selection.firstIndex(of: photo) {
                Text("\(index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.blue, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            } else {
                Circle()
                    .fill(.black.opacity(0.2))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            }
        }
        .padding(8)
    }

    private var collections: some View {
        VStack(spacing: 0) {
            ForEach(store.trips) { trip in
                Button {
                    tab = 0
                } label: {
                    HStack(spacing: 14) {
                        PhotoView(photo: trip.cover)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trip.name).font(.headline)
                            Text(trip.compactDateRange).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 0, fill: Theme.raised)
    }

    private func toggle(_ photo: SamplePhoto) {
        if let index = selection.firstIndex(of: photo) {
            selection.remove(at: index)
        } else {
            selection.append(photo)
        }
    }
}

#Preview {
    Text("Journal")
        .sheet(isPresented: .constant(true)) {
            PhotoPickerView(memoryID: nil)
                .environment(TripStore())
                .environment(AppRouter())
        }
        .preferredColorScheme(.dark)
}

// MARK: - PhotoRecognitionView

/// Recognising → Recognised (≥ 70%) or Please confirm (< 70%), one photo at a time.
/// Results come from `SamplePhoto.recognition` until the Core ML model is added.
struct PhotoRecognitionView: View {
    let photos: [SamplePhoto]
    let memoryID: UUID?

    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router

    private enum Stage { case recognising, recognised, confirm }

    @State private var index = 0
    @State private var stage: Stage = .recognising
    @State private var progress: Double = 0
    @State private var chosen: String?
    @State private var markVisited = true
    @State private var savedMemoryID: UUID?
    @State private var showCatalogue = false

    private var photo: SamplePhoto { photos[index] }
    private var result: RecognitionResult { photo.recognition }
    private var trip: Trip? { store.currentTrip }
    private var targetMemoryID: UUID? { savedMemoryID ?? memoryID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch stage {
                case .recognising: recognisingContent
                case .recognised: recognisedContent
                case .confirm: confirmContent
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { bottomButtons }
        .navigationTitle("Photo \(index + 1) of \(photos.count)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { router.activeSheet = nil }
            }
            if index < photos.count - 1 {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { index += 1 }
                        .disabled(stage == .recognising)
                }
            }
        }
        .navigationDestination(isPresented: $showCatalogue) {
            LandmarkChooserView(selection: $chosen)
        }
        .task(id: index) { await recognise() }
    }

    // MARK: - Recognising

    private var recognisingContent: some View {
        Group {
            photoHeader(badge: "Recognising on your device", icon: nil)
                .overlay { ScanOverlay() }

            VStack(spacing: 0) {
                stepRow("Photo prepared", "Resized on the iPhone for the model", state: stepState(from: 0, to: 0.15))
                Divider()
                stepRow("Landmark model", "Core ML • trained on 10 Sri Lankan landmarks", state: stepState(from: 0.15, to: 0.75))
                Divider()
                stepRow("Scene tags", "Vision image classifier", state: stepState(from: 0.75, to: 0.9))
                Divider()
                stepRow("Link to your plan", "\(trip?.name ?? "Your trip") • Day \(trip?.dayNumber() ?? 1)", state: stepState(from: 0.9, to: 1))
            }
            .card(padding: 14, fill: Theme.raised)

            Label("Nothing leaves this iPhone. Works in Airplane Mode.", systemImage: "airplane")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private enum StepState { case pending, running(Double), done }

    private func stepState(from start: Double, to end: Double) -> StepState {
        if progress >= end { return .done }
        if progress >= start { return .running((progress - start) / (end - start)) }
        return .pending
    }

    private func stepRow(_ title: String, _ detail: String, state: StepState) -> some View {
        var isPending = false
        if case .pending = state { isPending = true }

        return HStack(spacing: 14) {
            Group {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                case .running:
                    ProgressView()
                case .pending:
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .font(.title2)
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .done: Text("Done").font(.subheadline).foregroundStyle(.secondary)
            case .running(let value): Text(value.percentText).font(.subheadline.bold())
            case .pending: EmptyView()
            }
        }
        .padding(.vertical, 10)
        .opacity(isPending ? 0.5 : 1)
    }

    // MARK: - Recognised

    private var recognisedContent: some View {
        let top = result.top ?? LandmarkCandidate(name: "Unknown", confidence: 0)
        let landmark = store.landmarks.first { $0.name == top.name }
        let activity = matchingActivity(for: top.name)

        return Group {
            photoHeader(badge: "Recognised on device", icon: "checkmark.circle.fill")

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "building.columns.fill")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(top.name).font(.title2.bold())
                        Text(landmark?.location ?? "Sri Lanka").foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(top.confidence.percentText).font(.title.bold()).foregroundStyle(.secondary)
                        Text("confidence").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ConfidenceBar(value: top.confidence)
                Text("Above the \(RecognitionResult.threshold.percentText) threshold, so it is labelled automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .card(fill: Theme.raised)

            sceneTags

            if let memoryID = targetMemoryID, let memory = store.memory(memoryID),
               memory.transcript.localizedCaseInsensitiveContains(top.name) {
                HStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .frame(width: 40, height: 40)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Matches your voice memory").font(.subheadline.bold())
                        Text("You said “\(top.name)” in this memory.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: "Agree", color: .green)
                }
                .card(padding: 14, fill: Theme.raised)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark")
                        .frame(width: 40, height: 40)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LINKED ITINERARY ITEM").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(activity.map { "Day \($0.day) • \($0.timeText) \($0.title)" } ?? "No matching activity in this trip")
                            .font(.subheadline.bold())
                    }
                }
                if activity != nil {
                    Divider()
                    Toggle("Mark activity as visited", isOn: $markVisited)
                }
            }
            .card(padding: 14, fill: Theme.raised)
        }
    }

    // MARK: - Please confirm

    private var confirmContent: some View {
        Group {
            photoHeader(badge: "Not sure. Please confirm", icon: "questionmark.circle")

            VStack(alignment: .leading, spacing: 6) {
                Text("Which landmark is this?").font(.title2.bold())
                Text("The best match is below \(RecognitionResult.threshold.percentText) confidence, so RoamPulse will not label this photo on its own.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(result.candidates) { candidate in
                    Button {
                        chosen = candidate.name
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: chosen == candidate.name ? "largecircle.fill.circle" : "circle")
                                .font(.title2)
                                .foregroundStyle(chosen == candidate.name ? Color.primary : Color.secondary)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(candidate.name).font(.headline)
                                ConfidenceBar(value: candidate.confidence, showsThreshold: false, height: 4)
                            }
                            Text(candidate.confidence.percentText).font(.subheadline.bold())
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
                Button {
                    showCatalogue = true
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text(isCustomChoice ? "Chosen: \(chosen ?? "")" : "Choose another landmark")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .card(padding: 14, fill: Theme.raised)

            sceneTags

            Label("Your choice is saved with the photo. Nothing is labelled without you.", systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var isCustomChoice: Bool {
        guard let chosen else { return false }
        return !result.candidates.contains { $0.name == chosen }
    }

    // MARK: - Shared pieces

    private func photoHeader(badge: String, icon: String?) -> some View {
        PhotoView(photo: photo)
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: stage == .recognising ? .bottomLeading : .topLeading) {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                    } else {
                        ProgressView().tint(.white)
                    }
                    Text(badge)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(14)
            }
    }

    private var sceneTags: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Scene tags from Vision")
            FlowLayout {
                ForEach(result.sceneTags, id: \.self) { Chip($0) }
            }
        }
    }

    @ViewBuilder
    private var bottomButtons: some View {
        HStack(spacing: 12) {
            switch stage {
            case .recognising:
                Button("Recognising…") {}
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(true)
            case .recognised:
                Button("Change") { withAnimation { stage = .confirm } }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(width: 130)
                Button("Save to Memory") {
                    save(landmark: result.top?.name, confidence: result.top?.confidence)
                }
                .buttonStyle(PrimaryButtonStyle())
            case .confirm:
                Button("Skip") { save(landmark: nil, confidence: nil) }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(width: 110)
                Button(confirmTitle) {
                    let isOther = chosen == RecognitionResult.otherLabel
                    save(landmark: isOther ? nil : chosen, confidence: nil)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(chosen == nil)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var confirmTitle: String {
        guard let chosen else { return "Choose a landmark" }
        return chosen == RecognitionResult.otherLabel ? "Save without label" : "Confirm \(chosen)"
    }

    // MARK: - Actions

    private func recognise() async {
        stage = .recognising
        progress = 0
        chosen = nil
        for step in 1...25 {
            try? await Task.sleep(for: .milliseconds(70))
            if Task.isCancelled { return }
            progress = Double(step) / 25
        }
        withAnimation {
            stage = result.isConfident ? .recognised : .confirm
            chosen = result.isConfident ? nil : result.top?.name
        }
    }

    /// Placeholder link logic: first activity in the current trip whose title contains the landmark name.
    private func matchingActivity(for landmark: String) -> Activity? {
        let key = landmark.components(separatedBy: " (").first ?? landmark
        return trip?.activities.first { $0.title.localizedCaseInsensitiveContains(key) }
    }

    private func save(landmark: String?, confidence: Double?) {
        savedMemoryID = store.addPhoto(photo, landmark: landmark, confidence: confidence,
                                       sceneTags: result.sceneTags, to: targetMemoryID)
        if let landmark, markVisited, let trip, let activity = matchingActivity(for: landmark) {
            store.markVisited(activity.id, in: trip.id)
        }
        if index < photos.count - 1 {
            index += 1
        } else {
            router.activeSheet = nil
        }
    }
}

// MARK: - Helper views

/// Green → blue confidence bar with a tick at the 70% threshold.
struct ConfidenceBar: View {
    let value: Double
    var showsThreshold = true
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule()
                    .fill(LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * value)
                if showsThreshold {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: height + 10)
                        .offset(x: proxy.size.width * RecognitionResult.threshold)
                }
            }
        }
        .frame(height: height)
    }
}

/// Corner brackets + a moving scan line drawn over the photo while recognising.
private struct ScanOverlay: View {
    @State private var isAtBottom = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 4, dash: [40, 120]))
                    .frame(width: proxy.size.width * 0.45, height: proxy.size.height * 0.6)
                Rectangle()
                    .fill(.white)
                    .frame(height: 2)
                    .shadow(color: .white, radius: 6)
                    .offset(y: isAtBottom ? proxy.size.height * 0.35 : -proxy.size.height * 0.35)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isAtBottom = true
            }
        }
        .allowsHitTesting(false)
    }
}

/// List of all landmarks so the user can pick the right one.
struct LandmarkChooserView: View {
    @Binding var selection: String?
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(store.landmarks) { landmark in
                Button {
                    selection = landmark.name
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        PhotoView(photo: landmark.photo)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading) {
                            Text(landmark.name).foregroundStyle(.primary)
                            Text(landmark.location).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selection == landmark.name {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Choose Landmark")
        .navigationBarTitleDisplayMode(.inline)
    }
}
