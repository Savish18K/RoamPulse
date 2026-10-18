# RoamPulse IOS app
Offline trip planner for iPhone. Plan day-by-day itineraries, pack, split group expenses, get weather advisories for outdoor activities, and keep a private travel journal. It turns voice memories into searchable text and recognises Sri Lankan landmarks in photos, all on the device. Trips are backed up to your account with Firebase. SwiftUI, Core Data, Firebase Auth, Cloud Firestore, Speech, Natural Language, Vision, Core ML.

## Running

Open `RoamPulse.xcodeproj` in Xcode 26, pick an iPhone simulator and press Run. Requires iOS 26 or later (on-device SpeechAnalyzer needs it).
To run on a real iPhone, choose your team under *Signing & Capabilities*.

Xcode downloads the Firebase iOS SDK (Swift Package Manager, 12.x) the first time; this takes a few minutes.
Without `GoogleService-Info.plist` the app still builds and runs, but the sign-in screen says sign-in isn't set up.

## Firebase setup

1. In the [Firebase console](https://console.firebase.google.com) add a project called **RoamPulse**
   (Google Analytics isn't needed). The free Spark plan is enough.
2. **Add app → iOS** with the bundle ID **`com.savishka.RoamPulse`**. Download `GoogleService-Info.plist`
   and drag it into the `RoamPulse/` folder in Xcode (target: RoamPulse). Skip the console's SDK and code steps.
3. **Authentication → Get started → Sign-in method → Email/Password → Enable.**
4. **Firestore Database → Create database**, Standard edition, location **asia-south1 (Mumbai)**
   (it can't be changed later), and start in **production mode**.
5. **Firestore Database → Rules**: replace everything with the contents of [`firestore.rules`](firestore.rules) and
   press **Publish**. Until then, Profile → Cloud backup shows "Firestore refused access".
6. Run the app, create an account, and check *Authentication → Users* and *Firestore → trips* in the console.

The API key in `GoogleService-Info.plist` only identifies the project; the security rules protect the data.
It is committed so the project builds for the marker. Optionally restrict the key to the bundle ID in
Google Cloud console → APIs & Services → Credentials.

## Project structure

```
RoamPulse/
├── RoamPulseApp.swift         App entry point, root view (onboarding / sign-in / lock / sheets), tab bar
├── AppDependencies.swift      Creates the services once and hands them to view models
├── Account/
│   ├── AppSession.swift       Who is signed in; opens that account's database and starts syncing
│   ├── AuthService.swift      AppUser, AuthService protocol, AuthError, AuthValidator, stand-ins
│   ├── FirebaseAuthService.swift Email/password accounts with Firebase Auth (only file importing it)
│   └── FirebaseBootstrap.swift Configures Firebase and Firestore's offline cache at launch
├── Sync/
│   ├── SyncService.swift      SyncService protocol, SyncStatus, NoSyncService
│   ├── SyncRecords.swift      Firestore document shapes, Trip ↔ records, change set, RemoteTripMirror
│   └── FirestoreSyncService.swift Uploads changes in batches, listens for changes from the cloud
├── Navigation.swift           AppRouter, pushed routes and sheets (builds each screen's view model)
├── Models/
│   ├── Trip.swift             Member, Trip, Activity, PackingItem, Expense, Payment, Balance…
│   └── Memory.swift           Memory, Landmark, Weather
├── Services/
│   ├── Clock.swift            "Now" behind a protocol (real clock in the app, fixed in tests)
│   ├── WeatherService.swift   Forecast behind a protocol (sample data until OpenWeatherMap)
│   ├── ItineraryPlanner.swift Time order, drag to reorder, move day, demanding-day rule
│   ├── PackingAdvisor.swift   Default packing list and weather suggestions
│   ├── ExpenseCalculator.swift Splits, balances, settle-up algorithm, 90% budget warning
│   └── ImageProcessor.swift   Shrinks picked photos to 2048 px + a 400 px thumbnail (ImageIO)
├── Data/
│   ├── RoamPulse.xcdatamodeld Core Data model (11 entities)
│   ├── PersistenceController.swift Core Data stack: one database per account, or in memory for tests
│   ├── TripRepository.swift   Repository protocol + in-memory version
│   ├── CoreDataTripRepository.swift Saves/loads with Core Data, converts entities ↔ structs
│   ├── TripStore.swift        Shared in-memory copy of the data; saves every change
│   └── SampleData.swift       Sample trips (dates relative to today), sample photos
├── ViewModels/                One view model per screen, mirroring Views/
├── Components/
│   ├── Theme.swift            Colours, gradient, formatters
│   ├── Components.swift       Cards, buttons, chips, avatars, photos, segmented tabs
│   └── TripCoverView.swift    A trip's own cover photo (from Core Data) or its sample photo, with a cache
├── Views/                     SwiftUI screens
└── Assets.xcassets
RoamPulseTests/                Swift Testing suites (run with ⌘U), plus Fakes.swift (fake auth and sync)
firestore.rules                Firestore security rules (paste into the console)
```

The project uses Xcode folder-synced groups, so any file added to these folders is picked up automatically.
See [ARCHITECTURE.md](ARCHITECTURE.md) for how the layers fit together.

## Current state

Increments 1–6a are done:

- **Architecture:** MVVM with a view model per screen; storage, time, weather, sign-in and sync sit behind
  protocols and are injected, so tests use fakes, an in-memory repository and a fixed clock.
- **Core Data:** trips with their members, itinerary, packing list, expenses and payments, plus journal memories
  and photos. Each signed-in account has its own database file. Trips can be created, edited and deleted
  (with confirmation) and are sorted into Active, Upcoming and Completed.
- **Itinerary, packing, expenses:** as before (drag to reorder, demanding days, suggestions, splits, settle-up).
- **Accounts (Firebase Auth):** onboarding → sign in / create account / reset password → the app. Stays signed in
  offline. Sign out on Profile.
- **Cloud backup (Cloud Firestore):** every trip change is uploaded; changes made on another device signed in to
  the same account appear automatically. Works offline and uploads later. Profile shows the sync status.
- **Cover photos:** pick your own photo for a trip. It is resized and saved in Core Data (not uploaded).

A new account starts with the sample trips (Settings → Load sample trips adds them again after deleting
everything). Weather is still sample data, and the journal, photo recognition, map, notifications and Face ID
are still the prototype screens; they come in later increments. Journal memories are never uploaded.

Photos and avatars live in `Assets.xcassets` (`Photos/` and `Avatars/`). Each `SamplePhoto` case loads the image set
with the same name, and avatars load `avatar_<name>`. Image sources and licences are listed in [CREDITS.md](CREDITS.md).
