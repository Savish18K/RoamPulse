import SwiftUI

// MARK: - SampleData

/// Sample trips that mirror the Figma prototype.
///
/// They are added when a new account is created, and again from Settings → Load sample trips.
/// Dates are worked out from "now", so Hill Country Explorer is always on its second day.
enum SampleData {

    // MARK: - People

    static let profile = UserProfile(fullName: "Savishka Kuruppu", email: "savishka@icloud.com")

    /// The local user, shown on Home and Profile.
    static let me = Member(name: "Savishka", initials: "SK", colorHex: 0xD9738F, isMe: true)

    /// The four friends. Members are saved per trip, so each trip gets its own copies (with new ids).
    private struct Crew {
        let savishka = Member(name: "Savishka", initials: "SK", colorHex: 0xD9738F, isMe: true)
        let samee = Member(name: "Samee", initials: "SM", colorHex: 0x5B8FD6)
        let suu = Member(name: "Suu", initials: "SU", colorHex: 0xC98B5B)
        let suresha = Member(name: "Suresha", initials: "SR", colorHex: 0x6E9F7A)

        var everyone: [Member] { [savishka, samee, suu, suresha] }
    }

    /// Dates counted in days from today, e.g. `days.at(-1, 18, 30)` is yesterday at 18:30.
    private struct RelativeDays {
        let today: Date

        func at(_ offset: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            let calendar = Calendar.trip
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(day, atMinutes: hour * 60 + minute)
        }
    }

    // MARK: - Trips

    /// The sample trips and journal. Hill Country Explorer started yesterday,
    /// Jaffna is a few months away, and the Colombo and Sigiriya trips are finished.
    static func make(now: Date) -> (trips: [Trip], memories: [Memory]) {
        let days = RelativeDays(today: Calendar.trip.startOfDay(for: now))
        let hill = hillCountry(days)
        return ([hill.trip, jaffna(days), colombo(days), sigiriya(days)], hill.memories)
    }

