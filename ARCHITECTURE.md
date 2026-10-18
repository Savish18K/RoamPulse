# RoamPulse architecture (Increments 1–6a)

## Layers

```
View  ──calls──▶  ViewModel  ──calls──▶  TripStore  ──calls──▶  TripRepository  ──▶  Core Data (one file per account)
(SwiftUI)         (screen logic)          (shared data)  │       (protocol)
                       │                                 └──▶  SyncService (protocol)  ◀──▶  Cloud Firestore
                       │
                       └──uses──▶  Services: ItineraryPlanner, ExpenseCalculator, PackingAdvisor, ImageProcessor,
                                    WeatherService (protocol), Clock (protocol)

AppSession ──uses──▶ AuthService (protocol) ──▶ Firebase Auth
    └── on sign-in: opens the account's TripRepository in TripStore and starts SyncService
```

| Layer | Files | Job |
|---|---|---|
| Models | `Models/Trip.swift`, `Models/Memory.swift` | Plain structs (`Trip`, `Activity`, `Expense`…). No Core Data, no SwiftUI state. |
| Services | `Services/*.swift` | Rules as pure functions (data in, data out), plus the `Clock` and `WeatherService` protocols. |
| Data | `Data/*.swift` | `TripRepository` protocol, the Core Data version, and `TripStore`. |
| Account | `Account/*.swift` | `AuthService` protocol + Firebase version, `AppSession` (signed in/out). |
| Sync | `Sync/*.swift` | `SyncService` protocol + Firestore version; pure record/diff code in `SyncRecords.swift`. |
| View models | `ViewModels/*.swift` | One per screen. Work out what the screen shows and handle its buttons. |
| Views | `Views/*.swift` | Layout only. They read the view model and call its methods. |

**Why structs above Core Data?** Views and tests never touch `NSManagedObject`. `CoreDataTripRepository` is the
only file that knows about Core Data, so swapping storage (or testing without it) only touches one place.

## Following one tap through the app

Ticking "Passport" on the packing screen:

1. `PackingView` button → `viewModel.toggle(item)`
2. `PackingViewModel.toggle` → `store.updateTrip(tripID) { $0.packing[i].isPacked.toggle() }`
3. `TripStore.updateTrip` copies the trip, applies the change and calls `repository.save(trip)`.
   Only if saving works does it replace the trip in `trips` (so the screen never shows unsaved data).
4. `CoreDataTripRepository.save` finds the `TripEntity`, syncs its child rows to match the struct
   (`sync(...)`: update rows with the same id, insert new ones, delete removed ones), then `context.save()`.
   If saving fails it calls `context.rollback()` and throws, and the store shows an alert.
5. `TripStore` is `@Observable`, so every view that read that trip redraws.

## Dependency injection

`AppDependencies` (created once in `RoamPulseApp`) builds the real services:
`FirebaseAuthService`, `FirestoreSyncService`, `SystemClock`, `MockWeatherService`, the `TripStore` and the
`AppSession`. It first calls `FirebaseBootstrap.configure()`; if there is no `GoogleService-Info.plist` (or unit
tests are running) it uses `UnavailableAuthService` and `NoSyncService` instead, so the app never crashes.
The store starts empty; `AppSession` gives it the signed-in account's `CoreDataTripRepository(accountID:)`.
`Navigation.swift` (`AppDestinations`, `SheetContent`) and `MainTabView` are the only places screens are created.
They pass the services into each view model's `init` (constructor injection).

Tests build the same view models with an `InMemoryTripRepository` and a `FixedClock`, so results never depend on
the real date or the database. Only things that touch the outside world (storage, time, network) are protocols.
The rules (`ItineraryPlanner`, `ExpenseCalculator`, `PackingAdvisor`) are pure, so they are tested directly.

Views keep their view model in `@State`, so SwiftUI creates it once and keeps it while the screen is shown.

## Core Data model (`Data/RoamPulse.xcdatamodeld`)

