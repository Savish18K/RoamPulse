import AVFoundation
import Foundation
import Speech

enum TranscriptionError: LocalizedError, Equatable {
    case permissionDenied
    /// On-device transcription isn't available for this language (or on this device).
    case languageNotSupported(String)
    /// The Simulator has no speech recognition service; it works on a real iPhone.
    case notInSimulator
    case nothingHeard
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Speech recognition is turned off for RoamPulse. The recording is saved. Turn it on in Settings, or type the note yourself."
        case .languageNotSupported(let language):
            "\(language) can't be written down on this device yet. The recording is saved."
        case .notInSimulator:
            "The Simulator can't write recordings down; this works on a real iPhone. The recording is saved."
        case .nothingHeard:
            "No speech was heard in the recording."
        case .failed(let reason):
            "The recording couldn't be written down. \(reason)"
        }
    }

    /// Trying again won't help: the user has to type the note or change a setting.
    var isPermanent: Bool {
        switch self {
        case .permissionDenied, .languageNotSupported, .notInSimulator: true
        case .nothingHeard, .failed: false
        }
    }
}

/// Turns a recording into text. Behind a protocol so the journal pipeline is tested without audio.
protocol SpeechTranscribing {
    func transcribe(_ recording: URL, locale: Locale) async throws -> String
}

/// Speech-to-text that runs entirely on the iPhone: nothing is sent to a server.
///
/// iOS 26's `SpeechAnalyzer` with a `SpeechTranscriber` module is used when it supports the language
/// (its language model is downloaded once by the system, then works offline). Otherwise the older
/// `SFSpeechRecognizer` is used, but only in on-device mode. If neither can, the language isn't supported.
struct OnDeviceTranscriber: SpeechTranscribing {
    func transcribe(_ recording: URL, locale: Locale) async throws -> String {
        guard await Self.requestPermission() else { throw TranscriptionError.permissionDenied }

        let text: String
        if SpeechTranscriber.isAvailable, let supported = await Self.supportedLocale(for: locale) {
            text = try await transcribeWithAnalyzer(recording, locale: supported)
        } else {
            text = try await transcribeWithRecognizer(recording, locale: locale)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.nothingHeard }
        return trimmed
    }

    /// The phone's language, or US English for other English variants (e.g. en-LK) when needed.
    private static func supportedLocale(for locale: Locale) async -> Locale? {
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return supported
        }
        guard locale.language.languageCode == .english else { return nil }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
    }

    private func transcribeWithAnalyzer(_ recording: URL, locale: Locale) async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        do {
            // The language model is part of the system; this downloads it the first time only.
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installation.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let audio = try AVAudioFile(forReading: recording)

            // Results arrive while the file is analysed; collect them until the analyzer finishes.
            async let text = transcriber.results.reduce(into: "") { text, result in
                text += String(result.text.characters)
            }
            if let end = try await analyzer.analyzeSequence(from: audio) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await text
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.failed(error.localizedDescription)
        }
    }

    private func transcribeWithRecognizer(_ recording: URL, locale: Locale) async throws -> String {
        let language = locale.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? "")
            ?? locale.identifier
        guard let recognizer = Self.recognizer(for: locale) else {
            throw TranscriptionError.languageNotSupported(language)
        }
        let request = SFSpeechURLRecognitionRequest(url: recording)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = ResumeFlag()
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    let problem: TranscriptionError = Self.isMissingSpeechService(error)
                        ? .notInSimulator : .failed(error.localizedDescription)
                    if resumed.claim() { continuation.resume(throwing: problem) }
                } else if let result, result.isFinal {
                    if resumed.claim() { continuation.resume(returning: result.bestTranscription.formattedString) }
                }
            }
        }
    }

    /// A recogniser for the phone's language, or US English for English variants it doesn't know (e.g. en-LK).
    private static func recognizer(for locale: Locale) -> SFSpeechRecognizer? {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map { $0.identifier(.bcp47) })
        var candidates = [Locale(languageCode: locale.language.languageCode, languageRegion: locale.region)]
        if locale.language.languageCode == .english {
            candidates.append(Locale(identifier: "en-US"))
        }
        return candidates
            .filter { supported.contains($0.identifier(.bcp47)) }
            .lazy
            .compactMap { SFSpeechRecognizer(locale: $0) }
            .first { $0.supportsOnDeviceRecognition }
    }

    /// The Simulator has no speech service: every request fails with this error (kAFAssistantErrorDomain 1101).
    private static func isMissingSpeechService(_ error: Error) -> Bool {
        #if targetEnvironment(simulator)
        let error = error as NSError
        return error.domain == "kAFAssistantErrorDomain" && error.code == 1101
        #else
        return false
        #endif
    }

    /// Speech recognition permission, asked the first time a recording is transcribed.
    private static func requestPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }
}

/// Makes sure a continuation is resumed only once (the recogniser can call back more than once).
private final class ResumeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return false }
        done = true
        return true
    }
}
