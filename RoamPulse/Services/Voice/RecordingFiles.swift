import Foundation

/// Where voice recordings are kept: one `.m4a` file per memory, named after it, in the
/// signed-in account's folder (Application Support/Accounts/<uid>/Recordings). Core Data stores only
/// the file name (`MemoryEntity.audioFileName`), because audio files can be several megabytes.
/// Recordings are never uploaded.
struct RecordingFiles {
    let directory: URL

    /// The recordings of one signed-in account. Deleting the account deletes this folder too.
    static func forAccount(_ accountID: String) -> RecordingFiles {
        RecordingFiles(directory: PersistenceController.folder(for: accountID).appending(path: "Recordings", directoryHint: .isDirectory))
    }

    /// Used before anyone signs in, and in tests.
    static var temporary: RecordingFiles {
        RecordingFiles(directory: FileManager.default.temporaryDirectory.appending(path: "RoamPulseRecordings", directoryHint: .isDirectory))
    }

    func url(for fileName: String) -> URL {
        directory.appending(path: fileName)
    }

    func exists(_ fileName: String?) -> Bool {
        guard let fileName else { return false }
        return FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    /// Moves a finished recording into the folder as `<memory id>.m4a`, replacing an older one.
    /// Returns the file name to save on the memory.
    func keep(_ recording: URL, for memoryID: UUID) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(memoryID.uuidString).m4a"
        let destination = url(for: fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: recording, to: destination)
        return fileName
    }

    func delete(_ fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