    /// Day 1 is yesterday (offset -1) and Day 2 is today (offset 0).
    private static func hillCountry(_ days: RelativeDays) -> (trip: Trip, memories: [Memory]) {
        let crew = Crew()
        var trip = Trip(
            name: "Hill Country Explorer",
            destination: "Kandy to Ella",
            startDate: days.at(-1),
            endDate: days.at(2),
            budget: 120_000,
            members: crew.everyone,
            cover: .hillTrain
        )
        trip.activities = [
            activity(1, 7, 0, "Drive from Colombo to Kandy", "Kandy", .low, done: true),
            activity(1, 11, 30, "Temple of the Tooth", "Kandy", .low, done: true),
            activity(1, 13, 0, "Lunch in Peradeniya", "Peradeniya", .low, done: true),
            activity(1, 14, 30, "Peradeniya Botanical Gardens", "Peradeniya", .moderate, outdoor: true, done: true),
            activity(1, 18, 0, "Evening walk at Kandy Lake", "Kandy", .low, outdoor: true, done: true),
            activity(2, 7, 30, "Breakfast at hotel", "Kandy", .low, done: true),
            activity(2, 8, 45, "Scenic train ride through hills", "Kandy to Ella", .low, done: true),
            activity(2, 16, 0, "Check in Ella homestay", "Ella", .low, done: true),
            activity(2, 17, 30, "Nine Arch Bridge viewpoint", "Nine Arch Bridge", .moderate, outdoor: true),
            activity(3, 6, 0, "Little Adam's Peak sunrise hike", "Little Adam's Peak", .high, outdoor: true),
            activity(3, 11, 0, "Ella spice garden", "Ella", .low),
            activity(3, 15, 0, "Ravana Falls", "Ravana Falls", .moderate, outdoor: true),
            activity(3, 19, 30, "Dinner in Ella town", "Ella", .low),
            activity(4, 9, 0, "Tea factory tour", "Halpewatte", .low),
            activity(4, 13, 0, "Train back to Kandy", "Ella to Kandy", .low),
        ]
        trip.packing = template(packed: true)
        trip.expenses = [
            expense("Kandy guesthouse", 14_000, .lodging, paidBy: crew.savishka, splitWith: crew.everyone, days.at(-1, 18, 0)),
            expense("Car and driver Colombo to Kandy", 12_000, .transport, paidBy: crew.suresha, splitWith: crew.everyone, days.at(-1, 7, 0)),
            expense("Lunch in Peradeniya", 2_500, .food, paidBy: crew.samee, splitWith: crew.everyone, days.at(-1, 13, 30)),
            expense("Temple of the Tooth entry", 2_500, .activities, paidBy: crew.suu, splitWith: crew.everyone, days.at(-1, 11, 30)),
            expense("Breakfast in Kandy", 3_400, .food, paidBy: crew.samee, splitWith: crew.everyone, days.at(0, 8, 0)),
            expense("Train tickets", 6_200, .transport, paidBy: crew.suresha, splitWith: crew.everyone, days.at(0, 8, 30)),
            expense("Lunch in Ella", 6_800, .food, paidBy: crew.samee, splitWith: crew.everyone, days.at(0, 13, 0)),
            expense("Ella homestay", 18_000, .lodging, paidBy: crew.savishka, splitWith: crew.everyone, days.at(0, 16, 0)),
            expense("Little Adam's Peak guide deposit", 3_000, .activities, paidBy: crew.suu, splitWith: crew.everyone, days.at(0, 16, 30)),
        ]

        let memories = [
            Memory(tripID: trip.id, title: "Voice note in Sinhala", date: days.at(-1, 9, 10), day: 1,
                   place: "Kandy", transcript: "", duration: 42, people: [crew.savishka],
                   transcriptUnavailable: true),
            Memory(tripID: trip.id, title: "Temple of the Tooth", date: days.at(-1, 11, 40), day: 1,
                   place: "Kandy",
                   transcript: "Very serene experience. White flowers everywhere. We had to take our shoes off at the entrance and walk slowly with the crowd towards the inner chamber. The drumming during the puja was unforgettable.",
                   duration: 195, people: [crew.suresha, crew.samee], mood: .positive, sentiment: 0.68,
                   landmark: "Temple of the Tooth", linkedActivity: "Day 1 • 11:30 Temple of the Tooth", isVisited: true),
            Memory(tripID: trip.id, title: "Evening at Kandy Lake", date: days.at(-1, 18, 20), day: 1,
                   place: "Kandy",
                   transcript: "Quiet walk by the lake. Rain started on the way back. Splitting the umbrella price with Savishka. Enjoyed fresh ginger tea and short eats by the water as the sunset reflected on the temple roof.",
                   duration: 105, people: [crew.savishka], mood: .mixed, sentiment: 0.08,
                   linkedActivity: "Day 1 • 18:00 Evening walk at Kandy Lake", isVisited: true),
            Memory(tripID: trip.id, title: "Train through the tea country", date: days.at(0, 11, 5), day: 2,
                   place: "Haputale",
                   transcript: "The mist cleared just as we passed the viaduct. Looking down we can see tea pluckers with bright baskets working along the steep green terraces. The landscape opened up and the tea estates started somewhere after Nanu Oya filling the valleys in endless rows.",
                   duration: 130, people: [crew.samee, crew.suu], mood: .positive, sentiment: 0.74,
                   placeTags: ["Kandy", "Peradeniya", "Nanu Oya", "Haputale"],
                   photos: [.trainWindow, .teaEstate],
                   linkedActivity: "Day 2 • 08:45 Scenic train ride through hills", isVisited: true),
            Memory(tripID: trip.id, title: "View from the homestay balcony", date: days.at(0, 16, 22), day: 2,
                   place: "Ella",
                   transcript: "The rain stopped for a few minutes and the whole valley went quiet. You can see Little Adams Peak from the balcony. Samee says we should leave for Nine Arch Bridge at five.",
                   duration: 48, people: [crew.samee], mood: .positive, sentiment: 0.62,
                   placeTags: ["Ella"], linkedActivity: "Day 2 • 16:00 Check in Ella homestay"),
            Memory(tripID: trip.id, title: "Walking down from the tunnel", date: days.at(0, 17, 35), day: 2,
                   place: "Ella",
                   transcript: "Took the path down from tunnel nineteen. Muddy after the rain but the view of the arches through the trees was worth it.",
                   duration: 52, people: [crew.suu, crew.samee], mood: .positive, sentiment: 0.55,
                   landmark: "Nine Arch Bridge", linkedActivity: "Day 2 • 17:30 Nine Arch Bridge viewpoint", isVisited: true),
            Memory(tripID: trip.id, title: "Bridge from the tea ridge", date: days.at(0, 17, 48), day: 2,
                   place: "Ella", transcript: "", duration: 0, people: [crew.suu, crew.samee],
                   landmark: "Nine Arch Bridge", landmarkConfidence: 0.81, sceneTags: ["Train", "Bridge", "Mountain"],
                   photos: [.blueTrainBridge], linkedActivity: "Day 2 • 17:30 Nine Arch Bridge viewpoint", isVisited: true),
            Memory(tripID: trip.id, title: "Blue train at Nine Arch Bridge", date: days.at(0, 17, 52), day: 2,
                   place: "Ella",
                   transcript: "Waited on the ridge with Suu and Samee for the blue train to Badulla. It crossed Nine Arch Bridge right on time and the whole crowd went quiet. Best view of the trip so far.",
                   duration: 80, people: [crew.suu, crew.samee], mood: .positive, sentiment: 0.71,
                   placeTags: ["Ella"], landmark: "Nine Arch Bridge", landmarkConfidence: 0.94,
                   sceneTags: ["Bridge", "Mountain", "Forest"], photos: [.nineArchBridge, .blueTrainBridge],
                   linkedActivity: "Day 2 • 17:30 Nine Arch Bridge viewpoint", isVisited: true),
        ]
        return (trip, memories)
    }

