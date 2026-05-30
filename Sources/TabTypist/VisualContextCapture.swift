import AppKit
import Vision

// Captures the screen region ABOVE the focused text field and extracts text via
// on-device Vision OCR.  The result is trimmed to the context budget and injected
// into the completion prompt as additional context.
//
// Screen Recording permission must be granted by the user (optional — completions
// still work without it, they are just less context-aware).
final class VisualContextCapture: @unchecked Sendable {
    static let shared = VisualContextCapture()

    // Strategy B: proximity trim — keep text nearest to the field bottom.
    // Strategy C (model distillation) is gated behind a feature flag.
    private static let strategyC = UserDefaults.standard.bool(forKey: "visualContext.strategyC")

    /// Maximum character budget for OCR output injected into the prompt.
    private static let maxChars = 400

    private init() {}

    // MARK: – Public API

    /// Capture OCR text from the region above `inputFrame` (Cocoa coords).
    /// Returns nil if Screen Recording permission is not granted, the frame is
    /// invalid, or no text is found.
    func capture(above inputFrame: CGRect) async -> String? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard inputFrame.width > 10 && inputFrame.height > 10 else { return nil }

        // Capture region: full-width strip from screen top down to inputFrame top.
        let primaryScreen = NSScreen.screens.first?.frame ?? .zero
        let captureY = inputFrame.minY           // bottom of region in Cocoa
        let captureH = primaryScreen.height - captureY
        guard captureH > 20 else { return nil }

        let captureRect = CGRect(
            x: primaryScreen.minX,
            y: primaryScreen.minY + captureY,    // flip to screen coords
            width: primaryScreen.width,
            height: captureH
        )

        guard let image = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else { return nil }

        return await recogniseText(in: image, above: inputFrame)
    }

    // MARK: – OCR

    private func recogniseText(in image: CGImage, above inputFrame: CGRect) async -> String? {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let raw = lines.joined(separator: " ")
                let trimmed = VisualContextCapture.trim(raw)
                continuation.resume(returning: trimmed.isEmpty ? nil : trimmed)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: – Strategy B: proximity trim

    /// Keep the trailing `maxChars` characters — closest to the text field, most relevant.
    private static func trim(_ text: String) -> String {
        if strategyC {
            // Strategy C: truncate from the start (would be model distillation in full impl).
            return text.count <= maxChars ? text : String(text.prefix(maxChars))
        }
        // Strategy B default: keep the tail (nearest to the caret).
        if text.count <= maxChars { return text }
        let start = text.index(text.endIndex, offsetBy: -maxChars)
        return String(text[start...])
    }
}
