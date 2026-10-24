import Foundation

// Firestore layout for a trip, each item is its own document under trips/{tripID}/...
// so two phones editing different items don't overwrite each other

// Subcollections of a trip
enum SyncCollection: String, CaseIterable, Comparable {
    case members, activities, packing, expenses, payments

    static func < (lhs: SyncCollection, rhs: SyncCollection) -> Bool { lhs.rawValue < rhs.rawValue }
}

// trips/{tripID}/{collection}/{id}
struct ItemKey: Hashable, Comparable {
    var collection: SyncCollection
    var id: String

    static func < (lhs: ItemKey, rhs: ItemKey) -> Bool {
        (lhs.collection, lhs.id) < (rhs.collection, rhs.id)
    }
}

struct TripRecord: Codable, Equatable {
    var name: String
    var destination: String
    var startDate: Date
    var endDate: Date
    var budget: Double
    // Sample cover name, custom covers stay on the phone
    var cover: String
    var remindersOn: Bool
    var ownerUID: String
    // Checked by the security rules
    var memberUIDs: [String]
    // Kept as a tombstone so other devices know it was deleted
    var isDeleted: Bool
    var updatedAt: Date
    // Optional for older trips
    var latitude: Double?
    var longitude: Double?
}

// Firestore sorts by id so we store the order ourselves
protocol PositionedRecord {
    var position: Int { get }
}

struct MemberRecord: Codable, Equatable, PositionedRecord {
    var position: Int
    var name: String
    var initials: String
    var colorHex: Int
    // Used to work out isMe on each phone
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
    var latitude: Double? = nil
    var longitude: Double? = nil
}

struct PackingRecord: Codable, Equatable, PositionedRecord {
    var position: Int
    var name: String
    var category: String
    var isPacked: Bool
}

// Stored in cents
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

enum TripRecords {
    static func cents(_ amount: Double) -> Int { Int((amount * 100).rounded()) }

    static func amount(cents: Int) -> Double { Double(cents) / 100 }

    // Trips without an owner get the signed in account
    static func header(for trip: Trip, accountID: String, updatedAt: Date, isDeleted: Bool = false) -> TripRecord {
        let owner = trip.ownerUID ?? accountID
        var members = trip.memberUIDs.isEmpty ? [owner] : trip.memberUIDs
        if !members.contains(owner) {
            members.insert(owner, at: 0)
        }
        return TripRecord(
            name: trip.name,
            destination: trip.destination,
            startDate: trip.startDate,
            endDate: trip.endDate,
            budget: trip.budget,
            cover: trip.cover.rawValue,
            remindersOn: trip.remindersOn,
            ownerUID: owner,
            memberUIDs: members,
            isDeleted: isDeleted,
            updatedAt: updatedAt,
            latitude: trip.latitude,
            longitude: trip.longitude
        )
    }