    private static func jaffna(_ days: RelativeDays) -> Trip {
        let crew = Crew()
        var trip = Trip(
            name: "Jaffna Heritage Tour",
            destination: "Jaffna",
            startDate: days.at(117),
            endDate: days.at(121),
            budget: 100_000,
            members: crew.everyone,
            cover: .jaffnaKovil
        )
        trip.activities = [
            activity(1, 9, 0, "Nallur Kandaswamy Kovil", "Jaffna", .low, outdoor: true),
            activity(1, 14, 0, "Jaffna Fort", "Jaffna", .moderate, outdoor: true),
            activity(2, 8, 0, "Casuarina Beach", "Karainagar", .low, outdoor: true),
            activity(3, 10, 0, "Jaffna Public Library", "Jaffna", .low),
            activity(4, 7, 0, "Delft Island ferry", "Delft", .moderate, outdoor: true),
            activity(5, 10, 0, "Point Pedro lighthouse", "Point Pedro", .low, outdoor: true),
        ]
        trip.packing = template(packed: false)
        return trip
    }

    private static func colombo(_ days: RelativeDays) -> Trip {
        let crew = Crew()
        let pair = [crew.savishka, crew.samee]
        var trip = Trip(
            name: "Colombo City Break",
            destination: "Colombo",
            startDate: days.at(-74),
            endDate: days.at(-73),
            budget: 50_000,
            members: pair,
            cover: .colomboSkyline
        )
        trip.activities = [
            activity(1, 10, 0, "Galle Face Green", "Colombo", .low, outdoor: true, done: true),
            activity(1, 17, 30, "Lotus Tower", "Colombo", .low, done: true),
            activity(2, 9, 0, "Gangaramaya Temple", "Colombo", .low, done: true),
        ]
        trip.packing = template(packed: true)
        trip.expenses = [
            expense("Trains and tuk-tuks", 6_000, .transport, paidBy: crew.savishka, splitWith: pair, days.at(-74, 9, 0)),
            expense("City hotel", 18_000, .lodging, paidBy: crew.savishka, splitWith: pair, days.at(-74, 14, 0)),
            expense("Dinner at Ministry of Crab", 8_000, .food, paidBy: crew.samee, splitWith: pair, days.at(-74, 20, 0)),
            expense("Lotus Tower tickets", 10_000, .activities, paidBy: crew.samee, splitWith: pair, days.at(-73, 17, 30)),
        ]
        // Samee already paid back what they owed, so this trip is settled.
        trip.payments = [Payment(from: crew.samee, to: crew.savishka, amount: 3_000, date: days.at(-72, 10, 0))]
        return trip
    }

