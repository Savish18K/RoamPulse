import SwiftUI

// MARK: - DemoClock

/// A fixed "now" so the prototype always looks like the Figma screens
/// (Sunday 13 Dec 2026, 16:40 — Day 2 of the Hill Country trip).
/// Swap `now` for `Date()` once real data is stored.
enum DemoClock {
    static let calendar = Calendar(identifier: .gregorian)

    static let now = date(2026, 12, 13, 16, 40)

    /// Minutes since midnight for `now`.
    static var minutesNow: Int {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .now
    }

    static func days(from start: Date, to end: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

// MARK: - SampleData

/// Sample content that mirrors the Figma prototype.
/// Everything here will be replaced by Core Data once storage is added.
enum SampleData {

    // MARK: - People

    static let profile = UserProfile(fullName: "Savishka Kuruppu", email: "savishka@icloud.com")

    static let savishka = Member(name: "Savishka", initials: "SK", color: Color(hex: 0xD9738F), isMe: true)
    static let samee = Member(name: "Samee", initials: "SM", color: Color(hex: 0x5B8FD6))
    static let suu = Member(name: "Suu", initials: "SU", color: Color(hex: 0xC98B5B))
    static let suresha = Member(name: "Suresha", initials: "SR", color: Color(hex: 0x6E9F7A))
    static let crew = [savishka, samee, suu, suresha]

    static let placesVisited = 16

    // MARK: - Trips

    static var trips: [Trip] { [hillCountry, jaffna, colombo, sigiriya] }

    static let hillCountry: Trip = {
        var trip = Trip(
            name: "Hill Country Explorer",
            destination: "Kandy to Ella",
            startDate: DemoClock.date(2026, 12, 12),
            endDate: DemoClock.date(2026, 12, 15),
            budget: 120_000,
            members: crew,
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
            activity(3, 15, 0, "Ravana Falls", "Ravana Falls", .moderate, outdoor: true,
                     advisory: "Heavy rain likely 14:00–17:00. Try moving this earlier."),
            activity(3, 19, 30, "Dinner in Ella town", "Ella", .low),
            activity(4, 9, 0, "Tea factory tour", "Halpewatte", .low),
            activity(4, 13, 0, "Train back to Kandy", "Ella to Kandy", .low),
        ]
        trip.packing = packingTemplate(packed: true)
        trip.expenses = [
            Expense(title: "Kandy guesthouse", amount: 14_000, category: .lodging, paidBy: savishka, splitWith: crew, date: DemoClock.date(2026, 12, 12, 18, 0)),
            Expense(title: "Car and driver Colombo to Kandy", amount: 12_000, category: .transport, paidBy: suresha, splitWith: crew, date: DemoClock.date(2026, 12, 12, 7, 0)),
            Expense(title: "Lunch in Peradeniya", amount: 2_500, category: .food, paidBy: samee, splitWith: crew, date: DemoClock.date(2026, 12, 12, 13, 30)),
            Expense(title: "Temple of the Tooth entry", amount: 2_500, category: .activities, paidBy: suu, splitWith: crew, date: DemoClock.date(2026, 12, 12, 11, 30)),
            Expense(title: "Breakfast in Kandy", amount: 3_400, category: .food, paidBy: samee, splitWith: crew, date: DemoClock.date(2026, 12, 13, 8, 0)),
            Expense(title: "Train tickets", amount: 6_200, category: .transport, paidBy: suresha, splitWith: crew, date: DemoClock.date(2026, 12, 13, 8, 30)),
            Expense(title: "Lunch in Ella", amount: 6_800, category: .food, paidBy: samee, splitWith: crew, date: DemoClock.date(2026, 12, 13, 13, 0)),
            Expense(title: "Ella homestay", amount: 18_000, category: .lodging, paidBy: savishka, splitWith: crew, date: DemoClock.date(2026, 12, 13, 16, 0)),
            Expense(title: "Little Adam's Peak guide deposit", amount: 3_000, category: .activities, paidBy: suu, splitWith: crew, date: DemoClock.date(2026, 12, 13, 16, 30)),
        ]
        trip.balances = [
            Balance(member: savishka, amount: 14_900),
            Balance(member: suresha, amount: 1_100),
            Balance(member: samee, amount: -4_400),
            Balance(member: suu, amount: -11_600),
        ]
        trip.settlements = [
            Settlement(from: suu, to: savishka, amount: 11_600),
            Settlement(from: samee, to: savishka, amount: 3_300),
            Settlement(from: samee, to: suresha, amount: 1_100),
        ]
        trip.advisoryDays = [3]
        return trip
    }()

    static let jaffna: Trip = {
        var trip = Trip(
            name: "Jaffna Heritage Tour",
            destination: "Jaffna",
            startDate: DemoClock.date(2027, 4, 10),
            endDate: DemoClock.date(2027, 4, 14),
            budget: 100_000,
            members: crew,
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
        trip.packing = packingTemplate(packed: false)
        return trip
    }()

    static let colombo: Trip = {
        var trip = Trip(
            name: "Colombo City Break",
            destination: "Colombo",
            startDate: DemoClock.date(2026, 10, 3),
            endDate: DemoClock.date(2026, 10, 4),
            budget: 50_000,
            members: [savishka, samee],
            cover: .colomboSkyline
        )
        trip.activities = [
            activity(1, 10, 0, "Galle Face Green", "Colombo", .low, outdoor: true, done: true),
            activity(1, 17, 30, "Lotus Tower", "Colombo", .low, done: true),
            activity(2, 9, 0, "Gangaramaya Temple", "Colombo", .low, done: true),
        ]
        trip.packing = packingTemplate(packed: true)
        trip.expenses = [
            Expense(title: "Trains and tuk-tuks", amount: 6_000, category: .transport, paidBy: savishka, splitWith: [savishka, samee], date: DemoClock.date(2026, 10, 3, 9, 0)),
            Expense(title: "City hotel", amount: 18_000, category: .lodging, paidBy: savishka, splitWith: [savishka, samee], date: DemoClock.date(2026, 10, 3, 14, 0)),
            Expense(title: "Dinner at Ministry of Crab", amount: 8_000, category: .food, paidBy: samee, splitWith: [savishka, samee], date: DemoClock.date(2026, 10, 3, 20, 0)),
            Expense(title: "Lotus Tower tickets", amount: 10_000, category: .activities, paidBy: samee, splitWith: [savishka, samee], date: DemoClock.date(2026, 10, 4, 17, 30)),
        ]
        return trip
    }()

    static let sigiriya: Trip = {
        var trip = Trip(
            name: "Sigiriya & Dambulla",
            destination: "Sigiriya and Dambulla",
            startDate: DemoClock.date(2026, 8, 21),
            endDate: DemoClock.date(2026, 8, 23),
            budget: 90_000,
            members: [savishka, suu, suresha],
            cover: .sigiriya
        )
        trip.activities = [
            activity(1, 6, 30, "Sigiriya Rock Fortress", "Sigiriya", .high, outdoor: true, done: true),
            activity(2, 9, 0, "Dambulla Cave Temple", "Dambulla", .moderate, done: true),
            activity(3, 7, 0, "Minneriya safari", "Minneriya", .low, outdoor: true, done: true),
        ]
        trip.packing = packingTemplate(packed: true)
        trip.expenses = [
            Expense(title: "Van hire", amount: 18_000, category: .transport, paidBy: suresha, splitWith: [savishka, suu, suresha], date: DemoClock.date(2026, 8, 21, 5, 0)),
            Expense(title: "Jungle lodge", amount: 36_000, category: .lodging, paidBy: savishka, splitWith: [savishka, suu, suresha], date: DemoClock.date(2026, 8, 21, 15, 0)),
            Expense(title: "Meals", amount: 14_000, category: .food, paidBy: suu, splitWith: [savishka, suu, suresha], date: DemoClock.date(2026, 8, 22, 13, 0)),
            Expense(title: "Entry tickets and safari", amount: 18_000, category: .activities, paidBy: savishka, splitWith: [savishka, suu, suresha], date: DemoClock.date(2026, 8, 23, 7, 0)),
        ]
        return trip
    }()

    // MARK: - Packing

    static let packingCategories = ["Documents", "Clothing", "Rain Gear", "Electronics", "Toiletries"]

    static func packingTemplate(packed: Bool) -> [PackingItem] {
        let groups: [(String, [String])] = [
            ("Documents", ["Passport", "Tickets", "Travel insurance", "National ID"]),
            ("Clothing", ["Light shirts", "Hiking pants", "Underwear", "Socks", "Waterproof jacket"]),
            ("Rain Gear", ["Umbrella", "Poncho", "Waterproof dry bag"]),
            ("Electronics", ["Phone charger", "Power bank", "Camera", "Noise-cancelling headphones"]),
            ("Toiletries", ["Toothbrush", "Sunscreen SPF 50", "Personal medications", "First aid kit"]),
        ]
        return groups.flatMap { category, names in
            names.map { PackingItem(name: $0, category: category, isPacked: packed) }
        }
    }

    // MARK: - Journal

    static let memories: [Memory] = {
        let trip = hillCountry.id
        return [
            Memory(tripID: trip, title: "Voice note in Sinhala", date: DemoClock.date(2026, 12, 12, 9, 10), day: 1,
                   place: "Kandy", transcript: "", duration: 42, people: [savishka],
                   transcriptUnavailable: true),
            Memory(tripID: trip, title: "Temple of the Tooth", date: DemoClock.date(2026, 12, 12, 11, 40), day: 1,
                   place: "Kandy",
                   transcript: "Very serene experience. White flowers everywhere. We had to take our shoes off at the entrance and walk slowly with the crowd towards the inner chamber. The drumming during the puja was unforgettable.",
                   duration: 195, people: [suresha, samee], mood: .positive, sentiment: 0.68,
                   landmark: "Temple of the Tooth", linkedActivity: "Day 1 • 11:30 Temple of the Tooth", isVisited: true),
            Memory(tripID: trip, title: "Evening at Kandy Lake", date: DemoClock.date(2026, 12, 12, 18, 20), day: 1,
                   place: "Kandy",
                   transcript: "Quiet walk by the lake. Rain started on the way back. Splitting the umbrella price with Savishka. Enjoyed fresh ginger tea and short eats by the water as the sunset reflected on the temple roof.",
                   duration: 105, people: [savishka], mood: .mixed, sentiment: 0.08,
                   linkedActivity: "Day 1 • 18:00 Evening walk at Kandy Lake", isVisited: true),
            Memory(tripID: trip, title: "Train through the tea country", date: DemoClock.date(2026, 12, 13, 11, 5), day: 2,
                   place: "Haputale",
                   transcript: "The mist cleared just as we passed the viaduct. Looking down we can see tea pluckers with bright baskets working along the steep green terraces. The landscape opened up and the tea estates started somewhere after Nanu Oya filling the valleys in endless rows.",
                   duration: 130, people: [samee, suu], mood: .positive, sentiment: 0.74,
                   placeTags: ["Kandy", "Peradeniya", "Nanu Oya", "Haputale"],
                   photos: [.trainWindow, .teaEstate],
                   linkedActivity: "Day 2 • 08:45 Scenic train ride through hills", isVisited: true),
            Memory(tripID: trip, title: "View from the homestay balcony", date: DemoClock.date(2026, 12, 13, 16, 22), day: 2,
                   place: "Ella",
                   transcript: "The rain stopped for a few minutes and the whole valley went quiet. You can see Little Adams Peak from the balcony. Samee says we should leave for Nine Arch Bridge at five.",
                   duration: 48, people: [samee], mood: .positive, sentiment: 0.62,
                   placeTags: ["Ella"], linkedActivity: "Day 2 • 16:00 Check in Ella homestay"),
            Memory(tripID: trip, title: "Walking down from the tunnel", date: DemoClock.date(2026, 12, 13, 17, 35), day: 2,
                   place: "Ella",
                   transcript: "Took the path down from tunnel nineteen. Muddy after the rain but the view of the arches through the trees was worth it.",
                   duration: 52, people: [suu, samee], mood: .positive, sentiment: 0.55,
                   landmark: "Nine Arch Bridge", linkedActivity: "Day 2 • 17:30 Nine Arch Bridge viewpoint", isVisited: true),
            Memory(tripID: trip, title: "Bridge from the tea ridge", date: DemoClock.date(2026, 12, 13, 17, 48), day: 2,
                   place: "Ella", transcript: "", duration: 0, people: [suu, samee],
                   landmark: "Nine Arch Bridge", landmarkConfidence: 0.81, sceneTags: ["Train", "Bridge", "Mountain"],
                   photos: [.blueTrainBridge], linkedActivity: "Day 2 • 17:30 Nine Arch Bridge viewpoint", isVisited: true),
            Memory(tripID: trip, title: "Blue train at Nine Arch Bridge", date: DemoClock.date(2026, 12, 13, 17, 52), day: 2,
                   place: "Ella",
                   transcript: "Waited on the ridge with Suu and Samee for the blue train to Badulla. It crossed Nine Arch Bridge right on time and the whole crowd went quiet. Best view of the trip so far.",
                   duration: 80, people: [suu, samee], mood: .positive, sentiment: 0.71,
                   placeTags: ["Ella"], landmark: "Nine Arch Bridge", landmarkConfidence: 0.94,
                   sceneTags: ["Bridge", "Mountain", "Forest"], photos: [.nineArchBridge, .blueTrainBridge],
                   linkedActivity: "Day 2 • 17:30 Nine Arch Bridge viewpoint", isVisited: true),
        ]
    }()

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

    // MARK: - Weather

    static let ellaWeather = WeatherSnapshot(
        location: "Ella",
        condition: "Light rain",
        symbol: "cloud.drizzle.fill",
        temperature: 19, high: 22, low: 15,
        humidity: 88, windKmh: 11, rainChance: 70,
        sunset: "18:02", updatedAt: "16:32",
        hourly: [
            HourlyForecast(label: "Now", temperature: 19, rainChance: 70, symbol: "cloud.drizzle.fill"),
            HourlyForecast(label: "17:00", temperature: 19, rainChance: 60, symbol: "cloud.drizzle.fill"),
            HourlyForecast(label: "18:00", temperature: 18, rainChance: 40, symbol: "cloud.drizzle.fill"),
            HourlyForecast(label: "19:00", temperature: 17, rainChance: 20, symbol: "cloud.fill"),
            HourlyForecast(label: "20:00", temperature: 16, rainChance: 10, symbol: "cloud.moon.fill"),
            HourlyForecast(label: "21:00", temperature: 16, rainChance: 10, symbol: "moon.fill"),
        ],
        daily: [
            DailyForecast(dayLabel: "Sun 13", tripDay: 2, condition: "Light rain", symbol: "cloud.drizzle", rainChance: nil, high: 22, low: 15),
            DailyForecast(dayLabel: "Mon 14", tripDay: 3, condition: "Heavy rain", symbol: "cloud.heavyrain", rainChance: 90, high: 21, low: 15),
            DailyForecast(dayLabel: "Tue 15", tripDay: 4, condition: "Cloudy", symbol: "cloud", rainChance: nil, high: 23, low: 16),
            DailyForecast(dayLabel: "Wed 16", tripDay: nil, condition: "Partly sunny", symbol: "cloud.sun", rainChance: nil, high: 24, low: 16),
            DailyForecast(dayLabel: "Thu 17", tripDay: nil, condition: "Showers", symbol: "cloud.rain", rainChance: nil, high: 23, low: 15),
        ],
        advisory: WeatherAdvisory(
            day: 3,
            title: "Heavy Rain Advisory • Mon",
            shortMessage: "Heavy rain likely 14:00–17:00. Schedule outdoor sights early.",
            message: "Heavy rain likely Mon 14:00 to 17:00. Ravana Falls water levels may rise; outdoor activities affected."
        )
    )

    // MARK: - Helpers

    private static func activity(_ day: Int, _ hour: Int, _ minute: Int, _ title: String, _ place: String,
                                 _ effort: Effort, outdoor: Bool = false, done: Bool = false,
                                 advisory: String? = nil) -> Activity {
        Activity(day: day, title: title, minutes: hour * 60 + minute, place: place, effort: effort,
                 isOutdoor: outdoor, isDone: done, advisory: advisory)
    }
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
