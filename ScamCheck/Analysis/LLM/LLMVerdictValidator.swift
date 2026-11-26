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
//  STRICTER EVIDENCE CHECKS (added after the first evaluation run, where the
//  AI flagged 17 of 20 genuine messages, often "quoting" whole innocent
//  sentences; see WRONG_ANSWERS.md). AI evidence must meet the same bar the
//  rules already meet:
//  - a quote must be a short, specific phrase (at most 12 words)
//  - a "credential request" quote can't be a warning ("Do NOT share your OTP")
//  - a "suspicious link" / "sender-link mismatch" quote must contain a link,
//    and that link must not be an official one (amazon.in, *.bank.in, ...)
//
//  EVIDENCE RULE (precision first)
//  If the model flags the message but none of its reasons survive, the
//  verdict becomes "Looks fine" with a note. The app never shows a warning
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
        var notes: [String] = []
        if verdict != .looksFine && accepted.isEmpty {
            finalVerdict = .looksFine
            notes.append("The AI flagged this message but couldn't point to specific words that hold up, so it isn't treated as a warning.")
        }

        let result = AnalysisResult(
            message: message,
            verdict: finalVerdict,
            reasons: accepted.sorted { $0.span.start < $1.span.start },
            source: .llm,
            confidence: answer.confidence,
            hiddenReasonCount: rejected.count,
            notes: notes
        )
        return ValidatedLLMAnswer(result: result, rejectedReasons: rejected)
    }

    private struct Why: Error { let text: String }

    /// Evidence must be a specific phrase, not a whole sentence.
    static let maxQuoteWords = 12

    private static func check(_ llmReason: LLMReason, in message: String) -> Result<Reason, Why> {
        guard let category = ReasonCategory(rawValue: llmReason.category) else {
            return .failure(Why(text: "unknown category \"\(llmReason.category)\""))
        }
        let quote = cleaned(llmReason.quote)
        guard !quote.isEmpty else {
            return .failure(Why(text: "empty quote"))
        }
        let wordCount = quote.split(whereSeparator: { $0.isWhitespace }).count
        guard wordCount <= maxQuoteWords else {
            return .failure(Why(text: "quote too long to be specific evidence (\(wordCount) words)"))
        }
        let explanation = llmReason.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reason = Reason(
            category: category,
            quote: quote,
            explanation: explanation.isEmpty ? category.title : explanation,
            in: message,
            caseInsensitive: true,
            strength: .weak,   // Strength isn't used for AI reasons; the model gives its own verdict.
            origin: .ai
        ) else {
            return .failure(Why(text: "quote not found in message: \"\(llmReason.quote)\""))
        }
        if let problem = categoryProblem(reason, in: message) {
            return .failure(Why(text: problem))
        }
        return .success(reason)
    }

    /// Category-specific sanity checks, matching what the rules require.
    private static func categoryProblem(_ reason: Reason, in message: String) -> String? {
        switch reason.category {
        case .credentialRequest:
            guard let lower = message.index(message.startIndex, offsetBy: reason.span.start, limitedBy: message.endIndex),
                  let upper = message.index(lower, offsetBy: reason.span.length, limitedBy: message.endIndex)
            else { return nil }
            if Negation.isNegated(lower..<upper, in: message) {
                return "credential quote is a warning, not a request: \"\(reason.quote)\""
            }
            return nil
        case .suspiciousLink, .senderLinkMismatch:
            let links = LinkExtractor.links(in: reason.quote)
            guard !links.isEmpty else {
                return "link reason without a link: \"\(reason.quote)\""
            }
            let allOfficial = links.allSatisfy { link in
                !link.isIPAddress
                    && (KnownBrands.owner(of: link.registrableDomain) != nil
                        || link.registrableDomain.hasSuffix(".bank.in"))
            }
            return allOfficial ? "link is an official website: \"\(reason.quote)\"" : nil
        default:
            return nil
        }
    }

    /// Removes spaces and quote marks the model may have wrapped around the quote.
    static func cleaned(_ quote: String) -> String {
        quote.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
