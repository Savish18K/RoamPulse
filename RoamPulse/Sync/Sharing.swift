import Foundation

// Sharing a trip with friends (Increment 6b).
//
// 1. A member taps Invite Friends. The app saves `invites/{code}` in Firestore with the trip's id,
//    name, dates and members, and shows the code to send (Messages, WhatsApp…).
// 2. The friend taps Join Trip and enters the code. The app reads the invite and asks which member
//    they are (or adds them as a new one).
// 3. The friend's app adds their account to the trip's `memberUIDs`. The security rules only allow
//    that with a valid, unexpired invite for that trip. The trip then appears on the friend's phone
//    through the normal sync listener, and both phones see each other's changes.
// Nothing in this file imports Firebase, so it is unit tested.

/// An invitation to join one trip.
struct TripInvite: Equatable, Identifiable {
    var code: String
    var tripID: UUID
    var tripName: String
    var destination: String
    var startDate: Date
    var endDate: Date
    var ownerName: String
    /// The account that made the invite.
    var createdBy: String
    var expiresAt: Date
    /// The trip's members when the invite was made, so the friend can say which one they are.
    var members: [InviteMember]

    var id: String { code }

    /// Members who aren't linked to an account yet.
    var availableMembers: [InviteMember] { members.filter { !$0.isTaken } }

    func isExpired(at now: Date) -> Bool { expiresAt <= now }
}

/// A trip member as listed in an invite.
struct InviteMember: Codable, Equatable, Identifiable {
    /// The member's UUID string, the same id as their Firestore document.
    var id: String
    var name: String
    var initials: String
    var colorHex: Int
    /// Already linked to someone's account.
    var isTaken: Bool
}

/// The invite as stored in Firestore at `invites/{code}`.
struct InviteRecord: Codable, Equatable {
    var tripID: String
    var tripName: String
    var destination: String
    var startDate: Date
    var endDate: Date
    var ownerName: String
    var createdBy: String
    var expiresAt: Date
    var members: [InviteMember]

    init(_ invite: TripInvite) {
        tripID = invite.tripID.uuidString
        tripName = invite.tripName
        destination = invite.destination
        startDate = invite.startDate
        endDate = invite.endDate
        ownerName = invite.ownerName
        createdBy = invite.createdBy
        expiresAt = invite.expiresAt
        members = invite.members
    }

    func invite(code: String) -> TripInvite? {
        guard let id = UUID(uuidString: tripID) else { return nil }
        return TripInvite(code: code, tripID: id, tripName: tripName, destination: destination, startDate: startDate,
                          endDate: endDate, ownerName: ownerName, createdBy: createdBy, expiresAt: expiresAt,
                          members: members)
    }
}

enum InviteCode {
    /// No 0/O, 1/I/L or 5/S, so a code read out loud or typed from a screenshot isn't misread.
    static let alphabet = Array("ABCDEFGHJKMNPQRTUVWXYZ2346789")
    static let length = 8
    /// How long a code works.
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    /// A random code, e.g. "K7QM-2XHA" without the dash. 29⁸ ≈ 500 billion codes, so they can't be guessed.
    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    static func generate<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String {
        String((0..<length).map { _ in alphabet.randomElement(using: &generator) ?? "A" })
    }

    /// Cleans up what the friend typed ("k7qm-2xha " → "K7QM2XHA"). nil if it can't be a code.
    static func normalized(_ input: String) -> String? {
        let code = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard code.count == length, code.allSatisfy(alphabet.contains) else { return nil }
        return code
    }

    /// "K7QM2XHA" → "K7QM-2XHA", easier to read.
    static func formatted(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }

    /// The invite for a trip, as the person sharing it sees it.
    static func makeInvite(for trip: Trip, code: String, ownerName: String, accountID: String, now: Date) -> TripInvite {
        TripInvite(
            code: code,
            tripID: trip.id,
            tripName: trip.name,
            destination: trip.destination,
            startDate: trip.startDate,
            endDate: trip.endDate,
            ownerName: ownerName,
            createdBy: accountID,
            expiresAt: now.addingTimeInterval(lifetime),
            members: trip.members.map { member in
                InviteMember(id: member.id.uuidString, name: member.name, initials: member.initials,
                             colorHex: member.colorHex, isTaken: member.userUID != nil || member.isMe)
            }
        )
    }

    /// The text sent with the share sheet.
    static func shareMessage(for invite: TripInvite) -> String {
        "Join my trip “\(invite.tripName)” on RoamPulse! Open Trips → Join Trip and enter the code "
            + "\(formatted(invite.code)). It works until \(invite.expiresAt.text("d MMM"))."
    }

    /// The document for someone joining as a new member (they weren't on the trip's list).
    static func newMember(name: String, initials: String, accountID: String, existingCount: Int) -> (id: UUID, record: MemberRecord) {
        let record = MemberRecord(position: existingCount, name: name, initials: initials,
                                  colorHex: Member.palette[existingCount % Member.palette.count], userUID: accountID)
        return (UUID(), record)
    }
}

enum SharingError: LocalizedError, Equatable {
    case notSignedIn
    /// The server didn't answer in time. Sharing needs a connection, unlike normal editing.
    case offline
    case inviteNotFound
    case inviteExpired
    case alreadyMember
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Sign in to share trips."
        case .offline: "This needs an internet connection. Try again when you're online."
        case .inviteNotFound: "There's no trip with that code. Check it and try again."
        case .inviteExpired: "That code has expired. Ask your friend for a new one."
        case .alreadyMember: "You're already on this trip."
        case .unavailable: "Sharing isn't available, because cloud sync isn't set up."
        }
    }
}

/// Runs `operation`, but gives up with `SharingError.offline` after `seconds`.
///
/// Offline, a Firestore write never fails: it waits in the cache until the phone reconnects. That is
/// right for normal edits, but joining a trip or deleting an account must finish now, so they use this.
/// (A task group can't be used: it would wait for the stuck write before returning.)
func withTimeout<T>(seconds: Double = 15, _ operation: @escaping () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let gate = ResumeOnce()
        Task {
            do {
                let value = try await operation()
                gate.run { continuation.resume(returning: value) }
            } catch {
                gate.run { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            gate.run { continuation.resume(throwing: SharingError.offline) }
        }
    }
}

/// Makes sure a continuation is resumed only once, whichever task finishes first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
