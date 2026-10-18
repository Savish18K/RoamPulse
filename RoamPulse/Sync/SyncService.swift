import SwiftUI

/// Keeps the signed-in account's trips in the cloud in step with this iPhone.
///
/// The app uses `FirestoreSyncService`; tests use a fake that records changes, and previews
/// (or an app without Firebase set up) use `NoSyncService`.
@MainActor
protocol SyncService: AnyObject {
    var status: SyncStatus { get }
    /// Starts mirroring the account's trips between `store` and the cloud.
    func start(accountID: String, store: TripStore)
    /// Stops listening, e.g. after signing out. Nothing is deleted.
    func stop()
    /// Called by `TripStore` after a change was saved on this iPhone.
    /// `old` is nil for a new trip and `new` is nil for a deleted one.
    func tripDidChange(from old: Trip?, to new: Trip?)
}

/// What the Profile screen shows about syncing.
enum SyncStatus: Equatable {
    case off
    case connecting
    case upToDate
    case uploading
    /// No connection. Changes are saved on the iPhone and upload later.
    case offline
    case failed(String)

    var title: String {
        switch self {
        case .off: "Not syncing"
        case .connecting: "Connecting…"
        case .upToDate: "Up to date"
        case .uploading: "Uploading changes…"
        case .offline: "Offline – changes will upload later"
        case .failed: "Sync problem"
        }
    }

    var icon: String {
        switch self {
        case .off: "icloud.slash"
        case .connecting, .uploading: "arrow.triangle.2.circlepath.icloud"
        case .upToDate: "checkmark.icloud"
        case .offline: "icloud.slash"
        case .failed: "exclamationmark.icloud"
        }
    }

    var color: Color {
        switch self {
        case .upToDate: .green
        case .connecting, .uploading: .blue
        case .off, .offline: .secondary
        case .failed: .red
        }
    }

    var detail: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Does nothing. Used by previews, and when Firebase isn't set up.
@MainActor
final class NoSyncService: SyncService {
    var status: SyncStatus { .off }
    func start(accountID: String, store: TripStore) {}
    func stop() {}
    func tripDidChange(from old: Trip?, to new: Trip?) {}
}
