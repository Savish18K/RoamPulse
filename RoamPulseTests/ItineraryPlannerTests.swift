import Foundation
import Testing
@testable import RoamPulse

/// The demanding-day rule, time ordering, drag to reorder and moving between days.
struct ItineraryPlannerTests {

    private func activity(_ title: String, at hour: Int, _ minute: Int = 0,
                          effort: Effort = .low, day: Int = 1) -> Activity {
        Activity(day: day, title: title, minutes: hour * 60 + minute, place: "Ella", effort: effort)
    }

    @Test func anEmptyDayHasNoBadge() {
        #expect(ItineraryPlanner.intensity(of: []) == nil)
    }

    @Test func fourEasyActivitiesAreAnEasyDay() {
        // 1 + 1 + 1 + 1 = 4 points, below the moderate line of 5.
        let day = (8...11).map { activity("Stop \($0)", at: $0) }
        #expect(ItineraryPlanner.intensity(of: day) == .easy)
    }

    @Test func fivePointsMakeAModerateDay() {
        // The prototype's Day 2: three easy activities and the Nine Arch Bridge walk (1 + 1 + 1 + 2).
        let day = [
            activity("Breakfast", at: 7, 30),
            activity("Train", at: 8, 45),
            activity("Check in", at: 16),
            activity("Nine Arch Bridge viewpoint", at: 17, 30, effort: .moderate),
        ]
        #expect(ItineraryPlanner.intensity(of: day) == .moderate)
    }

    @Test func oneHighEffortActivityIsAlwaysAtLeastModerate() {
        let day = [activity("Sigiriya Rock Fortress", at: 6, 30, effort: .high)]
        #expect(ItineraryPlanner.intensity(of: day) == .moderate)
    }

    @Test func sevenPointsIsStillModerate() {
        let day = [
            activity("Hike", at: 6, effort: .high),
            activity("Falls", at: 15, effort: .moderate),
            activity("Dinner", at: 19),
        ]
        #expect(ItineraryPlanner.intensity(of: day) == .moderate)
    }

    @Test func thePrototypesDayThreeIsDemanding() {
        // 4 + 1 + 2 + 1 = 8 points.
        let day = [
            activity("Little Adam's Peak sunrise hike", at: 6, effort: .high),
            activity("Ella spice garden", at: 11),
            activity("Ravana Falls", at: 15, effort: .moderate),
            activity("Dinner in Ella town", at: 19, 30),
        ]
        #expect(ItineraryPlanner.intensity(of: day) == .demanding)
    }

    @Test func twoHighEffortActivitiesAreDemanding() {
        let day = [activity("Hike", at: 6, effort: .high), activity("Climb", at: 14, effort: .high)]
        #expect(ItineraryPlanner.intensity(of: day) == .demanding)
    }

    @Test func adviceOnlyAppearsOnDemandingDays() {
        #expect(ItineraryPlanner.demandingDayAdvice(today: .moderate, previousDay: .demanding) == nil)
        #expect(ItineraryPlanner.demandingDayAdvice(today: nil, previousDay: nil) == nil)
        #expect(ItineraryPlanner.demandingDayAdvice(today: .demanding, previousDay: .easy) != nil)
    }

    @Test func backToBackDemandingDaysGetAWarning() {
        let advice = ItineraryPlanner.demandingDayAdvice(today: .demanding, previousDay: .demanding)
        #expect(advice?.contains("in a row") == true)
    }

    @Test func activitiesAreShownInTimeOrder() {
        let day = [activity("Dinner", at: 19), activity("Hike", at: 6), activity("Lunch", at: 13)]
        #expect(ItineraryPlanner.ordered(day).map(\.title) == ["Hike", "Lunch", "Dinner"])
    }

    @Test func activitiesAtTheSameTimeAreSortedByTitle() {
        let day = [activity("Tea", at: 15), activity("Falls", at: 15)]
        #expect(ItineraryPlanner.ordered(day).map(\.title) == ["Falls", "Tea"])
    }

    @Test func reorderingKeepsTheDaysTimeSlots() {
        let day = [activity("Hike", at: 6), activity("Spice garden", at: 11), activity("Falls", at: 15)]

        // Drag Falls (index 2) to the top (index 0).
        let reordered = ItineraryPlanner.reorder(day, moving: 2, to: 0)

        #expect(reordered.map(\.title) == ["Falls", "Hike", "Spice garden"])
        #expect(reordered.map(\.timeText) == ["06:00", "11:00", "15:00"])
        // So the list is still in time order.
        #expect(ItineraryPlanner.ordered(reordered).map(\.title) == ["Falls", "Hike", "Spice garden"])
    }

    @Test func draggingDownWorksToo() {
        let day = [activity("Hike", at: 6), activity("Spice garden", at: 11), activity("Falls", at: 15)]
        let reordered = ItineraryPlanner.reorder(day, moving: 0, to: 2)
        #expect(reordered.map(\.title) == ["Spice garden", "Falls", "Hike"])
        #expect(reordered.last?.timeText == "15:00")
    }

    @Test func reorderingWithABadIndexChangesNothing() {
        let day = [activity("Hike", at: 6), activity("Falls", at: 15)]
        #expect(ItineraryPlanner.reorder(day, moving: 5, to: 0) == day)
        #expect(ItineraryPlanner.reorder(day, moving: 1, to: 1) == day)
    }

    @Test func replacingPutsReorderedActivitiesBackIntoTheTrip() {
        let otherDay = activity("Tea factory", at: 9, day: 4)
        let hike = activity("Hike", at: 6, day: 3)
        let falls = activity("Falls", at: 15, day: 3)
        let reordered = ItineraryPlanner.reorder([hike, falls], moving: 1, to: 0)

        let all = ItineraryPlanner.replacing(reordered, in: [otherDay, hike, falls])
        #expect(all.count == 3)
        #expect(all.first == otherDay)
        #expect(all.first { $0.title == "Falls" }?.timeText == "06:00")
    }

    @Test func movingToAnotherDayKeepsTheTime() {
        let falls = activity("Ravana Falls", at: 15, effort: .moderate, day: 3)
        let moved = ItineraryPlanner.move(falls.id, toDay: 4, dayCount: 4, in: [falls])
        #expect(moved.first?.day == 4)
        #expect(moved.first?.timeText == "15:00")
    }

    @Test func movingIsKeptInsideTheTrip() {
        let falls = activity("Ravana Falls", at: 15, day: 3)
        #expect(ItineraryPlanner.move(falls.id, toDay: 9, dayCount: 4, in: [falls]).first?.day == 4)
        #expect(ItineraryPlanner.move(falls.id, toDay: 0, dayCount: 4, in: [falls]).first?.day == 1)
    }

    @Test func shorteningATripMovesLaterActivitiesToTheNewLastDay() {
        let activities = [activity("A", at: 9, day: 1), activity("B", at: 9, day: 3), activity("C", at: 9, day: 4)]
        let clamped = ItineraryPlanner.clamp(activities, toDayCount: 2)
        #expect(clamped.map(\.day) == [1, 2, 2])
    }

    @Test func clashesFindOtherActivitiesAtTheSameTime() {
        let hike = activity("Hike", at: 6)
        let breakfast = activity("Breakfast", at: 6)
        let lunch = activity("Lunch", at: 13)
        let clashes = ItineraryPlanner.clashes(day: 1, minutes: 360, ignoring: hike.id, in: [hike, breakfast, lunch])
        #expect(clashes.map(\.title) == ["Breakfast"])
    }
}
