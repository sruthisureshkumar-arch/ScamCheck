//
//  LLMVerdictValidator.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The gate every language-model answer must pass before the user sees it.
//  The model can be wrong, so nothing it says is trusted until checked.
//
//  WHOLE-ANSWER CHECKS (fail → the answer is rejected, an error is thrown)
//  - verdict must be one of likelyScam / suspicious / looksFine
//  - confidence must be a real number from 0 to 1
//
//  PER-REASON CHECKS (fail → that reason is dropped and recorded)
//  - category must be one we know
//  - quote must not be empty
//  - quote must really appear in the message. Models often "tidy up" quotes;
//    we allow different capitalisation and strip surrounding quote marks,
//    but the words themselves must be there. The stored quote is always the
//    text as written in the message.
//
//  EVIDENCE RULE (precision first)
//  If the model says "Likely scam" but none of its reasons survive, the
//  verdict is lowered to "Suspicious". The app never shows a strong verdict
//  without evidence the user can see.
//
//  This is plain Swift with no model calls, so it is fully unit tested.
//

import Foundation

nonisolated enum LLMValidationError: Error, Equatable {
    case unknownVerdict(String)
    case confidenceOutOfRange(Double)
}

nonisolated struct RejectedReason: Equatable, Sendable {
    let reason: LLMReason
    let why: String
}

nonisolated struct ValidatedLLMAnswer: Sendable {
    let result: AnalysisResult
    let rejectedReasons: [RejectedReason]
}

nonisolated enum LLMVerdictValidator {

    static func validate(_ answer: LLMVerdict, for message: String) throws(LLMValidationError) -> ValidatedLLMAnswer {
        guard let verdict = Verdict(rawValue: answer.verdict) else {
            throw .unknownVerdict(answer.verdict)
        }
        guard answer.confidence.isFinite, (0...1).contains(answer.confidence) else {
            throw .confidenceOutOfRange(answer.confidence)
        }

        var accepted: [Reason] = []
        var rejected: [RejectedReason] = []

        for llmReason in answer.reasons {
            switch check(llmReason, in: message) {
            case .success(let reason): accepted.append(reason)
            case .failure(let why): rejected.append(RejectedReason(reason: llmReason, why: why.text))
            }
        }

        var finalVerdict = verdict
        if verdict == .likelyScam && accepted.isEmpty {
            finalVerdict = .suspicious
        }

        let result = AnalysisResult(
            message: message,
            verdict: finalVerdict,
            reasons: accepted.sorted { $0.span.start < $1.span.start },
            source: .llm,
            confidence: answer.confidence,
            hiddenReasonCount: rejected.count
        )
        return ValidatedLLMAnswer(result: result, rejectedReasons: rejected)
    }

    private struct Why: Error { let text: String }

    private static func check(_ llmReason: LLMReason, in message: String) -> Result<Reason, Why> {
        guard let category = ReasonCategory(rawValue: llmReason.category) else {
            return .failure(Why(text: "unknown category \"\(llmReason.category)\""))
        }
        let quote = cleaned(llmReason.quote)
        guard !quote.isEmpty else {
            return .failure(Why(text: "empty quote"))
        }
        let explanation = llmReason.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reason = Reason(
            category: category,
            quote: quote,
            explanation: explanation.isEmpty ? category.title : explanation,
            in: message,
            caseInsensitive: true,
            strength: .weak   // Strength isn't used for AI reasons; the model gives its own verdict.
        ) else {
            return .failure(Why(text: "quote not found in message: \"\(llmReason.quote)\""))
        }
        return .success(reason)
    }

    /// Removes spaces and quote marks the model may have wrapped around the quote.
    static func cleaned(_ quote: String) -> String {
        quote.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
