# RoamPulse IOS app
Offline trip planner for iPhone. Plan day-by-day itineraries, pack, split group expenses, get weather advisories for outdoor activities, and keep a private travel journal. It turns voice memories into searchable text and recognises Sri Lankan landmarks in photos, all on the device. SwiftUI, Core Data, Speech, Natural Language, Vision, Core ML.

## Running

Open `RoamPulse.xcodeproj` in Xcode 26, pick an iPhone simulator and press Run. Requires iOS 17 or later.
To run on a real iPhone, choose your team under *Signing & Capabilities*.

## Project structure

```
RoamPulse/
├── RoamPulseApp.swift       App entry point, root view (onboarding / lock / sheets), tab bar
├── Navigation.swift         AppRouter, pushed routes and sheets
├── Models/
│   ├── Trip.swift           Member, Trip, Activity, PackingItem, Expense
│   └── Memory.swift         Memory, Landmark, Weather
├── Data/
│   ├── TripStore.swift      In-memory data shared through the environment
│   └── SampleData.swift     Sample trips/memories, placeholder photos, fixed demo clock
├── Components/
│   ├── Theme.swift          Colours, gradient, formatters
│   └── Components.swift     Cards, buttons, chips, avatars, photos, segmented tabs
├── Views/
│   ├── OnboardingView.swift Onboarding + lock screen
│   ├── HomeView.swift
│   ├── TripsView.swift      Trips list + Create Trip
│   ├── TripDetailView.swift Trip detail + Add Activity + Packing
│   ├── OfflineMapView.swift
│   ├── ExpensesView.swift   Expenses + Analytics + Add Expense
│   ├── WeatherView.swift
│   ├── JournalView.swift    Journal + memory detail + Record Memory
│   ├── PhotosView.swift     Photo picker + landmark recognition
│   ├── InsightsView.swift   Search, timeline, mood
│   ├── LandmarksView.swift  Landmarks grid + landmark detail
│   └── ProfileView.swift    Profile, statistics, settings, about
└── Assets.xcassets
```

The project uses Xcode folder-synced groups, so any file added to these folders is picked up automatically.

## Current state

UI prototype only: every screen from the Figma prototype is built and navigable, using sample data
(`Data/SampleData.swift`) and a fixed "now" of Sun 13 Dec 2026, 16:40 (`DemoClock`). Nothing is persisted yet.
Core Data, OpenWeatherMap, notifications, Face ID, Speech, Natural Language, Vision and Core ML are still to be added.

Photos and avatars live in `Assets.xcassets` (`Photos/` and `Avatars/`). Each `SamplePhoto` case loads the image set
with the same name, and avatars load `avatar_<name>`. Image sources and licences are listed in [CREDITS.md](CREDITS.md).
