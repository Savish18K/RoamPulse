import CoreData

// Converts between the plain structs and the Core Data entities, all Core Data code is in here
final class CoreDataTripRepository: TripRepository {
    private let context: NSManagedObjectContext
    private let persistence: PersistenceController?

    init(context: NSManagedObjectContext, persistence: PersistenceController? = nil) {
        self.context = context
        self.persistence = persistence
    }

    convenience init(accountID: String) throws {
        let persistence = PersistenceController(accountID: accountID)
        if let error = persistence.loadError {
            throw error
        }
        self.init(context: persistence.container.viewContext, persistence: persistence)
        try? deleteUnlinkedImages()
    }

    func loadTrips() throws -> [Trip] {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
        return try context.fetch(request).compactMap(Trip.init(entity:))
    }

    func save(_ trip: Trip) throws {
        let entity = try find(TripEntity.self, id: trip.id) ?? TripEntity(context: context)
        if entity.createdAt == nil {
            entity.createdAt = Date()
        }
        entity.update(from: trip, context: context)
        try linkCoverImage(trip.coverImageID, to: entity)
        try commit()
    }

    func deleteTrip(id: UUID) throws {
        guard let entity = try find(TripEntity.self, id: id) else { return }
        // Cascade delete rule removes everything belonging to the trip
        context.delete(entity)
        try commit()
    }