    private static func sigiriya(_ days: RelativeDays) -> Trip {
        let crew = Crew()
        let three = [crew.savishka, crew.suu, crew.suresha]
        var trip = Trip(
            name: "Sigiriya & Dambulla",
            destination: "Sigiriya and Dambulla",
            startDate: days.at(-116),
            endDate: days.at(-114),
            budget: 90_000,
            members: three,
            cover: .sigiriya
        )
        trip.activities = [
            activity(1, 6, 30, "Sigiriya Rock Fortress", "Sigiriya", .high, outdoor: true, done: true),
            activity(2, 9, 0, "Dambulla Cave Temple", "Dambulla", .moderate, done: true),
            activity(3, 7, 0, "Minneriya safari", "Minneriya", .low, outdoor: true, done: true),
        ]
        trip.packing = template(packed: true)
        trip.expenses = [
            expense("Van hire", 18_000, .transport, paidBy: crew.suresha, splitWith: three, days.at(-116, 5, 0)),
            expense("Jungle lodge", 36_000, .lodging, paidBy: crew.savishka, splitWith: three, days.at(-116, 15, 0)),
            expense("Meals", 14_000, .food, paidBy: crew.suu, splitWith: three, days.at(-115, 13, 0)),
            expense("Entry tickets and safari", 18_000, .activities, paidBy: crew.savishka, splitWith: three, days.at(-114, 7, 0)),
        ]
        return trip
    }

    // MARK: - Helpers

    private static func template(packed: Bool) -> [PackingItem] {
        PackingAdvisor.defaultTemplate().map { item in
            var item = item
            item.isPacked = packed
            return item
        }
    }

    private static func activity(_ day: Int, _ hour: Int, _ minute: Int, _ title: String, _ place: String,
                                 _ effort: Effort, outdoor: Bool = false, done: Bool = false) -> Activity {
        Activity(day: day, title: title, minutes: hour * 60 + minute, place: place, effort: effort,
                 isOutdoor: outdoor, isDone: done)
    }

    /// An expense split equally between `splitWith`.
    private static func expense(_ title: String, _ amount: Double, _ category: ExpenseCategory,
                                paidBy: Member, splitWith: [Member], _ date: Date) -> Expense {
        Expense(title: title, amount: amount, category: category, paidBy: paidBy,
                shares: ExpenseCalculator.equalShares(of: amount, between: splitWith), date: date)
    }

    // MARK: - Landmarks

    static let landmarks: [Landmark] = [
        Landmark(name: "Nine Arch Bridge", location: "Demodara, Ella", category: .bridge, photo: .nineArchBridge,
                 status: .recognised(confidence: 0.94), tripName: "Hill Country Explorer", photoCount: 2, voiceCount: 1),
        Landmark(name: "Sigiriya Rock Fortress", location: "Sigiriya, Matale", category: .mountain, photo: .sigiriya,
                 status: .recognised(confidence: 0.91), tripName: "Sigiriya & Dambulla", photoCount: 4),
        Landmark(name: "Lotus Tower", location: "Colombo", category: .city, photo: .colomboSkyline,
                 status: .confirmedByUser, tripName: "Colombo City Break", photoCount: 1),
        Landmark(name: "Temple of the Tooth", location: "Kandy", category: .temple, photo: .templeOfTooth,
                 status: .voiceOnly, tripName: "Hill Country Explorer", voiceCount: 1),
        Landmark(name: "Nallur Kandaswamy Kovil", location: "Jaffna", category: .temple, photo: .jaffnaKovil,
                 status: .planned(trip: "Jaffna Heritage Tour")),
        Landmark(name: "Galle Fort Lighthouse", location: "Galle", category: .beach, photo: .galleFort, status: .notVisited),
        Landmark(name: "Dambulla Cave Temple", location: "Dambulla", category: .temple, photo: .dambulla, status: .notVisited),
        Landmark(name: "Ruwanwelisaya", location: "Anuradhapura", category: .temple, photo: .ruwanwelisaya, status: .notVisited),
        Landmark(name: "Sri Pada (Adam's Peak)", location: "Nallathanni", category: .mountain, photo: .sriPada, status: .notVisited),
        Landmark(name: "Coconut Tree Hill", location: "Mirissa", category: .beach, photo: .coconutTreeHill, status: .notVisited),
    ]

}

