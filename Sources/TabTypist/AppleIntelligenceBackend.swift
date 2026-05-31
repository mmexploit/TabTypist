import Foundation

// FoundationModels ships with Xcode 26+ SDK.  Wrap the entire file so the
// project still compiles against older SDKs (deployment target: macOS 14).
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
final class AppleIntelligenceBackend: Sendable {

    /// Whether the system language model is ready for use.
    static var isAvailable: Bool {
        FoundationModels.SystemLanguageModel.default.isAvailable
    }

    /// Generate a text completion for `prefix` using the on-device model.
    /// Applies the completion normaliser before returning.
    ///
    /// - Parameters:
    ///   - prefix: Text the user has typed so far.
    ///   - maxTokens: Approximate token budget (best-effort; Apple controls the actual limit).
    ///   - appName: Display name of the focused app (for context injection).
    /// - Returns: Normalised completion text, or `nil` if nothing useful was generated.
    static func complete(
        prefix: String,
        maxTokens: Int = 30,
        appName: String = ""
    ) async -> String? {
        guard isAvailable else { return nil }

        let lengthHint: String = {
            switch maxTokens {
            case ..<14: return "Write a very short completion (3–7 words)."
            case 14..<22: return "Write a short completion (7–12 words)."
            default:     return "Write a completion of up to 20 words."
            }
        }()

        let appHint = appName.isEmpty ? "" : " The user is typing in \(appName)."

        let systemPrompt = """
        You complete text inline. \(lengthHint)\(appHint) \
        Output ONLY the continuation — no explanation, no leading spaces if the prefix \
        already ends with a space, no quotes. Stop at the first sentence boundary.
        """

        let userPrompt = "Continue this text: \(prefix)"

        do {
            let session = FoundationModels.LanguageModelSession(instructions: systemPrompt)
            let response = try await session.respond(to: userPrompt)
            let raw = response.content
            guard !raw.isEmpty else { return nil }
            return normalise(raw, prefix: prefix)
        } catch {
            return nil
        }
    }

    // ── Normaliser ────────────────────────────────────────────────────────────
    //
    // Mirrors the Rust normalize_completion logic so the Swift-side Apple
    // Intelligence path produces the same output quality as the llama path.

    private static func normalise(_ raw: String, prefix: String) -> String {
        var text = stripThinkBlocks(raw)
        text = text
            .replacingOccurrences(of: "<|im_start|>assistant", with: "")
            .replacingOccurrences(of: "<|im_start|>", with: "")
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "\r", with: "")

        text = suppressEcho(text, prefix: prefix)

        if prefix.last?.isWhitespace == true {
            text = String(text.drop(while: { $0.isWhitespace }))
        }

        return truncateAtSentenceBoundary(text)
    }

    private static func stripThinkBlocks(_ text: String) -> String {
        var result = text
        while let start = result.range(of: "<think>") {
            if let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
                result.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                result = String(result[..<start.lowerBound])
                break
            }
        }
        return result
    }

    private static func suppressEcho(_ completion: String, prefix: String) -> String {
        let fragment = prefix
            .components(separatedBy: CharacterSet(charactersIn: "\n.!?"))
            .last ?? prefix

        let fragmentWords = fragment.split(separator: " ").map(String.init)
        guard !fragmentWords.isEmpty else { return completion }

        let cap = min(fragmentWords.count, 15)
        let fWords = Array(fragmentWords.suffix(cap))
        let cWords = completion.split(separator: " ").map(String.init)
        guard !cWords.isEmpty else { return completion }

        for n in stride(from: fWords.count, through: 1, by: -1) {
            guard cWords.count >= n else { continue }
            let suffix = Array(fWords.suffix(n))
            let prefix = Array(cWords.prefix(n))
            let matches = zip(suffix, prefix).allSatisfy {
                $0.lowercased() == $1.lowercased()
            }
            if matches {
                if n == fWords.count { return "" }
                let stripped = cWords.dropFirst(n).joined(separator: " ")
                let leadingSpace = completion.hasPrefix(" ") ? " " : ""
                return leadingSpace + stripped
            }
        }
        return completion
    }

    private static func truncateAtSentenceBoundary(_ text: String) -> String {
        var result = text
        for ch in [".", "!", "?", "\n"] {
            if let r = result.range(of: ch) {
                let truncated = String(result[..<r.upperBound]).trimmingCharacters(in: .whitespaces)
                if !truncated.isEmpty { result = truncated; break }
            }
        }
        return result.trimmingCharacters(in: .init(charactersIn: " \n\t"))
    }
}
#endif // canImport(FoundationModels)
