// Trains RoamPulse's landmark classifier with Create ML Components, then evaluates it on photos it has never seen.
//
// 1. Every photo is turned into 512 numbers by Apple's MobileCLIP image encoder, run through Vision
//    exactly as the app runs it. Training photos are also added mirrored (data augmentation).
// 2. A logistic regression classifier is trained on those numbers (transfer learning).
// 3. The confidence threshold is chosen from the validation set, then checked on the test set.
// 4. The classifier goes to RoamPulse/ML/LandmarkClassifier.mlpackage, the threshold to
//    RoamPulse/ML/LandmarkModel.json, and the results to EvaluationReport.md.
//
// Usage: swift train_model.swift     (run split_dataset.py first)

import CoreImage
import CoreML
import CreateMLComponents
import Foundation
import Vision

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let dataset = here.appending(path: "Dataset")
let appFolder = here.deletingLastPathComponent().appending(path: "RoamPulse/ML")
let encoderPackage = appFolder.appending(path: "MobileCLIPImageEncoder.mlpackage")
let otherLabel = "Other"
// Precision we want for photos labelled automatically. Below the threshold the app asks the user
let wantedPrecision = 0.95

struct Prediction {
    let truth: String
    let label: String
    let confidence: Double
    var isCorrect: Bool { truth == label }
}

func labels(in folder: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") }.sorted()
}

func photos(in folder: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "jpg" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

let encoder = try MLModel(contentsOf: MLModel.compileModel(at: encoderPackage))
let request = try CoreMLRequest(model: CoreMLModelContainer(model: encoder))

// The photo's 512 MobileCLIP numbers
func embedding(of image: CIImage) async throws -> MLShapedArray<Float> {
    let observation = try await request.perform(on: image).compactMap { $0 as? CoreMLFeatureValueObservation }.first
    guard let values = observation?.featureValue.shapedArrayValue(of: Float.self) else {
        throw CocoaError(.featureUnsupported)
    }
    return MLShapedArray(scalars: values.scalars, shape: [values.scalars.count])
}

func examples(_ set: String, mirrored: Bool = false) async throws -> [AnnotatedFeature<MLShapedArray<Float>, String>] {
    var result: [AnnotatedFeature<MLShapedArray<Float>, String>] = []
    for label in try labels(in: dataset.appending(path: set)) {
        for photo in try photos(in: dataset.appending(path: "\(set)/\(label)")) {
            guard let image = CIImage(contentsOf: photo, options: [.applyOrientationProperty: true]) else { continue }
            result.append(AnnotatedFeature(feature: try await embedding(of: image), annotation: label))
            if mirrored {
                let flipped = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
                result.append(AnnotatedFeature(feature: try await embedding(of: flipped), annotation: label))
            }
        }
    }
    return result
}

struct ThresholdResult {
    let threshold: Double
    let accepted: Int
    let correct: Int
    let landmarkPhotos: Int

    var precision: Double { accepted == 0 ? 1 : Double(correct) / Double(accepted) }
    // Share of real landmark photos labelled automatically and correctly
    var coverage: Double { landmarkPhotos == 0 ? 0 : Double(correct) / Double(landmarkPhotos) }
}

func thresholdResult(_ predictions: [Prediction], at threshold: Double) -> ThresholdResult {
    let accepted = predictions.filter { $0.label != otherLabel && $0.confidence >= threshold }
    return ThresholdResult(threshold: threshold, accepted: accepted.count, correct: accepted.filter(\.isCorrect).count,
                           landmarkPhotos: predictions.filter { $0.truth != otherLabel }.count)
}

func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }

// 1. Embeddings
print("Reading photos…")
let started = Date()
let training = try await examples("train", mirrored: true)
let validationSet = try await examples("validation")
let testSet = try await examples("test")

// 2. Train
let classes = Set(training.map(\.annotation))
let classifier = try await LogisticRegressionClassifier<Float, String>(labels: classes).fitted(to: training)

func predict(_ set: [AnnotatedFeature<MLShapedArray<Float>, String>]) async throws -> [Prediction] {
    var predictions: [Prediction] = []
    for example in set {
        let distribution = try await classifier.applied(to: example.feature)
        let label = distribution.mostLikelyLabel ?? otherLabel
        predictions.append(Prediction(truth: example.annotation, label: label, confidence: Double(distribution[label] ?? 0)))
    }
    return predictions
}

let trainingAccuracy = Double(try await predict(training).filter(\.isCorrect).count) / Double(training.count)
let validation = try await predict(validationSet)
let test = try await predict(testSet)
let minutes = Date().timeIntervalSince(started) / 60

