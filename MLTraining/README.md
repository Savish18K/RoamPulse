# Landmark model

RoamPulse recognises famous Sri Lankan landmarks in journal photos with a classifier trained here with
Create ML Components. The app runs two Core ML models on the iPhone, so photos never leave the device:

1. `RoamPulse/ML/MobileCLIPImageEncoder.mlpackage`: Apple's MobileCLIP-S0 image encoder, run with Vision.
   It turns a photo into 512 numbers that describe what's in it.
2. `RoamPulse/ML/LandmarkClassifier.mlpackage`: my classifier, trained on my reviewed photos, which turns
   those 512 numbers into a landmark (or Other). Its confidence threshold is in `LandmarkModel.json`.

## Classes

12 landmarks and **Other** (everyday travel photos that show none of them):

Nine Arch Bridge, Sigiriya Rock Fortress, Temple of the Tooth, Galle Fort Lighthouse, Lotus Tower,
Dambulla Cave Temple, Ruwanwelisaya, Sri Pada (Adam's Peak), Nallur Kandaswamy Kovil, Coconut Tree Hill,
Gal Vihara, Gangaramaya Temple.

The first ten are the ones in the proposal; the last two were added because there were enough
openly licensed photos of them and they appear in the sample trips.

## Steps

| Step | Command | What it does |
|---|---|---|
| 1. Collect | `python3 collect_dataset.py` | Downloads openly licensed photos (Wikimedia Commons and Openverse) into `Raw/<label>/`, and records the source page, author and licence of every photo in `dataset_log.csv`. |
| 2. Review | `swift contact_sheet.swift "<label>"` then `python3 exclude.py "<label>" "<reason>" <numbers>` | Makes numbered contact sheets in `Sheets/` so every photo is checked by eye (running it again later only shows photos added since). Photos that don't show the landmark (views from the top, museum objects, animals, other buildings, old prints) go into `excluded.csv` with the reason. Excluded photos don't count towards a class, so running step 1 again tops it back up. |
| 3. Split | `python3 split_dataset.py` | Copies the reviewed photos into `Dataset/train`, `validation` and `test` (about 70/15/15). All photos by one author go into the same set, so near-duplicates can't make the test results look better than they are. |
| 4. Train and evaluate | `swift train_model.swift` | Runs every photo through MobileCLIP with Vision, trains the classifier, evaluates it on the validation and test sets, picks the confidence threshold, saves the classifier into the app and writes `EvaluationReport.md`. Takes a few minutes. |

`Raw/` and `Dataset/` aren't committed (they're large and can be rebuilt with steps 1–3).
`dataset_log.csv`, `excluded.csv`, `split_summary.json` and `EvaluationReport.md` are.

## Training

- Transfer learning: MobileCLIP was trained by Apple on hundreds of millions of image and caption pairs, so its
  512 numbers already capture buildings, landscapes and statues well. Only a logistic regression classifier is
  trained on top, so a few dozen photos per landmark are enough.
- Why MobileCLIP and not Create ML's default (Vision's Scene Print)? Scene Print is built into the operating
  system and fails in the iOS 27 Simulator ("Could not create inference context"), so the app couldn't be
  demonstrated or unit tested there. MobileCLIP ships as a normal Core ML model, so it runs in the Simulator too.
  It's in Core ML's newer package format, which `MLImageClassifier` can't use as an extractor, so the classifier
  is trained with Create ML Components instead.
- Data augmentation: every training photo is also used mirrored.
- The photos the app itself uses for each landmark (see `CREDITS.md`) are kept out of the dataset, so the
  unit test can check the model on photos it has never seen.

## Confidence threshold

The model always gives its best guess, even for photos of something it doesn't know. To avoid saving
wrong labels, the app only labels a photo by itself when the model's confidence is at least the
threshold. Otherwise it shows the top three guesses and the user chooses (or says it isn't a landmark).

The threshold is the lowest one that keeps automatic labels at least 95% correct on the **validation**
set. It's then checked on the **test** set and saved in the model's metadata (`confidenceThreshold`),
which the app reads when it loads the model. See `EvaluationReport.md` for the numbers.

## Limits

- Coconut Tree Hill (10 photos) and Sri Pada (16) have few openly licensed photos that actually show them, so
  they're the least reliable classes. Ravana Falls was dropped for the same reason (only 3 usable photos).

- Only these 13 landmarks are known. Anything else falls back to Vision's general scene tags and the
  user's own choice.
- Photos come from public sources, so they're mostly daytime tourist views. Night, close-up or
  unusual angles are recognised less reliably.
- More landmarks can be added by adding them to `landmarks.json` and `LandmarkCatalogue.swift` and
  running the steps again.
