import Foundation

// The shape of a trip in Cloud Firestore, and the rules for moving between that and `Trip`.
// Nothing in this file imports Firebase, so all of it is unit tested without a network.
//
//   trips/{tripID}                      TripRecord: name, dates, budget, owner, members' uids
//   trips/{tripID}/members/{id}         MemberRecord
//   trips/{tripID}/activities/{id}      ActivityRecord
//   trips/{tripID}/packing/{id}         PackingRecord
//   trips/{tripID}/expenses/{id}        ExpenseRecord (with its shares inside)
//   trips/{tripID}/payments/{id}        PaymentRecord
//
// Every item is its own document, so two phones changing different expenses of the same trip
// don't overwrite each other. Ids are the same UUIDs used in Core Data.

// MARK: - Collections

/// The lists inside a trip. Each one is a Firestore subcollection of the trip's document.
enum SyncCollection: String, CaseIterable, Comparable {
    case members, activities, packing, expenses, payments

    static func < (lhs: SyncCollection, rhs: SyncCollection) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where an item lives: `trips/{tripID}/{collection}/{id}`.
struct ItemKey: Hashable, Comparable {
    var collection: SyncCollection
    var id: String

    static func < (lhs: ItemKey, rhs: ItemKey) -> Bool {
        (lhs.collection, lhs.id) < (rhs.collection, rhs.id)
    }
}

// MARK: - Records

/// The trip's own document.
struct TripRecord: Codable, Equatable {
    var name: String
    var destination: String
    var startDate: Date
    var endDate: Date
    var budget: Double
    /// Name of the sample cover photo. The user's own cover photo stays on the iPhone.
    var cover: String
    var remindersOn: Bool
    /// The account that created the trip.
    var ownerUID: String
    /// Accounts allowed to read and change the trip. The security rules check this list.
    var memberUIDs: [String]
    /// Deleted trips are kept as a "tombstone" so other devices find out they were deleted.
    var isDeleted: Bool
    var updatedAt: Date
}

/// Items keep their place in the list (`position`), because Firestore returns documents sorted by id.
protocol PositionedRecord {
    var position: Int { get }
}

struct MemberRecord: Codable, Equatable, PositionedRecord {
    var position: Int
    var name: String
    var initials: String
    var colorHex: Int
    /// The account of the person this member is, if they use the app. Decides `isMe` on each phone.
    var userUID: String?
}

struct ActivityRecord: Codable, Equatable, PositionedRecord {
    var position: Int
    var day: Int
    var title: String
    var minutes: Int
    var place: String
    var effort: String
    var isOutdoor: Bool
    var isDone: Bool
}

struct PackingRecord: Codable, Equatable, PositionedRecord {
    var position: Int
    var name: String
    var category: String
    var isPacked: Bool
}

/// Money is saved as whole cents so it adds up exactly, like `ExpenseCalculator`.
struct ExpenseRecord: Codable, Equatable, PositionedRecord {
    var position: Int
    var title: String
    var amountCents: Int
    var category: String
    var paidByID: String
    var splitMethod: String
    var shares: [ShareRecord]
    var date: Date
}

struct ShareRecord: Codable, Equatable {
    var memberID: String
    var amountCents: Int
}

struct PaymentRecord: Codable, Equatable, PositionedRecord {
    var position: Int
    var fromID: String
    var toID: String
    var amountCents: Int
    var date: Date
}

/// Any one item document.
enum ItemRecord: Equatable {
    case member(MemberRecord)
    case activity(ActivityRecord)
    case packing(PackingRecord)
    case expense(ExpenseRecord)
    case payment(PaymentRecord)

    var member: MemberRecord? { if case .member(let record) = self { record } else { nil } }
    var activity: ActivityRecord? { if case .activity(let record) = self { record } else { nil } }
    var packing: PackingRecord? { if case .packing(let record) = self { record } else { nil } }
    var expense: ExpenseRecord? { if case .expense(let record) = self { record } else { nil } }
    var payment: PaymentRecord? { if case .payment(let record) = self { record } else { nil } }
}

// MARK: - Trip ↔ records

enum TripRecords {
    static func cents(_ amount: Double) -> Int { Int((amount * 100).rounded()) }

    static func amount(cents: Int) -> Double { Double(cents) / 100 }