// MARK: - SamplePhoto

/// Sample photos used across the prototype.
///
/// Each case loads the image set with the same name from Assets.xcassets/Photos
/// (credits in CREDITS.md). If an image is missing, `PhotoView` falls back to the gradient below.
enum SamplePhoto: String, CaseIterable, Identifiable, Hashable {
    case nineArchBridge, blueTrainBridge, trainWindow, hillTrain, teaEstate, mistyHills
    case sigiriya, colomboSkyline, galleFort, jaffnaKovil
    case templeOfTooth, dambulla, ruwanwelisaya, sriPada, coconutTreeHill

    var id: String { rawValue }

    var colors: [Color] {
        switch self {
        case .nineArchBridge: [Color(hex: 0x1F3A24), Color(hex: 0x3F6B35), Color(hex: 0x8A5A3A)]
        case .blueTrainBridge: [Color(hex: 0x2E5E3A), Color(hex: 0x4E8A55), Color(hex: 0x2F6F9F)]
        case .trainWindow: [Color(hex: 0x24476B), Color(hex: 0x4B7F6A), Color(hex: 0x9DB59A)]
        case .hillTrain: [Color(hex: 0x324A3A), Color(hex: 0x6B8F5E), Color(hex: 0xB7C4A8)]
        case .teaEstate: [Color(hex: 0x3A4A2A), Color(hex: 0x8A6A3A), Color(hex: 0xE0A458)]
        case .mistyHills: [Color(hex: 0x4A5A62), Color(hex: 0x7F9399), Color(hex: 0xC7D3D6)]
        case .sigiriya: [Color(hex: 0x3E6B2E), Color(hex: 0x8A7A4A), Color(hex: 0xA0C4E0)]
        case .colomboSkyline: [Color(hex: 0x2B2D5A), Color(hex: 0xC0607A), Color(hex: 0xF2A65A)]
        case .galleFort: [Color(hex: 0x1F4E79), Color(hex: 0x4A90B8), Color(hex: 0xF0C27A)]
        case .jaffnaKovil: [Color(hex: 0x4A2A4A), Color(hex: 0xB0503A), Color(hex: 0xF2B25A)]
        case .templeOfTooth: [Color(hex: 0x5A4A3A), Color(hex: 0xA8957A), Color(hex: 0xE6DCC6)]
        case .dambulla: [Color(hex: 0x3A2E22), Color(hex: 0x8A6A4A), Color(hex: 0xD9B98A)]
        case .ruwanwelisaya: [Color(hex: 0x4F7AA5), Color(hex: 0xB5C4D4), Color(hex: 0xE8E4DA)]
        case .sriPada: [Color(hex: 0x2A3550), Color(hex: 0x5A6A8A), Color(hex: 0xE6A86A)]
        case .coconutTreeHill: [Color(hex: 0x1E6B6B), Color(hex: 0x3FA7A0), Color(hex: 0xF2D49B)]
        }
    }

    var symbol: String {
        switch self {
        case .nineArchBridge, .blueTrainBridge: "tram.fill"
        case .trainWindow, .hillTrain: "train.side.front.car"
        case .teaEstate: "leaf.fill"
        case .mistyHills: "cloud.fog.fill"
        case .sigiriya, .sriPada: "mountain.2.fill"
        case .colomboSkyline: "building.2.fill"
        case .galleFort, .coconutTreeHill: "beach.umbrella.fill"
        case .jaffnaKovil, .templeOfTooth, .dambulla, .ruwanwelisaya: "building.columns.fill"
        }
    }

