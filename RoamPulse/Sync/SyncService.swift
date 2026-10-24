import SwiftUI

// Cloud sync protocol, Firestore in the app, fakes in tests
@MainActor
protocol SyncService: AnyObject {
    var status: SyncStatus { get }
    func start(accountID: String, store: TripStore)
    // Doesn't delete anything
    func stop()
    // old is nil for a new trip, new is nil for a deleted one
    func tripDidChange(from old: Trip?, to new: Trip?)

    func createInvite(for trip: Trip, ownerName: String) async throws -> TripInvite
    func findInvite(code: String) async throws -> TripInvite
    // memberID nil means join as a new member
    func joinTrip(_ invite: TripInvite, as memberID: String?, name: String, initials: String) async throws
    // Works offline
    func leaveTrip(_ trip: Trip)

    // Own trips become tombstones, shared trips are left, invites removed
    func deleteCloudData(for trips: [Trip]) async throws
}

// Shown on Profile
enum SyncStatus: Equatable {
    case off
    case connecting
    case upToDate
    case uploading
    // Changes upload later
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

// For previews and when Firebase isn't set up
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
