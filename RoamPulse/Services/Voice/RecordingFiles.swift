import Foundation

// One .m4a per memory in Accounts/<uid>/Recordings, only the file name goes in Core Data
struct RecordingFiles {
    let directory: URL

    static func forAccount(_ accountID: String) -> RecordingFiles {
        RecordingFiles(directory: PersistenceController.folder(for: accountID).appending(path: "Recordings", directoryHint: .isDirectory))
    }

    // Before sign in and in tests
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

    // Replaces any older file
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
