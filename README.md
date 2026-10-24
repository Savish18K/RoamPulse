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

**Whenever `firestore.rules` changes (it did for shared trips), paste it in and Publish again.**

## OpenWeatherMap setup

1. Sign up at [openweathermap.org](https://home.openweathermap.org/users/sign_up) (free) and copy your key from
   *API keys*. New keys can take up to 2 hours to start working.
2. Open `RoamPulse/OpenWeatherMap.plist` and replace `PASTE_YOUR_KEY_HERE` with the key.

Without a key the app shows built-in sample weather, and the Weather screen says so.

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
├── Account/AppLock.swift       Face ID / Touch ID app lock (LocalAuthentication)
├── Sync/
│   ├── Sharing.swift          Invite codes, TripInvite, SharingError, withTimeout
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
│   ├── ImageProcessor.swift   Shrinks picked photos to 2048 px + a 400 px thumbnail (ImageIO)
│   ├── Weather/               OpenWeatherMap client, ForecastBuilder, OpenWeatherMapService (cache + offline)
│   ├── Reminders/             ReminderPlanner (which notifications) and ReminderService (UserNotifications)
│   └── Voice/                 AudioRecorder (AVFoundation), Transcriber (Speech), JournalAnalyzer (Natural Language),
│                              VoiceJournalService (the pipeline), RecordingFiles (where audio is kept)
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

Increments 1–14 are done:

- **Architecture:** MVVM with a view model per screen; storage, time, weather, sign-in, sync, notifications and
  Face ID sit behind protocols and are injected, so tests use fakes, an in-memory repository and a fixed clock.
- **Core Data:** each signed-in account has its own database (trips, itinerary, packing, expenses, payments,
  memories, cover photos, cached forecasts).
- **Accounts (Firebase Auth):** sign in, create account, reset password, change name, sign out, delete account
  (password check → cloud data removed → account deleted → database on the iPhone deleted).
- **Cloud backup (Firestore):** every trip change is uploaded; works offline and uploads later.
- **Shared trips:** *Trip → ⋯ → Invite Friends* makes an 8-character code; a friend enters it in
  *Trips → Join Trip*, says which member they are, and both phones then see each other's changes.
  Someone it was shared with can leave the trip; only the owner can delete it for everyone.
- **Weather (OpenWeatherMap):** current weather and the 5-day / 3-hour forecast, cached per trip for offline use.
  Each outdoor activity is checked against its 3-hour step: rain, storms and heat get a warning naming the time
  window and a drier time that day. Destinations are searched as you type in Create Trip.
- **Reminders (local notifications):** packing reminder the evening before, a reminder before each activity,
  and weather alerts when a new forecast puts today's or tomorrow's plans at risk. Edited, moved and deleted
  activities update their reminders. Permission is only asked when a reminder is turned on.
- **App lock (Face ID / Touch ID, passcode fallback):** locks on launch and after the chosen time in the
  background; hides the app in the app switcher; turning it on or off needs Face ID.
- **Settings & Profile:** real account details, notification options, app lock, real permission statuses,
  theme, export of all data as JSON, delete all trips, delete account.
- **Home dashboard:** four states — a trip today (plan, weather, budget, latest memory, quick actions), a trip
  coming up (countdown and "get ready" checklist), all trips finished (recap and "where to next?"), no trips
  (welcome with Create, Join or sample trips). Every card has an empty or error state.
- **Journal:** write memories with text, up to 10 photos (resized, stored in Core Data), who was there, a mood,
  and the activity they belong to (which can be ticked off as visited). Edit, delete, filter by trip.
- **Insights:** search everything written, places, people and landmarks (matches highlighted, suggestions from
  your own memories); a timeline by day; mood per day. Tapping a place or person on a memory opens the search.
- **Statistics:** trips, days, places, memories, landmarks, spending by category (donut chart) and by trip
  (stacked bar chart), for this year or all time.

- **Voice journal (AVFoundation + Speech + Natural Language, all on the iPhone):** Record Memory starts
  recording with a live level meter; the memory is saved at once, then written down on the device and read
  for places, people and mood, and linked to the activity it's about. Unsupported languages or refused
  permissions keep the recording and offer Try Again / Type It Myself. Recordings play back in the memory.

Landmark recognition and the map are still to come (Increments 15–16; the photo-recognition prototype
screens are kept in `PhotosView.swift`).
Journal memories, voice notes and photos are never uploaded.

## Testing on the Simulator

- **Voice journal:** allow the Simulator to use your Mac's microphone (macOS asks once), tap Record Memory,
  speak, Stop, Save. Allow speech recognition when asked. In the Simulator the older on-device recogniser is
  used (`SpeechAnalyzer` needs a real iPhone); both run on the device.
- **Face ID:** *Features → Face ID → Enrolled*, then *Matching Face* / *Non-matching Face* when the app asks.
- **Notifications:** add an activity a few minutes ahead with *Before activities* set to 15 min, then press ⌘⇧H.
- **Offline:** turn off the Mac's Wi-Fi; the Weather screen shows the saved forecast with an offline banner.
- **Sharing:** sign in with two accounts on two simulators (e.g. iPhone 17 and iPhone Air).

Photos and avatars live in `Assets.xcassets` (`Photos/` and `Avatars/`). Each `SamplePhoto` case loads the image set
with the same name, and avatars load `avatar_<name>`. Image sources and licences are listed in [CREDITS.md](CREDITS.md).