| Entity | Key attributes | Relationships |
|---|---|---|
| TripEntity | id, name, destination, startDate, endDate, budget, coverName, remindersOn | members, activities, packingItems, expenses, payments (ordered, cascade); memories (cascade); forecast (cascade); coverImage (cascade) |
| MemberEntity | id, name, initials, colorHex, isMe | trip; paidExpenses, shares, paymentsMade, paymentsReceived, memories (nullify) |
| ActivityEntity | id, day, minutes, title, place, effort, isOutdoor, isDone | trip |
| PackingItemEntity | id, name, category, isPacked | trip |
| ExpenseEntity | id, title, amount, category, splitMethod, date | trip, paidBy → Member, shares (ordered, cascade) |
| ExpenseShareEntity | amount | expense, member |
| PaymentEntity | id, amount, date | trip, payer → Member, receiver → Member |
| MemoryEntity | id, title, date, day, transcript, mood, sentiment, placeTags/sceneTags (Transformable `[String]`), landmark… | trip, people → Member (ordered), photos (ordered, cascade) |
| PhotoEntity | id, assetName, fileName, createdAt | memory |
| StoredImageEntity | id, imageData, thumbnailData (Binary, *Allows External Storage*), pixelWidth/Height, createdAt | trip (inverse of TripEntity.coverImage) |
| ForecastCacheEntity | location, fetchedAt, payload (JSON) | trip. Used in Increment 7 (weather). |

- **Cascade** from Trip means deleting a trip removes everything in it (tested in `deletingATripDeletesEverythingInIt`).
- **Ordered** relationships keep the order of the arrays (e.g. the packing list order).
- The "Day" in the plan's "Day/Activity" is stored as `ActivityEntity.day` (an Int) instead of a separate entity:
  a day has no data of its own, so a number is enough.
- Members are saved per trip, so deleting one trip can't break another.
- Classes (`TripEntity`…) are generated by Xcode (Codegen: Class Definition).
- Tests use `PersistenceController(inMemory: true)` (store at `/dev/null`). The model is loaded once (`static let model`).
- **One database per account:** `Application Support/Accounts/<firebase uid>/RoamPulse.sqlite`. Two people
  signing in on one iPhone never see each other's data, and signing out deletes nothing.

## Accounts (`Account/`)

1. Launch: `FirebaseBootstrap.configure()`, then `AppSession.start()` asks the `AuthService` to report the user.
   Firebase keeps the user in the keychain, so a returning user is signed in straight away, even offline.
2. `RootView` shows onboarding → `AuthView` (signed out) → `MainTabView` (signed in), from `session.state`.
3. Signing in or up: `AuthViewModel` checks the form with `AuthValidator`, then calls `AppSession`.
   `AppSession.openAccount` opens the account's database in the store, starts sync, and for a **new** account
   adds the sample trips (after sync starts, so they are uploaded).
4. Firebase errors are turned into `AuthError` (plain messages). With email enumeration protection, a wrong
   email and a wrong password are the same error, so the app says "The email or password is incorrect."
5. Signing out stops sync and empties the store. The account's database stays for next time.

## Cloud sync (`Sync/`)

