import Foundation
import NaturalLanguage
import Observation

/// Turns saved voice memories into searchable, organised journal entries, all on the iPhone:
///
/// 1. **Capture** (AVFoundation): the memory and its recording are saved at once (`MemoryFormViewModel`),
///    so nothing is lost if the app is closed while it is being processed.
/// 2. **Transcribe** (Speech): `transcriber` writes the recording down on the device.
/// 3. **Analyse** (Natural Language): `JournalAnalyzer` finds places, people and the mood, and links the
///    memory to the activity it is about.
/// 4. **Store**: the memory is updated in Core Data, so search, the timeline and the mood chart use it.
///
/// If transcription fails, the recording is kept and the reason is shown, with Try Again (for
/// temporary problems) or Type It Myself (for an unsupported language or refused permission).
@MainActor
@Observable
final class VoiceJournalService {
    /// Memories being written down right now.
    private(set) var inProgress: Set<UUID> = []
    /// Why the last attempt failed, per memory.
    private(set) var problems: [UUID: TranscriptionError] = [:]

    @ObservationIgnored private let store: TripStore
    @ObservationIgnored private let transcriber: SpeechTranscribing
    @ObservationIgnored private let locale: Locale

    init(store: TripStore, transcriber: SpeechTranscribing, locale: Locale = .current) {
        self.store = store
        self.transcriber = transcriber
        self.locale = locale
    }

    func isTranscribing(_ memoryID: UUID) -> Bool { inProgress.contains(memoryID) }

    func problem(for memoryID: UUID) -> TranscriptionError? { problems[memoryID] }

    /// Writes the memory's recording down and analyses the text.
    func transcribe(_ memoryID: UUID) async {
        guard !inProgress.contains(memoryID), let memory = store.memory(memoryID),
              let recording = store.recordingURL(for: memory) else { return }
        inProgress.insert(memoryID)
        problems[memoryID] = nil
        defer { inProgress.remove(memoryID) }

        do {
            let text = try await transcriber.transcribe(recording, locale: locale)
            store.updateMemory(memoryID) { memory in
                memory.transcript = text
                memory.transcriptUnavailable = false
                if let trip = store.trip(memory.tripID) {
                    JournalAnalyzer.apply(JournalAnalyzer.analyse(text), text: text, to: &memory, trip: trip)
                }
            }
        } catch {
            let problem = error as? TranscriptionError ?? .failed(error.localizedDescription)
            problems[memoryID] = problem
            if problem.isPermanent {
                // Shown on the memory as "can't be written down on this device", with Type It Myself.
                store.updateMemory(memoryID) { $0.transcriptUnavailable = true }
            }
        }
    }

    /// Asks iOS for the on-device Natural Language data (names and sentiment) in the background.
    /// The first time, iOS may take a while to provide it, so nothing waits for this: until it is
    /// there, memories are still linked to trip members and places by name, just without a mood.
    func prepareLanguageData() async {
        await JournalAnalyzer.prepareLanguageData(for: NLLanguage(locale.language.languageCode?.identifier ?? "en"))
    }

    /// Recordings saved earlier but never written down (e.g. the app was closed while transcribing).
    func transcribePending() async {
        let pending = store.memories.filter { memory in
            memory.hasVoice && !memory.hasText && store.recordingURL(for: memory) != nil
        }
        for memory in pending {
            await transcribe(memory.id)
        }
    }
}

/// Used in previews and tests: always returns the same sentence.
struct SampleTranscriber: SpeechTranscribing {
    var text = "Waited on the ridge with Suu and Samee for the blue train. It crossed Nine Arch Bridge right on time."

    func transcribe(_ recording: URL, locale: Locale) async throws -> String { text }
}
