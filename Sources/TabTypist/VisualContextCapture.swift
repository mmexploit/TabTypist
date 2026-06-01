import AppKit
import Vision
import ScreenCaptureKit

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

        let primaryScreen = NSScreen.screens.first?.frame ?? .zero
        let screenH = primaryScreen.height

        // inputFrame is in Cocoa coords (origin bottom-left, y-up). ScreenCaptureKit's
        // sourceRect is in the display's coord space (origin TOP-left, y-down). Convert:
        // a Cocoa y maps to top-left y as (screenH - y). The region ABOVE the field runs
        // from the screen top (top-left y = 0) down to the field's TOP edge, which in
        // Cocoa is inputFrame.maxY, i.e. top-left y = screenH - inputFrame.maxY.
        let regionHeight = screenH - inputFrame.maxY
        guard regionHeight > 20 else { return nil }

        let sourceRect = CGRect(
            x: 0,
            y: 0,
            width: primaryScreen.width,
            height: regionHeight
        )

        guard let image = await captureScreenRect(sourceRect) else { return nil }
        return await recogniseText(in: image)
    }

    // MARK: – Screen capture (ScreenCaptureKit)

    /// `sourceRect` is already in the display's top-left coordinate space.
    private func captureScreenRect(_ sourceRect: CGRect) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = sourceRect
            // 2× for Retina sharpness so OCR reads small chat text reliably.
            config.width  = max(1, Int(sourceRect.width) * 2)
            config.height = max(1, Int(sourceRect.height) * 2)
            config.capturesAudio = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            return nil
        }
    }

    // MARK: – OCR

    private func recogniseText(in image: CGImage) async -> String? {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                // Vision returns observations in no guaranteed order. Sort top-to-bottom
                // (boundingBox origin is bottom-left, so higher minY = higher on screen)
                // so the proximity trim's tail is the text closest to the input field.
                let ordered = observations.sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                let lines = ordered.compactMap { $0.topCandidates(1).first?.string }
                let raw = lines.joined(separator: "\n")
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