    func loadMemories() throws -> [Memory] {
        let request: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request).compactMap(Memory.init(entity:))
    }

    func save(_ memory: Memory) throws {
        guard let trip = try find(TripEntity.self, id: memory.tripID) else {
            throw RepositoryError.tripNotFound
        }
        let entity = try find(MemoryEntity.self, id: memory.id) ?? MemoryEntity(context: context)
        entity.update(from: memory, trip: trip, context: context)
        try syncPhotos(memory.photos, of: entity)
        try commit()
    }

    // Keeps existing photo rows, deletes the removed ones (and their images)
    private func syncPhotos(_ photos: [MemoryPhoto], of memory: MemoryEntity) throws {
        var unused = memory.photos.rows(of: PhotoEntity.self)
        var rows: [PhotoEntity] = []
        for photo in photos {
            if let index = unused.firstIndex(where: { Self.row($0, shows: photo) }) {
                rows.append(unused.remove(at: index))
                continue
            }
            let row = PhotoEntity(context: context)
            row.id = UUID()
            row.createdAt = memory.date
            switch photo {
            case .sample(let sample):
                row.assetName = sample.rawValue
            case .stored(let imageID):
                guard let image = try find(StoredImageEntity.self, id: imageID) else {
                    context.delete(row) // the image was never saved, so there is nothing to show
                    continue
                }
                row.image = image
            }
            rows.append(row)
        }
        unused.forEach(context.delete)
        memory.photos = NSOrderedSet(array: rows)
    }

    private static func row(_ row: PhotoEntity, shows photo: MemoryPhoto) -> Bool {
        switch photo {
        case .sample(let sample): row.image == nil && row.assetName == sample.rawValue
        case .stored(let imageID): row.image?.id == imageID
        }
    }

    func deleteMemory(id: UUID) throws {
        guard let entity = try find(MemoryEntity.self, id: id) else { return }
        context.delete(entity)
        try commit()
    }

    func deleteEverything() throws {
        let trips: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        for trip in try context.fetch(trips) {
            context.delete(trip)
        }
        try commit()
    }

    // Images use "Allows External Storage" so big ones are saved as separate files

    func saveImage(_ image: PreparedImage) throws -> UUID {
        let entity = StoredImageEntity(context: context)
        let id = UUID()
        entity.id = id
        entity.imageData = image.data
        entity.thumbnailData = image.thumbnail
        entity.pixelWidth = Int32(clamping: image.pixelWidth)
        entity.pixelHeight = Int32(clamping: image.pixelHeight)
        entity.createdAt = Date()
        try commit()
        return id
    }

    func imageData(id: UUID, thumbnail: Bool) throws -> Data? {
        guard let entity = try find(StoredImageEntity.self, id: id) else { return nil }
        return thumbnail ? entity.thumbnailData : entity.imageData
    }

    func deleteImage(id: UUID) throws {
        guard let entity = try find(StoredImageEntity.self, id: id) else { return }
        context.delete(entity)
        try commit()
    }

    func saveForecast(_ forecast: CachedForecast, for tripID: UUID) throws {
        guard let trip = try find(TripEntity.self, id: tripID) else { throw RepositoryError.tripNotFound }
        let cache = trip.forecast ?? ForecastCacheEntity(context: context)
        cache.payload = forecast.payload
        cache.location = forecast.location
        cache.fetchedAt = forecast.fetchedAt
        trip.forecast = cache
        try commit()
    }

    func cachedForecast(for tripID: UUID) throws -> CachedForecast? {
        guard let cache = try find(TripEntity.self, id: tripID)?.forecast,
              let payload = cache.payload, let location = cache.location, let fetchedAt = cache.fetchedAt else {
            return nil
        }
        return CachedForecast(payload: payload, location: location, fetchedAt: fetchedAt)
    }

    // Old cover gets deleted when it's replaced
    private func linkCoverImage(_ imageID: UUID?, to trip: TripEntity) throws {
        guard trip.coverImage?.id != imageID else { return }
        if let old = trip.coverImage {
            context.delete(old)
        }
        trip.coverImage = try imageID.flatMap { try find(StoredImageEntity.self, id: $0) }
    }

    // Clean up images that never got linked (e.g. app closed mid save)
    private func deleteUnlinkedImages() throws {
        let request: NSFetchRequest<StoredImageEntity> = StoredImageEntity.fetchRequest()
        request.predicate = NSPredicate(format: "trip == nil AND photo == nil")
        for image in try context.fetch(request) {
            context.delete(image)
        }
        try commit()
    }

    private func find<Entity: NSManagedObject>(_ type: Entity.Type, id: UUID) throws -> Entity? {
        let request = NSFetchRequest<Entity>(entityName: String(describing: type))
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    // Roll back on failure so the database and UI stay the same
    private func commit() throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

// Updates existing rows, inserts new ones and deletes removed ones, keeping the order
private func sync<Item: Identifiable, Row: NSManagedObject>(
    _ items: [Item],
    rows existing: [Row],
    id: (Row) -> UUID?,
    context: NSManagedObjectContext,
    makeRow: () -> Row,
    update: (Row, Item) -> Void
) -> [Row] where Item.ID == UUID {
    var unused: [UUID: Row] = [:]
    for row in existing {
        if let rowID = id(row), unused[rowID] == nil {
            unused[rowID] = row
        } else {
            context.delete(row) // a duplicate or a row without an id
        }
    }
    let rows = items.map { item in
        let row = unused.removeValue(forKey: item.id) ?? makeRow()
        update(row, item)
        return row
    }
    for row in unused.values {
        context.delete(row)
    }
    return rows
}

private extension TripEntity {
    func update(from trip: Trip, context: NSManagedObjectContext) {
        id = trip.id
        name = trip.name
        destination = trip.destination
        startDate = trip.startDate
        endDate = trip.endDate
        budget = trip.budget
        coverName = trip.cover.rawValue
        remindersOn = trip.remindersOn
        ownerUID = trip.ownerUID
        memberUIDs = trip.memberUIDs
        latitude = trip.latitude.map { NSNumber(value: $0) }
        longitude = trip.longitude.map { NSNumber(value: $0) }

        let memberRows = sync(trip.members, rows: members.rows(of: MemberEntity.self), id: \.id, context: context,
                              makeRow: { MemberEntity(context: context) },
                              update: { row, member in row.update(from: member) })
        members = NSOrderedSet(array: memberRows)

        var memberRowsByID: [UUID: MemberEntity] = [:]
        for row in memberRows {
            if let rowID = row.id { memberRowsByID[rowID] = row }
        }

        activities = NSOrderedSet(array: sync(
            trip.activities, rows: activities.rows(of: ActivityEntity.self), id: \.id, context: context,
            makeRow: { ActivityEntity(context: context) },
            update: { row, activity in row.update(from: activity) }))

        packingItems = NSOrderedSet(array: sync(
            trip.packing, rows: packingItems.rows(of: PackingItemEntity.self), id: \.id, context: context,
            makeRow: { PackingItemEntity(context: context) },
            update: { row, item in row.update(from: item) }))

        expenses = NSOrderedSet(array: sync(
            trip.expenses, rows: expenses.rows(of: ExpenseEntity.self), id: \.id, context: context,
            makeRow: { ExpenseEntity(context: context) },
            update: { row, expense in row.update(from: expense, members: memberRowsByID, context: context) }))

        payments = NSOrderedSet(array: sync(
            trip.payments, rows: payments.rows(of: PaymentEntity.self), id: \.id, context: context,
            makeRow: { PaymentEntity(context: context) },
            update: { row, payment in row.update(from: payment, members: memberRowsByID) }))
    }
}

private extension MemberEntity {
    func update(from member: Member) {
        id = member.id
        name = member.name
        initials = member.initials
        colorHex = Int64(member.colorHex)
        isMe = member.isMe
        userUID = member.userUID
    }
}

private extension ActivityEntity {
    func update(from activity: Activity) {
        id = activity.id
        day = Int16(clamping: activity.day)
        title = activity.title
        minutes = Int16(clamping: activity.minutes)
        place = activity.place
        effort = activity.effort.rawValue
        isOutdoor = activity.isOutdoor
        isDone = activity.isDone
    }
}

private extension PackingItemEntity {
    func update(from item: PackingItem) {
        id = item.id
        name = item.name
        category = item.category
        isPacked = item.isPacked
    }
}

private extension ExpenseEntity {
    func update(from expense: Expense, members: [UUID: MemberEntity], context: NSManagedObjectContext) {
        id = expense.id
        title = expense.title
        amount = expense.amount
        category = expense.category.rawValue
        splitMethod = expense.splitMethod.rawValue
        date = expense.date
        paidBy = members[expense.paidBy.id]

        // Shares don't have ids so rebuild them, but only if something changed
        let current = shares.rows(of: ExpenseShareEntity.self)
        let unchanged = current.count == expense.shares.count
            && zip(current, expense.shares).allSatisfy { row, share in
                row.member?.id == share.member.id && row.amount == share.amount
            }
        guard !unchanged else { return }

        current.forEach(context.delete)
        shares = NSOrderedSet(array: expense.shares.map { share in
            let row = ExpenseShareEntity(context: context)
            row.member = members[share.member.id]
            row.amount = share.amount
            return row
        })
    }
}

private extension PaymentEntity {
    func update(from payment: Payment, members: [UUID: MemberEntity]) {
        id = payment.id
        amount = payment.amount
        date = payment.date
        payer = members[payment.from.id]
        receiver = members[payment.to.id]
    }
}

private extension MemoryEntity {
    func update(from memory: Memory, trip: TripEntity, context: NSManagedObjectContext) {
        id = memory.id
        self.trip = trip
        title = memory.title
        date = memory.date
        day = Int16(clamping: memory.day)
        place = memory.place
        transcript = memory.transcript
        duration = Int32(clamping: memory.duration)
        mood = memory.mood?.rawValue
        sentiment = memory.sentiment.map { NSNumber(value: $0) }
        placeTags = memory.placeTags
        landmark = memory.landmark
        landmarkConfidence = memory.landmarkConfidence.map { NSNumber(value: $0) }
        sceneTags = memory.sceneTags
        linkedActivity = memory.linkedActivity
        isVisited = memory.isVisited
        transcriptUnavailable = memory.transcriptUnavailable
        audioFileName = memory.audioFileName

        let tripMembers = trip.members.rows(of: MemberEntity.self)
        people = NSOrderedSet(array: memory.people.compactMap { person in
            tripMembers.first { $0.id == person.id }
        })
    }
}

// Inits return nil for bad rows so one broken row doesn't crash the app

private extension Trip {
    init?(entity: TripEntity) {
        guard let id = entity.id, let name = entity.name,
              let startDate = entity.startDate, let endDate = entity.endDate else { return nil }

        let members = entity.members.rows(of: MemberEntity.self).compactMap(Member.init(entity:))
        var membersByID: [UUID: Member] = [:]
        for member in members { membersByID[member.id] = member }

        self.init(
            id: id,
            name: name,
            destination: entity.destination ?? "",
            startDate: startDate,
            endDate: endDate,
            budget: entity.budget,
            members: members,
            cover: SamplePhoto(rawValue: entity.coverName ?? "") ?? .mistyHills,
            remindersOn: entity.remindersOn,
            activities: entity.activities.rows(of: ActivityEntity.self).compactMap(Activity.init(entity:)),
            packing: entity.packingItems.rows(of: PackingItemEntity.self).compactMap(PackingItem.init(entity:)),
            expenses: entity.expenses.rows(of: ExpenseEntity.self).compactMap { Expense(entity: $0, members: membersByID) },
            payments: entity.payments.rows(of: PaymentEntity.self).compactMap { Payment(entity: $0, members: membersByID) },
            coverImageID: entity.coverImage?.id,
            ownerUID: entity.ownerUID,
            memberUIDs: entity.memberUIDs ?? [],
            latitude: entity.latitude?.doubleValue,
            longitude: entity.longitude?.doubleValue
        )
    }
}

private extension Member {
    init?(entity: MemberEntity) {
        guard let id = entity.id, let name = entity.name else { return nil }
        self.init(id: id, name: name, initials: entity.initials, colorHex: Int(entity.colorHex), isMe: entity.isMe,
                  userUID: entity.userUID)
    }
}

private extension Activity {
    init?(entity: ActivityEntity) {
        guard let id = entity.id, let title = entity.title else { return nil }
        self.init(
            id: id,
            day: Int(entity.day),
            title: title,
            minutes: Int(entity.minutes),
            place: entity.place ?? "",
            effort: Effort(rawValue: entity.effort ?? "") ?? .low,
            isOutdoor: entity.isOutdoor,
            isDone: entity.isDone
        )
    }
}

private extension PackingItem {
    init?(entity: PackingItemEntity) {
        guard let id = entity.id, let name = entity.name else { return nil }
        self.init(id: id, name: name, category: entity.category ?? "Other", isPacked: entity.isPacked)
    }
}

private extension Expense {
    init?(entity: ExpenseEntity, members: [UUID: Member]) {
        guard let id = entity.id, let title = entity.title, let date = entity.date,
              let payerID = entity.paidBy?.id, let paidBy = members[payerID] else { return nil }

        let shares = entity.shares.rows(of: ExpenseShareEntity.self).compactMap { row -> ExpenseShare? in
            guard let memberID = row.member?.id, let member = members[memberID] else { return nil }
            return ExpenseShare(member: member, amount: row.amount)
        }
        self.init(
            id: id,
            title: title,
            amount: entity.amount,
            category: ExpenseCategory(rawValue: entity.category ?? "") ?? .activities,
            paidBy: paidBy,
            splitMethod: SplitMethod(rawValue: entity.splitMethod ?? "") ?? .equal,
            shares: shares,
            date: date
        )
    }
}

private extension Payment {
    init?(entity: PaymentEntity, members: [UUID: Member]) {
        guard let id = entity.id, let date = entity.date,
              let payerID = entity.payer?.id, let from = members[payerID],
              let receiverID = entity.receiver?.id, let to = members[receiverID] else { return nil }
        self.init(id: id, from: from, to: to, amount: entity.amount, date: date)
    }
}

private extension Memory {
    init?(entity: MemoryEntity) {
        guard let id = entity.id, let tripID = entity.trip?.id,
              let title = entity.title, let date = entity.date else { return nil }
        self.init(
            id: id,
            tripID: tripID,
            title: title,
            date: date,
            day: Int(entity.day),
            place: entity.place ?? "",
            transcript: entity.transcript ?? "",
            duration: Int(entity.duration),
            people: entity.people.rows(of: MemberEntity.self).compactMap(Member.init(entity:)),
            mood: entity.mood.flatMap(Mood.init(rawValue:)),
            sentiment: entity.sentiment?.doubleValue,
            placeTags: entity.placeTags ?? [],
            landmark: entity.landmark,
            landmarkConfidence: entity.landmarkConfidence?.doubleValue,
            sceneTags: entity.sceneTags ?? [],
            photos: entity.photos.rows(of: PhotoEntity.self).compactMap { row -> MemoryPhoto? in
                if let imageID = row.image?.id { return .stored(imageID) }
                return SamplePhoto(rawValue: row.assetName ?? "").map(MemoryPhoto.sample)
            },
            linkedActivity: entity.linkedActivity,
            isVisited: entity.isVisited,
            transcriptUnavailable: entity.transcriptUnavailable,
            audioFileName: entity.audioFileName
        )
    }
}

private extension Optional where Wrapped == NSOrderedSet {
    func rows<Row>(of type: Row.Type) -> [Row] {
        self?.array.compactMap { $0 as? Row } ?? []
    }
}
