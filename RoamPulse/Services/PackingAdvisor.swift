import Foundation

struct PackingSuggestion: Identifiable, Hashable {
    var item: String
    var category: String
    // e.g. "Rain likely on Day 3 (90%)"
    var reason: String
    var icon: String

    var id: String { item }
}

enum PackingAdvisor {

    // Other categories come after these
    static let categories = ["Documents", "Clothing", "Rain Gear", "Electronics", "Toiletries"]

    static func defaultTemplate() -> [PackingItem] {
        let groups: [(category: String, items: [String])] = [
            ("Documents", ["Passport", "Tickets", "Travel insurance", "National ID"]),
            ("Clothing", ["Light shirts", "Hiking pants", "Underwear", "Socks", "Waterproof jacket"]),
            ("Rain Gear", ["Umbrella", "Poncho", "Waterproof dry bag"]),
            ("Electronics", ["Phone charger", "Power bank", "Camera", "Noise-cancelling headphones"]),
            ("Toiletries", ["Toothbrush", "Sunscreen SPF 50", "Personal medications", "First aid kit"]),
        ]
        return groups.flatMap { group in
            group.items.map { PackingItem(name: $0, category: group.category) }
        }
    }

    // % chance of rain
    static let rainyDay = 60
    // °C
    static let hotDay = 30
    // °C
    static let coldNight = 12

    // Skips anything already on the list
    static func suggestions(for trip: Trip, forecast: WeatherSnapshot?) -> [PackingSuggestion] {
        let tripDays = forecast?.daily.filter { $0.tripDay != nil } ?? []
        var suggestions: [PackingSuggestion] = []

        if let wettest = tripDays.max(by: { ($0.rainChance ?? 0) < ($1.rainChance ?? 0) }),
           let day = wettest.tripDay, let rain = wettest.rainChance, rain >= rainyDay {
            let reason = "Rain likely on Day \(day) (\(rain)%)"
            suggestions.append(PackingSuggestion(item: "Camera rain cover", category: "Rain Gear", reason: reason, icon: "cloud.rain"))
            suggestions.append(PackingSuggestion(item: "Quick-dry towel", category: "Rain Gear", reason: reason, icon: "cloud.rain"))
        }

        if let hottest = tripDays.max(by: { $0.high < $1.high }), let day = hottest.tripDay, hottest.high >= hotDay {
            let reason = "Hot on Day \(day) (\(hottest.high)°)"
            suggestions.append(PackingSuggestion(item: "Sun hat", category: "Clothing", reason: reason, icon: "sun.max"))
            suggestions.append(PackingSuggestion(item: "Refillable water bottle", category: "Extras", reason: reason, icon: "sun.max"))
        }

        if let coldest = tripDays.min(by: { $0.low < $1.low }), let day = coldest.tripDay, coldest.low <= coldNight {
            let reason = "Cold night on Day \(day) (\(coldest.low)°)"
            suggestions.append(PackingSuggestion(item: "Warm fleece", category: "Clothing", reason: reason, icon: "thermometer.snowflake"))
        }

        let inPlanOrder = trip.activities.sorted { ($0.day, $0.minutes) < ($1.day, $1.minutes) }
        if let hardest = inPlanOrder.first(where: { $0.effort == .high }) {
            let reason = "\(hardest.title) is high effort"
            suggestions.append(PackingSuggestion(item: "Hiking shoes", category: "Clothing", reason: reason, icon: "figure.hiking"))
            suggestions.append(PackingSuggestion(item: "Energy snacks", category: "Extras", reason: reason, icon: "figure.hiking"))
        }

        let alreadyPacked = Set(trip.packing.map { $0.name.lowercased() })
        return suggestions.filter { !alreadyPacked.contains($0.item.lowercased()) }
    }

    static func orderedCategories(in items: [PackingItem]) -> [String] {
        let used = Set(items.map(\.category))
        let known = categories.filter(used.contains)
        let extra = used.subtracting(known).sorted()
        return known + extra
    }
}
