import Foundation
import Vision
import ImageIO
import WerkstattCore

struct OCRInput: Sendable {
    let photoID: String
    let url: URL
}
struct OCRObservation: Sendable {
    let photoID: String
    let text: String
    var mayContainPrivateLabel: Bool {
        let value = text.lowercased()
        return ["serial number", "seriennummer", "imei", "s/n:", "s/n "].contains { value.contains($0) }
    }
}
enum VisionScanner {
    static func scan(_ photos: [OCRInput]) async throws -> [OCRObservation] {
        try await Task.detached(priority: .userInitiated) {
            var result: [OCRObservation] = []
            for photo in photos {
                try Task.checkCancellation()
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["de-DE", "en-US"]
                request.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(url: photo.url)
                try handler.perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                result.append(OCRObservation(photoID: photo.photoID, text: text))
            }
            return result
        }.value
    }
}