    /// Mock result of the landmark model for this photo.
    /// Some photos are deliberately below the 70% threshold to show the "please confirm" flow.
    var recognition: RecognitionResult {
        switch self {
        case .nineArchBridge:
            RecognitionResult(
                candidates: [.init(name: "Nine Arch Bridge", confidence: 0.94), .init(name: RecognitionResult.otherLabel, confidence: 0.04)],
                sceneTags: ["Bridge", "Mountain", "Forest", "Outdoor"])
        case .blueTrainBridge:
            RecognitionResult(
                candidates: [.init(name: "Nine Arch Bridge", confidence: 0.81), .init(name: RecognitionResult.otherLabel, confidence: 0.12)],
                sceneTags: ["Train", "Bridge", "Mountain"])
        case .colomboSkyline:
            RecognitionResult(
                candidates: [.init(name: "Galle Fort Lighthouse", confidence: 0.44), .init(name: "Lotus Tower", confidence: 0.38), .init(name: RecognitionResult.otherLabel, confidence: 0.12)],
                sceneTags: ["Beach", "City", "Sunset"])
        case .sigiriya:
            RecognitionResult(
                candidates: [.init(name: "Sigiriya Rock Fortress", confidence: 0.91), .init(name: RecognitionResult.otherLabel, confidence: 0.05)],
                sceneTags: ["Rock", "Forest", "Outdoor"])
        case .jaffnaKovil:
            RecognitionResult(
                candidates: [.init(name: "Nallur Kandaswamy Kovil", confidence: 0.88), .init(name: RecognitionResult.otherLabel, confidence: 0.07)],
                sceneTags: ["Temple", "Sunset", "Crowd"])
        case .galleFort:
            RecognitionResult(
                candidates: [.init(name: "Galle Fort Lighthouse", confidence: 0.86), .init(name: RecognitionResult.otherLabel, confidence: 0.09)],
                sceneTags: ["Beach", "Lighthouse", "Ocean"])
        case .templeOfTooth:
            RecognitionResult(
                candidates: [.init(name: "Temple of the Tooth", confidence: 0.89), .init(name: RecognitionResult.otherLabel, confidence: 0.06)],
                sceneTags: ["Temple", "Lake", "Architecture"])
        case .coconutTreeHill:
            RecognitionResult(
                candidates: [.init(name: "Coconut Tree Hill", confidence: 0.52), .init(name: "Galle Fort Lighthouse", confidence: 0.21), .init(name: RecognitionResult.otherLabel, confidence: 0.18)],
                sceneTags: ["Beach", "Palm Trees", "Ocean"])
        default:
            RecognitionResult(
                candidates: [.init(name: RecognitionResult.otherLabel, confidence: 0.58), .init(name: "Nine Arch Bridge", confidence: 0.21), .init(name: "Sri Pada (Adam's Peak)", confidence: 0.12)],
                sceneTags: ["Mountain", "Forest", "Outdoor"])
        }
    }
}

extension SamplePhoto {
    /// Picks a cover photo for a new trip from the place names in its destination.
    static func cover(for destination: String) -> SamplePhoto {
        let place = destination.lowercased()
        let covers: [(keyword: String, photo: SamplePhoto)] = [
            ("ella", .nineArchBridge), ("kandy", .templeOfTooth), ("galle", .galleFort),
            ("unawatuna", .galleFort), ("hikkaduwa", .galleFort), ("mirissa", .coconutTreeHill),
            ("jaffna", .jaffnaKovil), ("sigiriya", .sigiriya), ("dambulla", .dambulla),
            ("colombo", .colomboSkyline), ("anuradhapura", .ruwanwelisaya), ("adam", .sriPada),
            ("nuwara", .teaEstate), ("haputale", .teaEstate),
        ]
        return covers.first { place.contains($0.keyword) }?.photo ?? .mistyHills
    }
}

// Encodable for Settings → Export my data (saved as its name).
extension SamplePhoto: Encodable {}
