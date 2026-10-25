import CoreML
import Foundation
import Vision

// Behind a protocol so the journal form can be tested without the model
protocol LandmarkRecognizing: Sendable {
    func recognize(_ imageData: Data) async throws -> RecognitionResult
}

enum LandmarkRecognitionError: LocalizedError {
    case modelUnavailable

    var errorDescription: String? {
        "The landmark model couldn't be loaded on this iPhone."
    }
}

// Two Core ML models, all on the iPhone:
// 1. Apple's MobileCLIP image encoder (run with Vision) turns the photo into 512 numbers.
// 2. My classifier, trained with Create ML on my landmark photos, turns those numbers into a landmark.
// Vision's built-in classifier adds general scene tags (beach, temple, food…)
actor VisionLandmarkRecognizer: LandmarkRecognizing {
    private var models: (encoder: CoreMLRequest, classifier: LandmarkClassifier)?
    private var threshold = RecognitionResult.defaultThreshold

    // Loaded the first time a photo is recognised, then reused
    private func loadModels() throws -> (encoder: CoreMLRequest, classifier: LandmarkClassifier) {
        if let models { return models }
        do {
            let encoder = try MobileCLIPImageEncoder(configuration: MLModelConfiguration()).model
            let loaded = (encoder: CoreMLRequest(model: try CoreMLModelContainer(model: encoder)),
                          classifier: try LandmarkClassifier(configuration: MLModelConfiguration()))
            // Chosen on the validation set when the classifier was trained (see MLTraining/)
            if let url = Bundle.main.url(forResource: "LandmarkModel", withExtension: "json"),
               let settings = try? JSONDecoder().decode([String: Double].self, from: Data(contentsOf: url)) {
                threshold = settings["confidenceThreshold"] ?? threshold
            }
            models = loaded
            return loaded
        } catch {
            throw LandmarkRecognitionError.modelUnavailable
        }
    }

    func recognize(_ imageData: Data) async throws -> RecognitionResult {
        let (encoder, classifier) = try loadModels()
        let observation = try await encoder.perform(on: imageData)
            .compactMap { $0 as? CoreMLFeatureValueObservation }
            .first
        guard let embedding = observation?.featureValue.shapedArrayValue(of: Float.self) else {
            throw LandmarkRecognitionError.modelUnavailable
        }
        let features = MLMultiArray(MLShapedArray(scalars: embedding.scalars, shape: [embedding.scalars.count]))
        let output = try await classifier.prediction(input: LandmarkClassifierInput(features: features))
        let landmarks = output.targetProbability.map { (name: $0.key, confidence: $0.value) }

        // Scene tags are a bonus, so a failure there doesn't lose the landmark
        var sceneRequest = ClassifyImageRequest()
        Self.useCPUInSimulator(&sceneRequest)
        let scenes = (try? await sceneRequest.perform(on: imageData)) ?? []
        return RecognitionResult(labels: landmarks,
                                 scenes: scenes.map { (name: $0.identifier, confidence: Double($0.confidence)) },
                                 threshold: threshold)
    }

    // Vision's built-in classifier can't start on the Simulator's GPU ("Failed to create espresso
    // context"), so there it runs on the CPU. A real iPhone uses the default
    private static func useCPUInSimulator<Request: VisionRequest>(_ request: inout Request) {
        #if targetEnvironment(simulator)
        for (stage, devices) in request.supportedComputeStageDevices {
            if let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        #endif
    }
}
