import AVFoundation
import Foundation
import Observation

enum RecordingError: LocalizedError, Equatable {
    case microphoneDenied
    case couldNotStart(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "RoamPulse can't use the microphone. Turn it on in Settings → Privacy → Microphone."
        case .couldNotStart(let reason):
            "Recording couldn't start. \(reason)"
        }
    }
}

/// Records a voice memory with a live level meter. Behind a protocol so the journal form can be
/// tested without a microphone.
@MainActor
protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    /// Seconds recorded so far.
    var elapsed: TimeInterval { get }
    /// The last few loudness readings, 0 (silent) to 1 (loud), for the level meter.
    var levels: [Double] { get }
    /// Asks for the microphone the first time; afterwards just reports the answer.
    func requestPermission() async -> Bool
    func start() throws
    /// Stops and returns the finished file (in the temporary folder until the memory is saved).
    func stop() -> URL?
    /// Stops and throws the recording away.
    func discard()
}

/// `AVAudioRecorder`, recording AAC (`.m4a`, about 1 MB a minute) to a temporary file.
@MainActor
@Observable
final class AVAudioRecorderService: AudioRecording {
    /// Longest recording, so a forgotten recording doesn't fill the iPhone.
    static let maxDuration: TimeInterval = 10 * 60
    private static let levelCount = 32

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Double] = Array(repeating: 0, count: 32)

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    func start() throws {
        guard !isRecording else { return }
        let session = AVAudioSession.sharedInstance()
        let file = FileManager.default.temporaryDirectory.appending(path: "recording-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: file, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: Self.maxDuration) else {
                throw RecordingError.couldNotStart("The microphone may be in use by another app.")
            }
            self.recorder = recorder
        } catch let error as RecordingError {
            throw error
        } catch {
            throw RecordingError.couldNotStart(error.localizedDescription)
        }
        isRecording = true
        elapsed = 0
        levels = Array(repeating: 0, count: Self.levelCount)
        startMetering()
    }

    func stop() -> URL? {
        guard let recorder else { return nil }
        let url = recorder.url
        recorder.stop()
        finish()
        return url
    }

    func discard() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        finish()
    }

    private func finish() {
        meterTask?.cancel()
        meterTask = nil
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Reads the loudness 20 times a second for the meter and the timer.
    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let recorder = self.recorder else { return }
                if !recorder.isRecording {
                    // Reached the maximum length.
                    _ = self.stop()
                    return
                }
                recorder.updateMeters()
                self.elapsed = recorder.currentTime
                self.levels = Array((self.levels + [Self.normalised(recorder.averagePower(forChannel: 0))])
                    .suffix(Self.levelCount))
            }
        }
    }

    /// Decibels (-160 silent … 0 loudest) to 0…1. Below -50 dB counts as silence.
    nonisolated static func normalised(_ decibels: Float) -> Double {
        let floor: Float = -50
        guard decibels > floor else { return 0 }
        return Double(min((decibels - floor) / -floor, 1))
    }
}

/// Plays back a memory's recording (`AVAudioPlayer`) and reports the progress.
@MainActor
@Observable
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    var progress: Double { duration > 0 ? currentTime / duration : 0 }

    func toggle(_ url: URL) {
        isPlaying ? pause() : play(url)
    }

    func play(_ url: URL) {
        do {
            if loadedURL != url {
                player = try AVAudioPlayer(contentsOf: url)
                player?.delegate = self
                loadedURL = url
                duration = player?.duration ?? 0
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            player?.play()
            isPlaying = true
            errorMessage = nil
            trackProgress()
        } catch {
            errorMessage = "The recording couldn't be played. \(error.localizedDescription)"
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        progressTask?.cancel()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
        progressTask?.cancel()
    }

    private func trackProgress() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.progressTask?.cancel()
        }
    }
}
