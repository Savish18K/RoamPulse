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

    /// Saves a new invite code for the trip and returns it.
    func createInvite(for trip: Trip, ownerName: String) async throws -> TripInvite
    /// Looks up a code a friend typed in.
    func findInvite(code: String) async throws -> TripInvite
    /// Adds this account to the invite's trip, as the existing member `memberID`,
    /// or as a new member called `name` when `memberID` is nil.
    func joinTrip(_ invite: TripInvite, as memberID: String?, name: String, initials: String) async throws
    /// Removes this account from someone else's trip. Works offline (uploaded later).
    func leaveTrip(_ trip: Trip)

    /// Deletes the account's data from the cloud before the account itself is deleted:
    /// its own trips become empty tombstones, shared trips are left, and its invites are removed.
    func deleteCloudData(for trips: [Trip]) async throws
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
    func createInvite(for trip: Trip, ownerName: String) async throws -> TripInvite { throw SharingError.unavailable }
    func findInvite(code: String) async throws -> TripInvite { throw SharingError.unavailable }
    func joinTrip(_ invite: TripInvite, as memberID: String?, name: String, initials: String) async throws {
        throw SharingError.unavailable
    }
    func leaveTrip(_ trip: Trip) {}
    func deleteCloudData(for trips: [Trip]) async throws {}
}
