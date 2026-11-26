//
//  LLMVerdict.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The exact shape of answer we want from a language model:
//    { "reasons": [ {category, quote, explanation} ], "verdict": "...", "confidence": 0.0–1.0 }
//
//  TWO WAYS IN, ONE TYPE
//  1. On-device (Apple Foundation Models): `@Generable` tells the framework
//     to force the model to fill in this exact structure ("guided
//     generation"), so the model cannot return broken JSON.
//  2. Any other model that returns JSON text: `Codable` lets JSONDecoder
//     turn that text into the same type (see `decode(json:)` below).
//
//  WHY STRINGS, NOT OUR Verdict/ReasonCategory ENUMS
//  The model's answer is untrusted. Keeping its raw strings here means
//  LLMVerdictValidator decides what is acceptable, in one place, and can
//  report exactly what was wrong.
//
//  WHY THIS PROPERTY ORDER
//  The model fills properties in the order they're declared. Asking for the
//  evidence (reasons) BEFORE the verdict nudges it to decide based on what it
//  actually found, rather than deciding first and inventing reasons after.
//
//  ⚠️ API CHECK: `@Generable`, `@Guide(description:_:)` and `.anyOf` are from
//  Apple's Foundation Models docs (checked Nov 2026). If Xcode rejects one,
//  check the current documentation for its exact spelling.
//

import Foundation
import FoundationModels

@Generable(description: "A scam check of one text message")
nonisolated struct LLMVerdict: Codable, Equatable, Sendable {

    @Guide(description: "Warning signs found in the message. Empty if there are none.")
    var reasons: [LLMReason]

    @Guide(description: "Overall verdict", .anyOf(["likelyScam", "suspicious", "looksFine"]))
    var verdict: String

    @Guide(description: "How sure you are, from 0.0 (guessing) to 1.0 (certain)")
    var confidence: Double
}

@Generable(description: "One warning sign")
nonisolated struct LLMReason: Codable, Equatable, Sendable {

    @Guide(description: "Kind of warning sign", .anyOf([
        "urgencyOrThreat", "credentialRequest", "paymentRequest",
        "suspiciousLink", "senderLinkMismatch", "feeForPrizeOrJob", "other",
    ]))
    var category: String

    @Guide(description: "The exact words copied from the message, unchanged")
    var quote: String

    @Guide(description: "One short, plain sentence explaining the risk")
    var explanation: String
}

// MARK: - Decoding JSON text (for models without guided generation, and tests)

nonisolated enum LLMDecodeError: Error, Equatable {
    /// The text wasn't JSON, or didn't match the expected shape.
    /// `detail` is a readable description, suitable to send back to the
    /// model when retrying (Phase 4).
    case invalid(detail: String)
}

extension LLMVerdict {

    /// Models often wrap JSON in extra text or ```json fences. This keeps
    /// only the part from the first "{" to the last "}". If there's no such
    /// part, the text is returned unchanged and decoding will report it.
    nonisolated static func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end
        else { return text }
        return String(text[start...end])
    }

    /// Turns JSON text into an LLMVerdict, with a clear message when it fails.
    nonisolated static func decode(json: String) throws(LLMDecodeError) -> LLMVerdict {
        guard let data = json.data(using: .utf8) else {
            throw .invalid(detail: "The answer was not text.")
        }
        do {
            return try JSONDecoder().decode(LLMVerdict.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw .invalid(detail: "Missing field \"\(key.stringValue)\".")
        } catch let DecodingError.typeMismatch(type, context) {
            throw .invalid(detail: "Field \"\(context.codingPath.map(\.stringValue).joined(separator: "."))\" should be \(type).")
        } catch let DecodingError.valueNotFound(_, context) {
            throw .invalid(detail: "Field \"\(context.codingPath.map(\.stringValue).joined(separator: "."))\" is empty.")
        } catch {
            throw .invalid(detail: "The answer is not valid JSON.")
        }
    }
}
