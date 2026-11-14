import Vision
import CoreGraphics

struct MatchResult: Equatable {
    var isMatch: Bool
    /// Smallest feature-print distance to any reference photo (0 = identical).
    var distance: Float?
    var threshold: Float?
    var matchedWords: [String]
    var note: String?

    static func failure(_ note: String) -> MatchResult {
        MatchResult(isMatch: false, distance: nil, threshold: nil, matchedWords: [], note: note)
    }

    var details: String {
        var parts: [String] = []
        if let distance, let threshold {
            parts.append(String(format: "Visual difference %.2f (limit %.2f)", distance, threshold))
        }
        if !matchedWords.isEmpty {
            parts.append("Label words matched: " + matchedWords.prefix(5).joined(separator: ", "))
        }
        if let note { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

/// Compares a new photo with the reference photos using Apple's on-device Vision framework:
/// 1. an image "feature print" (overall visual similarity), and
/// 2. text recognition (words printed on the box, e.g. the medicine name).
/// Nothing leaves the phone.
enum ObjectMatcher {

    static func compare(candidate: CGImage?, references: [CGImage], referenceWords: [String]?, strictness: Strictness) -> MatchResult {
        guard let candidate else { return .failure("Couldn't read the photo.") }
        guard !references.isEmpty else { return .failure("No reference photos saved for this alarm.") }

        do {
            let candidatePrint = try featurePrint(for: candidate)
            let referencePrints = references.compactMap { try? featurePrint(for: $0) }
            guard !referencePrints.isEmpty else { return .failure("Couldn't analyse the reference photos.") }

            var best = Float.greatestFiniteMagnitude
            for reference in referencePrints {
                var distance: Float = 0
                try candidatePrint.computeDistance(&distance, to: reference)
                best = min(best, distance)
            }

            // If the reference photos differ a lot from each other (different angles),
            // allow a little more tolerance, up to a cap.
            var spread: Float = 0
            for i in referencePrints.indices {
                for j in referencePrints.indices where j > i {
                    var distance: Float = 0
                    if (try? referencePrints[i].computeDistance(&distance, to: referencePrints[j])) != nil {
                        spread = max(spread, distance)
                    }
                }
            }
            let base = strictness.baseThreshold
            let threshold = min(base + 0.15, max(base, spread + 0.05))

            let wanted = Set(referenceWords ?? Array(words(inAll: references)))
            let found = words(in: candidate)
            let hits = found.intersection(wanted).sorted()

            let visualMatch = best <= threshold
            let textAssisted = hits.count >= 2 && best <= threshold + strictness.textBonus
            let textOnly = strictness != .strict && hits.count >= 4

            return MatchResult(
                isMatch: visualMatch || textAssisted || textOnly,
                distance: best,
                threshold: threshold,
                matchedWords: hits,
                note: nil
            )
        } catch {
            return .failure("Image analysis failed: \(error.localizedDescription)")
        }
    }

    static func featurePrint(for image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        // Look at the middle of the photo, where the person is told to put the object.
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw NSError(domain: "PillSnap", code: 1, userInfo: [NSLocalizedDescriptionKey: "No feature print produced"])
        }
        return observation
    }

    static func words(inAll images: [CGImage]) -> Set<String> {
        images.reduce(into: Set<String>()) { result, image in
            result.formUnion(words(in: image))
        }
    }

    static func words(in image: CGImage) -> Set<String> {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
        return tokenize(text)
    }

    static func tokenize(_ text: String) -> Set<String> {
        let parts = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { word in
            word.count >= 4
                && word.rangeOfCharacter(from: .letters) != nil
                && !stopWords.contains(word)
        })
    }

    /// Words printed on almost every medicine box, so they say nothing about *which* box it is.
    private static let stopWords: Set<String> = [
        "tablet", "tablets", "capsule", "capsules", "each", "contains", "store", "below",
        "keep", "reach", "sight", "children", "dose", "doses", "daily", "take", "with",
        "water", "food", "warning", "read", "leaflet", "pharmacy", "pharmacist", "only",
        "medicine", "film", "coated", "before", "after", "pack", "blister", "batch",
        "expiry", "date", "label", "directions", "use", "used", "this", "that", "your",
        "from", "more", "than", "hours", "adults", "years", "over", "under", "doctor"
    ]
}
