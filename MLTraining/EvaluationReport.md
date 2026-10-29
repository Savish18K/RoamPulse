# Landmark model evaluation

Trained 25 Oct 2026 at 14:55 in 0.1 minutes.
Image features: Apple's MobileCLIP-S0 image encoder (512 numbers per photo), run through Vision.
Classifier: logistic regression trained with Create ML Components. Augmentation: every training photo
is also used mirrored.

## Data

| Class | Train | Validation | Test |
|---|---|---|---|
| Coconut Tree Hill | 7 | 2 | 1 |
| Dambulla Cave Temple | 45 | 10 | 10 |
| Gal Vihara | 45 | 10 | 9 |
| Galle Fort Lighthouse | 56 | 12 | 12 |
| Gangaramaya Temple | 21 | 5 | 4 |
| Lotus Tower | 21 | 5 | 4 |
| Nallur Kandaswamy Kovil | 30 | 7 | 6 |
| Nine Arch Bridge | 67 | 15 | 14 |
| Other | 105 | 23 | 22 |
| Ruwanwelisaya | 50 | 11 | 10 |
| Sigiriya Rock Fortress | 28 | 6 | 6 |
| Sri Pada (Adam's Peak) | 11 | 3 | 2 |
| Temple of the Tooth | 44 | 9 | 9 |

Every class was split by author (the smallest has 7 authors), so all of one author's photos are in the same set and near-duplicates can't inflate the test results.

## Accuracy

| | Accuracy |
|---|---|
| Training | 100.0% |
| Validation | 91.5% |
| Test (unseen photos) | 89.9% |

## Test set, per class

| Class | Photos | Precision | Recall |
|---|---|---|---|
| Coconut Tree Hill | 1 | 0.0% | 0.0% |
| Dambulla Cave Temple | 10 | 100.0% | 100.0% |
| Gal Vihara | 9 | 100.0% | 100.0% |
| Galle Fort Lighthouse | 12 | 100.0% | 100.0% |
| Gangaramaya Temple | 4 | 66.7% | 50.0% |
| Lotus Tower | 4 | 100.0% | 75.0% |
| Nallur Kandaswamy Kovil | 6 | 85.7% | 100.0% |
| Nine Arch Bridge | 14 | 100.0% | 100.0% |
| Other | 22 | 72.0% | 81.8% |
| Ruwanwelisaya | 10 | 100.0% | 100.0% |
| Sigiriya Rock Fortress | 6 | 100.0% | 100.0% |
| Sri Pada (Adam's Peak) | 2 | 100.0% | 50.0% |
| Temple of the Tooth | 9 | 100.0% | 77.8% |

Coconut Tree Hill (1 test photo), Gangaramaya Temple (4 test photos), Lotus Tower (4 test photos), Sri Pada (Adam's Peak) (2 test photos) have too few test photos for their precision and recall to mean much. The overall test accuracy is the more reliable figure.

## Confusion matrix (test set)

Rows are the real landmark, columns what the model said.

| | CTH | DCT | GV | GFL | GT | LT | NKK | NAB | O | R | SRF | SPAP | TotT |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CTH | · | · | · | · | · | · | · | · | 1 | · | · | · | · |
| DCT | · | 10 | · | · | · | · | · | · | · | · | · | · | · |
| GV | · | · | 9 | · | · | · | · | · | · | · | · | · | · |
| GFL | · | · | · | 12 | · | · | · | · | · | · | · | · | · |
| GT | · | · | · | · | 2 | · | · | · | 2 | · | · | · | · |
| LT | · | · | · | · | · | 3 | · | · | 1 | · | · | · | · |
| NKK | · | · | · | · | · | · | 6 | · | · | · | · | · | · |
| NAB | · | · | · | · | · | · | · | 14 | · | · | · | · | · |
| O | 2 | · | · | · | 1 | · | 1 | · | 18 | · | · | · | · |
| R | · | · | · | · | · | · | · | · | · | 10 | · | · | · |
| SRF | · | · | · | · | · | · | · | · | · | · | 6 | · | · |
| SPAP | · | · | · | · | · | · | · | · | 1 | · | · | 1 | · |
| TotT | · | · | · | · | · | · | · | · | 2 | · | · | · | 7 |

CTH = Coconut Tree Hill, DCT = Dambulla Cave Temple, GV = Gal Vihara, GFL = Galle Fort Lighthouse, GT = Gangaramaya Temple, LT = Lotus Tower, NKK = Nallur Kandaswamy Kovil, NAB = Nine Arch Bridge, O = Other, R = Ruwanwelisaya, SRF = Sigiriya Rock Fortress, SPAP = Sri Pada (Adam's Peak), TotT = Temple of the Tooth

## Confidence threshold

A landmark is only labelled automatically when the model is at least this sure. Otherwise the app shows its
top three guesses and asks. The threshold is the lowest one that keeps automatic labels at 95.0%
precision or better on the validation set.

| Threshold | Validation precision | Validation landmark photos labelled automatically |
|---|---|---|
| 0.30 | 93.7% | 93.7% |
| 0.35 | 93.7% | 93.7% |
| 0.40 | 93.7% | 93.7% |
| 0.45 | 94.7% | 93.7% |
| 0.50 | 94.7% | 93.7% |
| 0.55 | 94.7% | 93.7% |
| 0.60 **(chosen)** | 95.7% | 92.6% |
| 0.65 | 95.6% | 91.6% |
| 0.70 | 95.6% | 91.6% |
| 0.75 | 95.6% | 90.5% |
| 0.80 | 95.5% | 89.5% |
| 0.85 | 96.6% | 88.4% |
| 0.90 | 96.5% | 87.4% |

Chosen threshold: **0.60**, saved as `confidenceThreshold` in
`RoamPulse/ML/LandmarkModel.json`, which the app reads when it loads the model. On the test set it gives 97.5%
precision, and 90.8% of landmark photos are labelled without asking.
