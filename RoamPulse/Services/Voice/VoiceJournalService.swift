import Foundation
import NaturalLanguage
import Observation

// Transcribes voice memories and runs the NL analysis, recording is saved first so nothing is lost
@MainActor
@Observable
final class VoiceJournalService {
    private(set) var inProgress: Set<UUID> = []
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
                store.updateMemory(memoryID) { $0.transcriptUnavailable = true }
            }
        }
    }

    // Not awaited, can take a while the first time
    func prepareLanguageData() async {
        await JournalAnalyzer.prepareLanguageData(for: NLLanguage(locale.language.languageCode?.identifier ?? "en"))
    }

    // Leftover recordings, e.g. the app was closed while transcribing
    func transcribePending() async {
        let pending = store.memories.filter { memory in
            memory.hasVoice && !memory.hasText && store.recordingURL(for: memory) != nil
        }
        for memory in pending {
            await transcribe(memory.id)
        }
    }
}

// For previews and tests
struct SampleTranscriber: SpeechTranscribing {
    var text = "Waited on the ridge with Suu and Samee for the blue train. It crossed Nine Arch Bridge right on time."

    func transcribe(_ recording: URL, locale: Locale) async throws -> String { text }
}