Firestore layout (one document per item, so two devices editing different expenses don't clash):

```
trips/{tripId}                    TripRecord  (name, dates, budget, cover, ownerUID, memberUIDs, isDeleted, updatedAt)
trips/{tripId}/members/{id}       MemberRecord   (userUID = the account of the person who is "me")
trips/{tripId}/activities/{id}    ActivityRecord
trips/{tripId}/packing/{id}       PackingRecord
trips/{tripId}/expenses/{id}      ExpenseRecord  (amounts in whole cents; shares inside)
trips/{tripId}/payments/{id}      PaymentRecord
```

- **Up:** `TripStore` calls `sync.tripDidChange(from: old, to: new)` after every successful save.
  `TripChangeSet.writes` compares the two versions and returns only what changed (ticking one packing item = one
  write). `FirestoreSyncService` sends them as a `WriteBatch`. Firestore puts the batch in its **offline cache**
  immediately and uploads it when online, so the app needs no upload queue of its own.
- **Down:** one listener on `trips where memberUIDs contains my uid`, plus five listeners per trip. Each report
  goes into a `RemoteTripMirror`. The cloud's copy is saved locally (`TripStore.applyRemote`) only when:
  every part has arrived (otherwise a half-arrived trip would wipe local expenses), and no part still has
  **pending writes** from this iPhone (those are already in Core Data; we wait for the server to confirm).
- `applyRemote` never calls sync, so a change from the cloud isn't uploaded again (no loop). It keeps the
  local `coverImageID`, because cover photos aren't synced.
- **Deleting** a trip writes a tombstone (`isDeleted = true`) instead of removing the document, so a device
  that was offline still learns about it. The rules forbid hard deletes.
- **First answer from the server:** trips that exist locally but not in the cloud are uploaded.
- **Conflicts:** last write to reach the server wins, per document.
- **Security rules** (`firestore.rules`): only accounts in `memberUIDs` can read or write a trip and its items;
  nobody can change `ownerUID`. Items use `getAfter()` so a new trip and its items can be written in one batch.
- **Not synced, on purpose:** journal memories, voice recordings, transcripts and photos (privacy promise:
  on-device intelligence; also Firestore documents are limited to 1 MB and Cloud Storage needs the paid plan).
- **Increment 6b (sharing)** will add `ownerUID`/`memberUIDs` to `Trip`, so a member's uploads keep the owner.

## Photos

- **Sample photos** (`Assets.xcassets/Photos`, 1200 px, 130–550 KB) stay in the asset catalog. They are part of
  the app, the same for everyone, and the asset catalog is the fastest way to load them. Copying them into a
  database would duplicate them for every account and gain nothing.
- **Photos the user picks** (a trip's cover now; journal photos later) are user data, so they go in Core Data:
  1. `PhotosPicker` gives the app only the chosen photo (no photo library permission needed).
  2. `ImageProcessor.prepare` (ImageIO) makes a 2048 px JPEG and a 400 px thumbnail **without decoding the full
     12–48 MP original**, applies the rotation, and drops metadata such as GPS.
  3. Saved as `StoredImageEntity` with *Allows External Storage*: Core Data keeps big blobs as files next to
     the database, small ones inside SQLite. Cascade from the trip deletes the photo with the trip.
  4. `TripCoverView` reads the bytes on the main thread (Core Data), decodes them in the background, and keeps
     the decoded image in an `NSCache` so lists don't decode it again.

## The rules

### Demanding-day rule (`ItineraryPlanner.intensity(of:)`)
Points: low 1, moderate 2, high 4. **≥ 8 → Demanding**, **≥ 5 or any high-effort activity → Moderate**, otherwise Easy.
The prototype's Day 3 is hike (4) + spice garden (1) + falls (2) + dinner (1) = 8, so it's demanding. Two demanding days
in a row get an extra warning.

### Drag to reorder (`ItineraryPlanner.reorder`)
The list is always in time order, so dragging keeps the day's **time slots** and hands them out in the new order.
Dragging the 15:00 falls above the 06:00 hike gives the falls 06:00 and moves the hike to the next slot.
Dropping an activity on a day tab, or using **Move to another day** in the menu, changes its day but keeps its time.
The long-press menu also has Move earlier/later, so VoiceOver users can reorder without dragging.

### Splits and settle-up (`ExpenseCalculator`)
- All maths is in **whole cents** (`Int`), so `0.1 + 0.2` problems can't happen and balances add up to exactly 0.
- Equal split: leftover cents go to the first people (100 ÷ 3 = 33.34, 33.33, 33.33).
- Custom split: the shares must add up to the total before Save is enabled.
- Balance = paid − share of every expense, + payments made − payments received.
- **Settle-up (greedy):** repeatedly match the person who owes the most with the person owed the most and pay the
  smaller amount. Each payment clears at least one person, so it needs at most n − 1 payments. Ties go in name order.
  Prototype numbers: Suu → Savishka 11,600; Samee → Savishka 3,300; Samee → Suresha 1,100.
- Tapping **Settle** saves a `Payment`, so balances and the plan update and survive a restart. Undo deletes it.
- **Budget warning:** at 90% or more (compared as whole numbers, so exactly 90% counts), and over budget above 100%.
  A budget of 0 means "no budget" and never warns.

### Packing suggestions (`PackingAdvisor.suggestions`)
From the forecast for the trip's days: rain ≥ 60% → camera rain cover, quick-dry towel; high ≥ 30° → sun hat, water
bottle; low ≤ 12° → warm fleece. From the plan: a high-effort activity → hiking shoes, energy snacks.
Items already on the list are left out.

## Tests (`RoamPulseTests`, Swift Testing, ⌘U)

101 tests in seven suites:

| Suite | Covers |
|---|---|
| ExpenseCalculatorTests | equal/custom splits, balances, payments, settle-up (prototype numbers, clears everything, ≤ n − 1, ties, empty trip, solo traveller), budget warning, zero budget |
| ItineraryPlannerTests | demanding-day rule and its boundaries, time order, reorder, move day, clamping, clashes |
| TripStoreTests | Active/Upcoming/Completed sorting, status at trip edges, end before start, saving, failed save rollback, view models (trip form, drag/drop, settle up, custom split, number pad) |
| CoreDataRepositoryTests | round trip of a full trip and a memory, updates don't duplicate rows, cascade delete, memory without a trip |
| AccountTests | email/password/name checks, sign in/up/out with a fake auth service, sample trips only for new accounts, separate databases per account, form messages, password reset |
| SyncTests | Trip ↔ Firestore records round trip, cents, "me" per account, list order, missing members, minimal change sets, tombstones, mirror waits for all parts and pending writes, store ↔ sync wiring, no re-upload of cloud changes |
| ImageTests | resizing (big, small, not a photo), cover saved/replaced/removed/deleted in Core Data, no orphan photos, the Create Trip form's photo |

## Questions you might be asked

- **Why is `TripStore` `@MainActor`?** It uses Core Data's `viewContext`, which must be used on the main thread,
  and it drives the UI.
- **What happens if saving fails?** The repository rolls back the context and throws; the store keeps the old value
  and sets `errorMessage`, which `RootView` (or the open sheet) shows as an alert.
- **Why `@Observable` instead of `ObservableObject`?** SwiftUI only redraws views that read the property that changed,
  and no `@Published` is needed. It needs iOS 17, which is the deployment target.
- **How does the "NOW" line move?** `TimelineView(.everyMinute)` redraws the schedule every minute, and the view model
  reads the time from the injected `Clock`.
- **Where does the sample data come from?** `SampleData.make(now:)`, added when a new account is created
  (`AppSession.openAccount`). Dates are relative to today, so Hill Country Explorer is always on Day 2.
- **Why does Core Data stay when Firestore has an offline cache too?** Core Data is the app's database (platform
  feature, relationships, journal and photos that are never uploaded). Firestore is only the backup/sync channel.
- **Why not wait for `batch.commit` before saving?** Offline, its completion only runs when the phone reconnects.
  The change is saved in Core Data first and Firestore's cache uploads it later.
- **How do you avoid upload loops?** Only `addTrip`/`updateTrip`/`deleteTrip` call sync. Cloud changes use
  `applyRemote`, which saves to the repository directly.
- **Why one Core Data file per account instead of an `ownerUID` column?** No query can forget the filter, so data
  can never leak between accounts, and signing out needs no clean-up.
- **What if Firebase isn't configured?** `FirebaseBootstrap.configure()` returns false; `UnavailableAuthService`
  explains on the sign-in screen. Unit tests also run this way, so they never touch the network.
- **What would you improve?** Run Core Data saves on a background context for big data sets; only write changed
  attributes; replace `MockWeatherService` with OpenWeatherMap and `ForecastCacheEntity`; purge old tombstones;
  App Check to stop other apps using the Firebase project.