    /// The trip's own document. Until trips can be shared (Increment 6b) the signed-in account
    /// is both the owner and the only member.
    static func header(for trip: Trip, accountID: String, updatedAt: Date, isDeleted: Bool = false) -> TripRecord {
        TripRecord(
            name: trip.name,
            destination: trip.destination,
            startDate: trip.startDate,
            endDate: trip.endDate,
            budget: trip.budget,
            cover: trip.cover.rawValue,
            remindersOn: trip.remindersOn,
            ownerUID: accountID,
            memberUIDs: [accountID],
            isDeleted: isDeleted,
            updatedAt: updatedAt
        )
    }

    /// Every item of the trip, keyed by where it is stored.
    static func items(for trip: Trip, accountID: String) -> [ItemKey: ItemRecord] {
        var items: [ItemKey: ItemRecord] = [:]
        func add(_ collection: SyncCollection, _ id: UUID, _ record: ItemRecord) {
            items[ItemKey(collection: collection, id: id.uuidString)] = record
        }

        for (position, member) in trip.members.enumerated() {
            add(.members, member.id, .member(MemberRecord(
                position: position, name: member.name, initials: member.initials, colorHex: member.colorHex,
                userUID: member.isMe ? accountID : nil)))
        }
        for (position, activity) in trip.activities.enumerated() {
            add(.activities, activity.id, .activity(ActivityRecord(
                position: position, day: activity.day, title: activity.title, minutes: activity.minutes,
                place: activity.place, effort: activity.effort.rawValue, isOutdoor: activity.isOutdoor,
                isDone: activity.isDone)))
        }
        for (position, item) in trip.packing.enumerated() {
            add(.packing, item.id, .packing(PackingRecord(
                position: position, name: item.name, category: item.category, isPacked: item.isPacked)))
        }
        for (position, expense) in trip.expenses.enumerated() {
            add(.expenses, expense.id, .expense(ExpenseRecord(
                position: position, title: expense.title, amountCents: cents(expense.amount),
                category: expense.category.rawValue, paidByID: expense.paidBy.id.uuidString,
                splitMethod: expense.splitMethod.rawValue,
                shares: expense.shares.map { ShareRecord(memberID: $0.member.id.uuidString, amountCents: cents($0.amount)) },
                date: expense.date)))
        }
        for (position, payment) in trip.payments.enumerated() {
            add(.payments, payment.id, .payment(PaymentRecord(
                position: position, fromID: payment.from.id.uuidString, toID: payment.to.id.uuidString,
                amountCents: cents(payment.amount), date: payment.date)))
        }
        return items
    }

    /// Builds the trip back from its documents. `accountID` decides which member is "me" on this phone.
    /// Items that point at a missing member are skipped, the same way Core Data skips damaged rows.
    static func trip(id: UUID, header: TripRecord, lists: [SyncCollection: [String: ItemRecord]],
                     accountID: String) -> Trip {
        let members = sorted(lists[.members], \.member).map { id, record in
            Member(id: id, name: record.name, initials: record.initials, colorHex: record.colorHex,
                   isMe: record.userUID == accountID)
        }
        var membersByID: [String: Member] = [:]
        for member in members { membersByID[member.id.uuidString] = member }

        let activities = sorted(lists[.activities], \.activity).map { id, record in
            Activity(id: id, day: record.day, title: record.title, minutes: record.minutes, place: record.place,
                     effort: Effort(rawValue: record.effort) ?? .low, isOutdoor: record.isOutdoor, isDone: record.isDone)
        }
        let packing = sorted(lists[.packing], \.packing).map { id, record in
            PackingItem(id: id, name: record.name, category: record.category, isPacked: record.isPacked)
        }
        let expenses = sorted(lists[.expenses], \.expense).compactMap { id, record -> Expense? in
            guard let paidBy = membersByID[record.paidByID] else { return nil }
            let shares = record.shares.compactMap { share in
                membersByID[share.memberID].map { ExpenseShare(member: $0, amount: amount(cents: share.amountCents)) }
            }
            return Expense(id: id, title: record.title, amount: amount(cents: record.amountCents),
                           category: ExpenseCategory(rawValue: record.category) ?? .activities, paidBy: paidBy,
                           splitMethod: SplitMethod(rawValue: record.splitMethod) ?? .equal, shares: shares,
                           date: record.date)
        }
        let payments = sorted(lists[.payments], \.payment).compactMap { id, record -> Payment? in
            guard let from = membersByID[record.fromID], let to = membersByID[record.toID] else { return nil }
            return Payment(id: id, from: from, to: to, amount: amount(cents: record.amountCents), date: record.date)
        }

        return Trip(
            id: id,
            name: header.name,
            destination: header.destination,
            startDate: header.startDate,
            endDate: header.endDate,
            budget: header.budget,
            members: members,
            cover: SamplePhoto(rawValue: header.cover) ?? .cover(for: header.destination),
            remindersOn: header.remindersOn,
            activities: activities,
            packing: packing,
            expenses: expenses,
            payments: payments
        )
    }

