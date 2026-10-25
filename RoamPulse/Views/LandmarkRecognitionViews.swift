import SwiftUI

// Shown under the photos in the memory form: what the landmark model found, and the user's say on it
struct LandmarkRecognitionSection: View {
    let viewModel: MemoryFormViewModel
    @State private var showsChooser = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Landmark")
            if viewModel.isRecognising {
                Label("Recognising the landmark on your iPhone…", systemImage: "viewfinder")
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse)
            } else if let info = viewModel.landmarkInfo {
                recognised(info)
            } else if viewModel.needsLandmarkConfirmation, let result = viewModel.recognition {
                confirm(result)
            } else if let problem = viewModel.recognitionProblem {
                Text(problem).font(.footnote).foregroundStyle(.secondary)
            }

            if !viewModel.sceneTags.isEmpty {
                FlowLayout {
                    ForEach(viewModel.sceneTags, id: \.self) { tag in
                        Chip(tag, icon: "sparkles")
                    }
                }
                .accessibilityLabel("Scene tags: " + viewModel.sceneTags.joined(separator: ", "))
            }

            if let named = viewModel.conflictingLandmark, let photo = viewModel.landmark {
                conflict(named: named.name, photo: photo)
            }
        }
        .sheet(isPresented: $showsChooser) {
            NavigationStack {
                LandmarkChooserView(selection: viewModel.landmark) { name in
                    viewModel.chooseLandmark(name)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func recognised(_ info: LandmarkInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PhotoView(photo: info.photo)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name).font(.headline)
                    Text(viewModel.landmarkConfidence.map { "Recognised on device • \($0.percentText)" } ?? "Chosen by you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let confidence = viewModel.landmarkConfidence {
                ConfidenceBar(value: confidence, threshold: viewModel.recognition?.threshold)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 18) {
                Button("Change") { showsChooser = true }
                Button("Not a landmark", role: .destructive) {
                    withAnimation { viewModel.rejectLandmark() }
                }
            }
            .font(.subheadline.bold())
        }
        .padding(14)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // Below the threshold the guess is never saved on its own, the user picks instead
    private func confirm(_ result: RecognitionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(result.isOther ? "This doesn't look like a landmark RoamPulse knows. Is it one of these?"
                                : "Not sure about this one. Which landmark is it?")
                .font(.subheadline)
            ForEach(result.suggestions) { candidate in
                Button {
                    withAnimation { viewModel.chooseLandmark(candidate.name) }
                } label: {
                    HStack {
                        Text(candidate.name)
                        Spacer()
                        Text(candidate.confidence.percentText).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(candidate.name), \(candidate.confidence.percentText) match")
            }
            HStack(spacing: 18) {
                Button("Something else") { showsChooser = true }
                Button("Not a landmark") {
                    withAnimation { viewModel.rejectLandmark() }
                }
            }
            .font(.subheadline.bold())
        }
        .padding(14)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // The voice note or text names a different landmark than the photo shows
    private func conflict(named: String, photo: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your note mentions \(named), but the photo looks like \(photo). Which is right?",
                  systemImage: "questionmark.circle")
                .font(.subheadline)
            HStack(spacing: 18) {
                Button(named) { withAnimation { viewModel.chooseLandmark(named) } }
                Button(photo) { withAnimation { viewModel.keepPhotoLandmark() } }
            }
            .font(.subheadline.bold())
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// Green to blue bar, with a tick where the model's threshold is
struct ConfidenceBar: View {
    let value: Double
    var threshold: Double?
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule()
                    .fill(LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * value)
                if let threshold {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: height + 10)
                        .offset(x: proxy.size.width * threshold)
                }
            }
        }
        .frame(height: height)
    }
}

// Every landmark the model knows, to pick the right one by hand
struct LandmarkChooserView: View {
    let selection: String?
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(LandmarkCatalogue.all) { landmark in
            Button {
                onPick(landmark.name)
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
        .navigationTitle("Choose Landmark")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
