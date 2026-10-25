import Foundation

// One landmark the model was trained on. The name is exactly the model's label
struct LandmarkInfo: Identifiable, Hashable {
    let name: String
    let location: String
    let category: LandmarkCategory
    let photo: SamplePhoto
    // Other names people use, so "Sri Dalada Maligawa" in a plan still matches the Temple of the Tooth
    let aliases: [String]

    var id: String { name }
}

enum LandmarkCatalogue {
    static let all: [LandmarkInfo] = [
        LandmarkInfo(name: "Nine Arch Bridge", location: "Demodara, Ella", category: .bridge, photo: .nineArchBridge,
                     aliases: ["Nine Arches Bridge", "Nine Arch", "Demodara Bridge"]),
        LandmarkInfo(name: "Sigiriya Rock Fortress", location: "Sigiriya, Matale", category: .mountain, photo: .sigiriya,
                     aliases: ["Sigiriya", "Lion Rock", "Sigiri"]),
        LandmarkInfo(name: "Temple of the Tooth", location: "Kandy", category: .temple, photo: .templeOfTooth,
                     aliases: ["Sri Dalada Maligawa", "Dalada Maligawa", "Temple of the Sacred Tooth Relic"]),
        LandmarkInfo(name: "Galle Fort Lighthouse", location: "Galle", category: .beach, photo: .galleFort,
                     aliases: ["Galle Lighthouse", "Galle Fort"]),
        LandmarkInfo(name: "Lotus Tower", location: "Colombo", category: .city, photo: .colomboSkyline,
                     aliases: ["Nelum Kuluna", "Colombo Lotus Tower"]),
        LandmarkInfo(name: "Dambulla Cave Temple", location: "Dambulla", category: .temple, photo: .dambulla,
                     aliases: ["Dambulla", "Golden Temple of Dambulla", "Rangiri Dambulla"]),
        LandmarkInfo(name: "Ruwanwelisaya", location: "Anuradhapura", category: .temple, photo: .ruwanwelisaya,
                     aliases: ["Ruwanweliseya", "Ruwanweli Maha Seya", "Mahathupa"]),
        LandmarkInfo(name: "Sri Pada (Adam's Peak)", location: "Nallathanni", category: .mountain, photo: .sriPada,
                     aliases: ["Sri Pada", "Adam's Peak", "Adams Peak", "Samanala Kanda"]),
        LandmarkInfo(name: "Nallur Kandaswamy Kovil", location: "Jaffna", category: .temple, photo: .jaffnaKovil,
                     aliases: ["Nallur Kovil", "Nallur Kandaswamy", "Nallur temple"]),
        LandmarkInfo(name: "Coconut Tree Hill", location: "Mirissa", category: .beach, photo: .coconutTreeHill,
                     aliases: ["Coconut Hill"]),
        LandmarkInfo(name: "Gal Vihara", location: "Polonnaruwa", category: .temple, photo: .galVihara,
                     aliases: ["Gal Viharaya", "Uttararama"]),
        LandmarkInfo(name: "Gangaramaya Temple", location: "Colombo", category: .temple, photo: .gangaramaya,
                     aliases: ["Gangaramaya"]),
    ]

    static func info(named name: String) -> LandmarkInfo? {
        all.first { $0.name == name }
    }

    // The first catalogue landmark named in some text, e.g. an activity title or a transcript
    static func mentioned(in text: String) -> LandmarkInfo? {
        guard !text.isEmpty else { return nil }
        return all.first { info in
            ([info.name] + info.aliases).contains { JournalAnalyzer.containsWord($0, in: text) }
        }
    }

    // The planned activity at this landmark, matched by its title or place
    static func activity(for landmark: String, in activities: [Activity]) -> Activity? {
        activities.first { mentioned(in: "\($0.title) \($0.place)")?.name == landmark }
    }

    // Every landmark with what the user has done there: recognised in a photo, picked by hand,
    // mentioned in a voice note, planned on a trip, or not visited yet
    static func landmarks(memories: [Memory], trips: [Trip], now: Date) -> [Landmark] {
        let tripNames = Dictionary(uniqueKeysWithValues: trips.map { ($0.id, $0.name) })

        return all.map { info in
            let tagged = memories.filter { $0.landmark == info.name }.sorted { $0.date > $1.date }
            let spoken = memories.filter { $0.landmark == nil && mentioned(in: $0.transcript)?.name == info.name }
            var landmark = Landmark(name: info.name, location: info.location, category: info.category, photo: info.photo,
                                    status: .notVisited)
            landmark.photoCount = tagged.reduce(0) { $0 + $1.photos.count }
            landmark.voiceCount = (tagged + spoken).filter(\.hasVoice).count

            if let latest = tagged.first {
                // Recognised by the model if any photo was, otherwise the user picked it
                let confidence = tagged.compactMap(\.landmarkConfidence).max()
                landmark.status = confidence.map { .recognised(confidence: $0) } ?? .confirmedByUser
                landmark.tripName = tripNames[latest.tripID]
            } else if let latest = spoken.max(by: { $0.date < $1.date }) {
                landmark.status = .voiceOnly
                landmark.tripName = tripNames[latest.tripID]
            } else if let trip = trips.first(where: { trip in
                trip.status(at: now) != .completed && activity(for: info.name, in: trip.activities) != nil
            }) {
                landmark.status = .planned(trip: trip.name)
            }
            return landmark
        }
    }
}