    /// The records of one kind in list order, with their ids.
    private static func sorted<Record: PositionedRecord>(
        _ items: [String: ItemRecord]?, _ extract: KeyPath<ItemRecord, Record?>
    ) -> [(UUID, Record)] {
        (items ?? [:])
            .compactMap { key, item -> (UUID, Record)? in
                guard let id = UUID(uuidString: key), let record = item[keyPath: extract] else { return nil }
                return (id, record)
            }
            .sorted { $0.1.position < $1.1.position }
    }
}

// MARK: - Changes to upload

/// One document write.
enum SyncWrite: Equatable {
    case setTrip(UUID, TripRecord)
    case setItem(tripID: UUID, ItemKey, ItemRecord)
    case deleteItem(tripID: UUID, ItemKey)
}

/// Works out the smallest set of writes that makes Firestore match a change made on this iPhone.
enum TripChangeSet {
    /// `old` is nil for a new trip; `new` is nil for a deleted one.
    /// Only documents that actually changed are written: ticking one packing item is one write.
    /// The cover photo id is not part of any record, so changing only the photo writes nothing.
    static func writes(from old: Trip?, to new: Trip?, accountID: String, now: Date) -> [SyncWrite] {
        guard let new else {
            guard let old else { return [] }
            // Keep a tombstone for other devices, and remove the trip's items.
            let tombstone = TripRecords.header(for: old, accountID: accountID, updatedAt: now, isDeleted: true)
            let items = TripRecords.items(for: old, accountID: accountID).keys.sorted()
            return [.setTrip(old.id, tombstone)] + items.map { .deleteItem(tripID: old.id, $0) }
        }

        var writes: [SyncWrite] = []
        let newHeader = TripRecords.header(for: new, accountID: accountID, updatedAt: now)
        let oldHeader = old.map { TripRecords.header(for: $0, accountID: accountID, updatedAt: now) }
        if oldHeader != newHeader {
            writes.append(.setTrip(new.id, newHeader))
        }

        let oldItems = old.map { TripRecords.items(for: $0, accountID: accountID) } ?? [:]
        let newItems = TripRecords.items(for: new, accountID: accountID)
        for key in newItems.keys.sorted() {
            if let record = newItems[key], record != oldItems[key] {
                writes.append(.setItem(tripID: new.id, key, record))
            }
        }
        for key in oldItems.keys.sorted() where newItems[key] == nil {
            writes.append(.deleteItem(tripID: new.id, key))
        }
        return writes
    }
}

// MARK: - What the cloud has

/// Firestore's current copy of one trip, put together from the trip's document and its five lists,
/// which arrive from six separate listeners.
struct RemoteTripMirror {
    enum Part: Hashable {
        case header
        case list(SyncCollection)
    }

    private(set) var header: TripRecord?
    private(set) var lists: [SyncCollection: [String: ItemRecord]] = [:]
    private var received: Set<Part> = []
    private var pending: Set<Part> = []

    /// True while Firestore is still showing writes from this iPhone that the server hasn't confirmed.
    /// Those changes are already in Core Data, so nothing is applied until the server answers.
    var hasPendingWrites: Bool { !pending.isEmpty }

    /// True once the trip's document and all five lists have arrived at least once.
    var hasEveryPart: Bool { received.count == SyncCollection.allCases.count + 1 }

    mutating func receiveHeader(_ record: TripRecord, hasPendingWrites: Bool) {
        header = record
        mark(.header, hasPendingWrites: hasPendingWrites)
    }

    mutating func receive(_ records: [String: ItemRecord], in collection: SyncCollection, hasPendingWrites: Bool) {
        lists[collection] = records
        mark(.list(collection), hasPendingWrites: hasPendingWrites)
    }

    /// The trip as the cloud has it, or nil while parts are missing or if it was deleted.
    /// Without waiting for every part, a half-arrived trip (say, with no expenses yet) would
    /// overwrite the full copy on the iPhone.
    func trip(id: UUID, accountID: String) -> Trip? {
        guard hasEveryPart, let header, !header.isDeleted else { return nil }
        return TripRecords.trip(id: id, header: header, lists: lists, accountID: accountID)
    }

    private mutating func mark(_ part: Part, hasPendingWrites: Bool) {
        received.insert(part)
        if hasPendingWrites {
            pending.insert(part)
        } else {
            pending.remove(part)
        }
    }
}