// 3. Lowest threshold that reaches the wanted precision on the validation set
let thresholds = stride(from: 0.30, through: 0.95, by: 0.05).map { ($0 * 100).rounded() / 100 }
let validationResults = thresholds.map { thresholdResult(validation, at: $0) }
let chosen = validationResults.first { $0.precision >= wantedPrecision } ?? validationResults.max { $0.precision < $1.precision }!
let testAtThreshold = thresholdResult(test, at: chosen.threshold)

// 4. Save the classifier and the threshold for the app
let classifierURL = appFolder.appending(path: "LandmarkClassifier.mlpackage")
try? FileManager.default.removeItem(at: classifierURL)
try classifier.export(to: classifierURL)
let settings = ["confidenceThreshold": chosen.threshold]
try JSONEncoder().encode(settings).write(to: appFolder.appending(path: "LandmarkModel.json"))

// Report
let labelsSorted = classes.sorted()
let accuracy = { (set: [Prediction]) in Double(set.filter(\.isCorrect).count) / Double(max(set.count, 1)) }
let short = Dictionary(uniqueKeysWithValues: labelsSorted.map { label in
    // Initials for the matrix, e.g. "Nine Arch Bridge" -> "NAB"
    (label, String(label.split(separator: " ").compactMap { $0.first(where: \.isLetter) }))
})
var report = """
# Landmark model evaluation

Trained \(Date().formatted(date: .abbreviated, time: .shortened)) in \(String(format: "%.1f", minutes)) minutes.
Image features: Apple's MobileCLIP-S0 image encoder (512 numbers per photo), run through Vision.
Classifier: logistic regression trained with Create ML Components. Augmentation: every training photo
is also used mirrored.

## Data

| Class | Train | Validation | Test |
|---|---|---|---|

"""
for label in labelsSorted {
    let counts = [training.filter { $0.annotation == label }.count / 2,
                  validationSet.filter { $0.annotation == label }.count,
                  testSet.filter { $0.annotation == label }.count]
    report += "| \(label) | \(counts[0]) | \(counts[1]) | \(counts[2]) |\n"
}
report += """

All of one author's photos are in the same set, so near-duplicates can't inflate the test results.

## Accuracy

| | Accuracy |
|---|---|
| Training | \(percent(trainingAccuracy)) |
| Validation | \(percent(accuracy(validation))) |
| Test (unseen photos) | \(percent(accuracy(test))) |

## Test set, per class

| Class | Photos | Precision | Recall |
|---|---|---|---|

"""
for label in labelsSorted {
    let truePositives = test.filter { $0.truth == label && $0.label == label }.count
    let predicted = test.filter { $0.label == label }.count
    let actual = test.filter { $0.truth == label }.count
    report += "| \(label) | \(actual) | \(predicted == 0 ? "–" : percent(Double(truePositives) / Double(predicted))) | "
        + "\(actual == 0 ? "–" : percent(Double(truePositives) / Double(actual))) |\n"
}
report += "\n## Confusion matrix (test set)\n\nRows are the real landmark, columns what the model said.\n\n"
report += "| | " + labelsSorted.map { short[$0]! }.joined(separator: " | ") + " |\n"
report += "|---|" + labelsSorted.map { _ in "---" }.joined(separator: "|") + "|\n"
for truth in labelsSorted {
    let counts = labelsSorted.map { predicted in test.filter { $0.truth == truth && $0.label == predicted }.count }
    report += "| \(short[truth]!) " + counts.map { "| \($0 == 0 ? "·" : String($0)) " }.joined() + "|\n"
}
report += "\n" + labelsSorted.map { "\(short[$0]!) = \($0)" }.joined(separator: ", ") + "\n"
report += """

## Confidence threshold

A landmark is only labelled automatically when the model is at least this sure. Otherwise the app shows its
top three guesses and asks. The threshold is the lowest one that keeps automatic labels at \(percent(wantedPrecision))
precision or better on the validation set.

| Threshold | Validation precision | Validation landmark photos labelled automatically |
|---|---|---|

"""
for result in validationResults {
    let mark = result.threshold == chosen.threshold ? " **(chosen)**" : ""
    report += "| \(String(format: "%.2f", result.threshold))\(mark) | \(percent(result.precision)) | \(percent(result.coverage)) |\n"
}
report += """

Chosen threshold: **\(String(format: "%.2f", chosen.threshold))**. On the test set it gives \(percent(testAtThreshold.precision))
precision, and \(percent(testAtThreshold.coverage)) of landmark photos are labelled without asking.

"""
try report.write(to: here.appending(path: "EvaluationReport.md"), atomically: true, encoding: .utf8)
print("Test accuracy \(percent(accuracy(test))), threshold \(chosen.threshold)")