    static func items(for trip: Trip, accountID: String) -> [ItemKey: ItemRecord] {
        var items: [ItemKey: ItemRecord] = [:]
        func add(_ collection: SyncCollection, _ id: UUID, _ record: ItemRecord) {
            items[ItemKey(collection: collection, id: id.uuidString)] = record
        }

        for (position, member) in trip.members.enumerated() {
            add(.members, member.id, .member(MemberRecord(
                position: position, name: member.name, initials: member.initials, colorHex: member.colorHex,
                userUID: member.userUID ?? (member.isMe ? accountID : nil))))
        }
        for (position, activity) in trip.activities.enumerated() {
            add(.activities, activity.id, .activity(ActivityRecord(
                position: position, day: activity.day, title: activity.title, minutes: activity.minutes,
                place: activity.place, effort: activity.effort.rawValue, isOutdoor: activity.isOutdoor,
                isDone: activity.isDone, latitude: activity.latitude, longitude: activity.longitude)))
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

    // Items pointing at a missing member are skipped
    static func trip(id: UUID, header: TripRecord, lists: [SyncCollection: [String: ItemRecord]],
                     accountID: String) -> Trip {
        let members = sorted(lists[.members], \.member).map { id, record in
            Member(id: id, name: record.name, initials: record.initials, colorHex: record.colorHex,
                   isMe: record.userUID == accountID, userUID: record.userUID)
        }
        var membersByID: [String: Member] = [:]
        for member in members { membersByID[member.id.uuidString] = member }

        let activities = sorted(lists[.activities], \.activity).map { id, record in
            Activity(id: id, day: record.day, title: record.title, minutes: record.minutes, place: record.place,
                     effort: Effort(rawValue: record.effort) ?? .low, isOutdoor: record.isOutdoor, isDone: record.isDone,
                     latitude: record.latitude, longitude: record.longitude)
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
            payments: payments,
            ownerUID: header.ownerUID,
            memberUIDs: header.memberUIDs,
            latitude: header.latitude,
            longitude: header.longitude
        )
    }

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

enum SyncWrite: Equatable {
    // Full write including owner and members
    case createTrip(UUID, TripRecord)
    // Only writes contentFields, so an edit can't remove a member that just joined
    case updateTrip(UUID, TripRecord)
    case setItem(tripID: UUID, ItemKey, ItemRecord)
    case deleteItem(tripID: UUID, ItemKey)
}

extension TripRecord {
    // Everything except ownerUID and memberUIDs
    static let contentFields = ["name", "destination", "startDate", "endDate", "budget", "cover", "remindersOn",
                                "isDeleted", "updatedAt", "latitude", "longitude"]

    var content: TripRecord {
        var record = self
        record.ownerUID = ""
        record.memberUIDs = []
        return record
    }

    // Clears the name etc. so no personal data is left
    static func tombstone(owner: String, members: [String], at date: Date) -> TripRecord {
        TripRecord(name: "", destination: "", startDate: date, endDate: date, budget: 0, cover: "",
                   remindersOn: false, ownerUID: owner, memberUIDs: members, isDeleted: true, updatedAt: date)
    }
}

// Works out the minimum Firestore writes for a change
enum TripChangeSet {
    // old is nil for a new trip, new is nil for a deleted one. Only changed docs are written
    static func writes(from old: Trip?, to new: Trip?, accountID: String, now: Date) -> [SyncWrite] {
        guard let new else {
            guard let old else { return [] }
            let header = TripRecords.header(for: old, accountID: accountID, updatedAt: now)
            let tombstone = TripRecord.tombstone(owner: header.ownerUID, members: header.memberUIDs, at: now)
            let items = TripRecords.items(for: old, accountID: accountID).keys.sorted()
            return [.updateTrip(old.id, tombstone)] + items.map { .deleteItem(tripID: old.id, $0) }
        }

        var writes: [SyncWrite] = []
        let newHeader = TripRecords.header(for: new, accountID: accountID, updatedAt: now)
        if let old {
            let oldHeader = TripRecords.header(for: old, accountID: accountID, updatedAt: now)
            if oldHeader.content != newHeader.content {
                writes.append(.updateTrip(new.id, newHeader))
            }
        } else {
            writes.append(.createTrip(new.id, newHeader))
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

// Puts a trip back together from its 6 listeners
struct RemoteTripMirror {
    enum Part: Hashable {
        case header
        case list(SyncCollection)
    }

    private(set) var header: TripRecord?
    private(set) var lists: [SyncCollection: [String: ItemRecord]] = [:]
    private var received: Set<Part> = []
    private var pending: Set<Part> = []

    // Wait until the server confirms our own writes
    var hasPendingWrites: Bool { !pending.isEmpty }

    // Trip doc + all 5 lists received
    var hasEveryPart: Bool { received.count == SyncCollection.allCases.count + 1 }

    mutating func receiveHeader(_ record: TripRecord, hasPendingWrites: Bool) {
        header = record
        mark(.header, hasPendingWrites: hasPendingWrites)
    }

    mutating func receive(_ records: [String: ItemRecord], in collection: SyncCollection, hasPendingWrites: Bool) {
        lists[collection] = records
        mark(.list(collection), hasPendingWrites: hasPendingWrites)
    }

    // nil until every part is here, otherwise a half loaded trip would overwrite the local one
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
