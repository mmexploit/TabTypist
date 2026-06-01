import AppKit
@preconcurrency import Vision
import ScreenCaptureKit

// Captures a compact screenshot of the focused window around the input field and
// extracts text via on-device Vision OCR. Approach adapted from cotabby's
// WindowScreenshotService + ScreenTextExtractor:
//   • capture the focused window IN ISOLATION (desktopIndependentWindow) so other
//     windows can't occlude/clip the text,
//   • crop a field-centred band (field width + horizontal padding, a tall band above)
//     rather than the whole screen width,
//   • OCR with language correction OFF and a low minimumTextHeight so small chat text
//     is read in full instead of mangled ("Yeah" → "h").
//
// Screen Recording permission must be granted (optional — completions still work
// without it, just less context-aware).
final class VisualContextCapture: @unchecked Sendable {
    static let shared = VisualContextCapture()

    /// Character budget for OCR text injected into the prompt (keeps the tail, nearest the field).
    private static let maxChars = 1200
    /// Extra context captured left/right of the field, in display points.
    private static let horizontalPadding: CGFloat = 160
    /// Height of the band captured ABOVE the field, in display points.
    private static let verticalContextHeight: CGFloat = 800
    /// Downsample very large Retina captures before OCR to keep latency bounded.
    private static let maxImageDimension = 1600

    private init() {}

    // MARK: – Public API

    /// `fieldFrameCG` is the focused field's bounds in CG global coords (top-left origin),
    /// i.e. the raw AX `AXFrame`. `pid` identifies the focused app so we can capture its
    /// window in isolation. Returns nil if permission is missing or no text is found.
    func capture(pid: pid_t, fieldFrameCG: CGRect) async -> String? {
        guard CGPreflightScreenCaptureAccess() else {
            fputs("OCR: skipped — Screen Recording permission not granted\n", stderr)
            return nil
        }
        guard fieldFrameCG.width > 4 && fieldFrameCG.height > 4 else {
            fputs("OCR: skipped — invalid field frame \(fieldFrameCG)\n", stderr)
            return nil
        }
        guard let window = await focusedWindow(pid: pid) else {
            fputs("OCR: skipped — no on-screen window for pid \(pid)\n", stderr)
            return nil
        }

        let sourceRect = snapshotRect(fieldFrameCG: fieldFrameCG, windowFrame: window.frame)
        guard sourceRect.width > 20 && sourceRect.height > 20 else {
            fputs("OCR: skipped — crop too small \(sourceRect)\n", stderr)
            return nil
        }
        guard let image = await captureImage(window: window, sourceRect: sourceRect) else {
            fputs("OCR: skipped — ScreenCaptureKit returned no image\n", stderr)
            return nil
        }
        return await recogniseText(in: image)
    }

    // MARK: – Window discovery

    private func focusedWindow(pid: pid_t) async -> SCWindow? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true
        ) else { return nil }
        return content.windows.first(where: {
            $0.owningApplication?.processID == pid && $0.isActive && $0.isOnScreen
        }) ?? content.windows.first(where: {
            $0.owningApplication?.processID == pid && $0.isOnScreen
        })
    }

    // MARK: – Crop geometry (all CG/top-left coords)

    private func snapshotRect(fieldFrameCG: CGRect, windowFrame: CGRect) -> CGRect {
        let targetHeight = min(Self.verticalContextHeight, windowFrame.height)
        let targetWidth = min(fieldFrameCG.width + Self.horizontalPadding * 2, windowFrame.width)
        let proposedX = fieldFrameCG.minX - Self.horizontalPadding
        let proposedY = fieldFrameCG.minY - targetHeight   // band ABOVE the field (smaller y)
        // Clamp inside the window so ScreenCaptureKit doesn't fail or crop incorrectly.
        let clampedX = min(max(proposedX, windowFrame.minX), windowFrame.maxX - targetWidth)
        let clampedY = min(max(proposedY, windowFrame.minY), windowFrame.maxY - targetHeight)
        return CGRect(x: clampedX, y: clampedY, width: targetWidth, height: targetHeight).integral
    }

    // MARK: – Screen capture (ScreenCaptureKit)

    private func captureImage(window: SCWindow, sourceRect: CGRect) async -> CGImage? {
        let scale = backingScaleFactor(forCG: sourceRect)
        // sourceRect is global; desktopIndependentWindow wants window-local coords.
        let local = CGRect(
            x: sourceRect.minX - window.frame.minX,
            y: sourceRect.minY - window.frame.minY,
            width: sourceRect.width,
            height: sourceRect.height
        )
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.sourceRect = local
        config.width  = max(Int((local.width  * scale).rounded(.up)), 1)
        config.height = max(Int((local.height * scale).rounded(.up)), 1)
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Backing scale of the screen containing the crop's midpoint. `rect` is CG/top-left;
    /// convert its midpoint to AppKit (bottom-left) to test against NSScreen frames.
    private func backingScaleFactor(forCG rect: CGRect) -> CGFloat {
        let desktop = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let appKitMid = CGPoint(x: rect.midX, y: desktop.maxY - rect.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitMid) }) ?? NSScreen.main
        return screen?.backingScaleFactor ?? 2.0
    }

    // MARK: – OCR

    private func recogniseText(in image: CGImage) async -> String? {
        let prepared = downsampled(image)
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                // Reading order: top-to-bottom (bands), then left-to-right within a band.
                let lines = observations
                    .sorted {
                        if abs($0.boundingBox.minY - $1.boundingBox.minY) > 0.02 {
                            return $0.boundingBox.minY > $1.boundingBox.minY
                        }
                        return $0.boundingBox.minX < $1.boundingBox.minX
                    }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let joined = lines.joined(separator: "\n")
                // Keep the tail (nearest the field = most recent in a chat).
                let capped = joined.count <= Self.maxChars
                    ? joined
                    : String(joined.suffix(Self.maxChars))
                let flat = capped.replacingOccurrences(of: "\n", with: " | ")
                fputs("OCR: \(lines.count) lines, \(capped.count) chars: \(flat)\n", stderr)
                continuation.resume(returning: capped.isEmpty ? nil : capped)
            }
            // Accurate, no language correction (it mangles names/chat slang), and a low
            // minimum text height so small chat text is recognised in full.
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.008

            do {
                try VNImageRequestHandler(cgImage: prepared, options: [:]).perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Scale very large Retina captures down to a bounded dimension before OCR.
    private func downsampled(_ image: CGImage) -> CGImage {
        let largest = max(image.width, image.height)
        guard largest > Self.maxImageDimension else { return image }
        let scale = CGFloat(Self.maxImageDimension) / CGFloat(largest)
        let w = max(Int(CGFloat(image.width) * scale), 1)
        let h = max(Int(CGFloat(image.height) * scale), 1)
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}
