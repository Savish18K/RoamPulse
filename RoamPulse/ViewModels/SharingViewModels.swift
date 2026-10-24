import Foundation
import Observation

@MainActor
@Observable
final class ShareTripViewModel {
    enum State: Equatable {
        case creating
        case ready(TripInvite)
        case failed(String)
    }

    let tripID: UUID
    private let store: TripStore
    private let sync: SyncService
    private(set) var state: State = .creating

    init(tripID: UUID, store: TripStore, sync: SyncService) {
        self.tripID = tripID
        self.store = store
        self.sync = sync
    }

    var trip: Trip? { store.trip(tripID) }

    var joinedMembers: [Member] { trip?.members.filter { $0.userUID != nil } ?? [] }

    var invite: TripInvite? {
        if case .ready(let invite) = state { invite } else { nil }
    }

    var formattedCode: String { invite.map { InviteCode.formatted($0.code) } ?? "" }

    var shareMessage: String { invite.map(InviteCode.shareMessage) ?? "" }

    var expiryText: String {
        guard let invite else { return "" }
        return "Works until \(invite.expiresAt.text("EEE d MMM")) for anyone you send it to."
    }

    func createInvite() async {
        guard let trip else { return }
        state = .creating
        do {
            state = .ready(try await sync.createInvite(for: trip, ownerName: store.profile.fullName))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

@MainActor
@Observable
final class JoinTripViewModel {
    enum Step: Equatable {
        case enterCode
        case chooseMember(TripInvite)
        case joined(tripName: String)
    }

    var code = ""
    private(set) var step: Step = .enterCode
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    // nil = add me as a new member
    var selectedMemberID: String?

    private let store: TripStore
    private let sync: SyncService

    init(store: TripStore, sync: SyncService) {
        self.store = store
        self.sync = sync
    }

    var codeLooksValid: Bool { InviteCode.normalized(code) != nil }

    var invite: TripInvite? {
        if case .chooseMember(let invite) = step { invite } else { nil }
    }

    // Pre-select the member with my name
    private func suggestedMember(in invite: TripInvite) -> String? {
        let myName = store.me.name.lowercased()
        return invite.availableMembers.first { $0.name.lowercased() == myName }?.id
    }

    func findTrip() async {
        errorMessage = nil
        guard codeLooksValid else {
            errorMessage = "Codes are 8 letters and numbers, like K7QM-2XHA."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let invite = try await sync.findInvite(code: code)
            selectedMemberID = suggestedMember(in: invite)
            step = .chooseMember(invite)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func join() async {
        guard let invite else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await sync.joinTrip(invite, as: selectedMemberID, name: store.me.name, initials: store.me.initials)
            step = .joined(tripName: invite.tripName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startOver() {
        step = .enterCode
        errorMessage = nil
        selectedMemberID = nil
    }
}
