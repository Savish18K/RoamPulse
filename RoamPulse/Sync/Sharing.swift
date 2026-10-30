import Foundation

// Trip sharing with invite codes. The friend enters the code and gets added to memberUIDs (checked by the rules)

struct TripInvite: Equatable, Identifiable {
    var code: String
    var tripID: UUID
    var tripName: String
    var destination: String
    var startDate: Date
    var endDate: Date
    var ownerName: String
    var createdBy: String
    var expiresAt: Date
    // So the friend can pick who they are
    var members: [InviteMember]

    var id: String { code }

    var availableMembers: [InviteMember] { members.filter { !$0.isTaken } }

    func isExpired(at now: Date) -> Bool { expiresAt <= now }
}

struct InviteMember: Codable, Equatable, Identifiable {
    // Same id as the Firestore doc
    var id: String
    var name: String
    var initials: String
    var colorHex: Int
    // Already linked to an account
    var isTaken: Bool
}

// Stored at invites/{code}
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
    // No 0/O, 1/I/L or 5/S so codes aren't misread
    static let alphabet = Array("ABCDEFGHJKMNPQRTUVWXYZ2346789")
    static let length = 8
    // 7 days
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    // 8 characters, too many combinations to guess
    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    static func generate<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String {
        String((0..<length).map { _ in alphabet.randomElement(using: &generator) ?? "A" })
    }

    // e.g. "k7qm-2xha " -> "K7QM2XHA", nil if invalid
    static func normalized(_ input: String) -> String? {
        let code = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard code.count == length, code.allSatisfy(alphabet.contains) else { return nil }
        return code
    }

    // "K7QM2XHA" -> "K7QM-2XHA"
    static func formatted(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }

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

    static func shareMessage(for invite: TripInvite) -> String {
        "Join my trip “\(invite.tripName)” on RoamPulse! Open Trips → Join Trip and enter the code "
            + "\(formatted(invite.code)). It works until \(invite.expiresAt.text("d MMM"))."
    }

    // For someone not already on the members list
    static func newMember(name: String, initials: String, accountID: String, existingCount: Int) -> (id: UUID, record: MemberRecord) {
        let record = MemberRecord(position: existingCount, name: name, initials: initials,
                                  colorHex: Member.palette[existingCount % Member.palette.count], userUID: accountID)
        return (UUID(), record)
    }
}

enum SharingError: LocalizedError, Equatable {
    case notSignedIn
    // Sharing needs a connection
    case offline
    case inviteNotFound
    case inviteExpired
    case alreadyMember
    case unavailable
    // Firestore said no: the rules in the Firebase console aren't the ones in firestore.rules
    case refused

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Sign in to share trips."
        case .offline: "This needs an internet connection. Try again when you're online."
        case .inviteNotFound: "There's no trip with that code. Check it and try again."
        case .inviteExpired: "That code has expired. Ask your friend for a new one."
        case .alreadyMember: "You're already on this trip."
        case .unavailable: "Sharing isn't available, because cloud sync isn't set up."
        case .refused: "The cloud refused this. Publish the rules in firestore.rules in the Firebase console, then try again."
        }
    }
}

// Offline Firestore writes just wait forever, so joining/deleting need a timeout
// (a task group would still wait for the stuck write)
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

// Only resume once, whichever finishes first
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
