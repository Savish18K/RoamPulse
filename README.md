# RoamPulse IOS app
Offline trip planner for iPhone. Plan day-by-day itineraries, pack, split group expenses, get weather advisories for outdoor activities, and keep a private travel journal. It turns voice memories into searchable text and recognises Sri Lankan landmarks in photos, all on the device. SwiftUI, Core Data, Speech, Natural Language, Vision, Core ML.

## Running

Open `RoamPulse.xcodeproj` in Xcode 26, pick an iPhone simulator and press Run. Requires iOS 17 or later.
To run on a real iPhone, choose your team under *Signing & Capabilities*.

## Project structure

```
RoamPulse/
├── RoamPulseApp.swift         App entry point, root view (onboarding / lock / sheets), tab bar
├── AppDependencies.swift      Creates the services once and hands them to view models
├── Navigation.swift           AppRouter, pushed routes and sheets (builds each screen's view model)
├── Models/
│   ├── Trip.swift             Member, Trip, Activity, PackingItem, Expense, Payment, Balance…
│   └── Memory.swift           Memory, Landmark, Weather
├── Services/
│   ├── Clock.swift            "Now" behind a protocol (real clock in the app, fixed in tests)
│   ├── WeatherService.swift   Forecast behind a protocol (sample data until OpenWeatherMap)
│   ├── ItineraryPlanner.swift Time order, drag to reorder, move day, demanding-day rule
│   ├── PackingAdvisor.swift   Default packing list and weather suggestions
│   └── ExpenseCalculator.swift Splits, balances, settle-up algorithm, 90% budget warning
├── Data/
│   ├── RoamPulse.xcdatamodeld Core Data model (10 entities)
│   ├── PersistenceController.swift Core Data stack (on disk, or in memory for tests)
│   ├── TripRepository.swift   Repository protocol + in-memory version
│   ├── CoreDataTripRepository.swift Saves/loads with Core Data, converts entities ↔ structs
│   ├── TripStore.swift        Shared in-memory copy of the data; saves every change
│   └── SampleData.swift       Sample trips (dates relative to today), sample photos
├── ViewModels/                One view model per screen, mirroring Views/
├── Components/
│   ├── Theme.swift            Colours, gradient, formatters
│   └── Components.swift       Cards, buttons, chips, avatars, photos, segmented tabs
├── Views/                     SwiftUI screens
└── Assets.xcassets
RoamPulseTests/                Swift Testing suites (run with ⌘U)
```

The project uses Xcode folder-synced groups, so any file added to these folders is picked up automatically.
See [ARCHITECTURE.md](ARCHITECTURE.md) for how the layers fit together.

## Current state

Increments 1–3 are done:

- **Architecture:** MVVM with a view model per screen; storage, time and weather sit behind protocols and are
  injected, so tests use an in-memory repository and a fixed clock. The app uses the real date.
- **Core Data:** trips with their members, itinerary, packing list, expenses and payments, plus journal memories
  and photos, are saved on the iPhone and are still there after the app is closed. Trips can be created, edited
  and deleted (with confirmation) and are sorted into Active, Upcoming and Completed.
- **Itinerary:** activities in time order, drag to reorder, drag onto a day tab (or use the menu) to move day,
  demanding-day badge and advice.
- **Packing:** default list, progress ring, suggestions from the forecast and the plan.
- **Expenses:** equal and custom splits, balances, settle-up plan with recorded payments, 90% budget warning and
  a shareable summary.

The sample trips are added on the first launch (Settings → Load sample trips adds them again after deleting
everything). Weather is still sample data, and the journal, photo recognition, map, notifications and Face ID
are still the prototype screens; they come in Increments 4–9.

Photos and avatars live in `Assets.xcassets` (`Photos/` and `Avatars/`). Each `SamplePhoto` case loads the image set
with the same name, and avatars load `avatar_<name>`. Image sources and licences are listed in [CREDITS.md](CREDITS.md).
