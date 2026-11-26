//
//  AnalysisResult.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The shared vocabulary of the app: the data every analyzer returns.
//  Whether the answer comes from the mock, the rules, or a language model,
//  it is always an AnalysisResult made of a Verdict plus a list of Reasons.
//
//  WHY IT LOOKS LIKE THIS
//  - Each Reason carries the exact quote from the message AND where that quote
//    sits (a TextSpan). The UI highlights using the span, so it can never
//    highlight a different occurrence of the same words by mistake.
//  - Reasons can only be built through an initializer that checks the quote
//    really is in the message. This is the first line of defence against a
//    model inventing evidence (Phase 4 relies on it).
//  - Types are marked `nonisolated` because this project makes code run on the
//    main thread by default. These are plain data types with no UI, so they
//    should be usable from anywhere, including tests.
//

import Foundation

/// The three answers the app can give.
nonisolated enum Verdict: String, Codable, CaseIterable, Sendable {
    case likelyScam
    case suspicious
    case looksFine

    /// The wording shown to the user.
    var title: String {
        switch self {
        case .likelyScam: "Likely scam"
        case .suspicious: "Suspicious"
        case .looksFine: "Looks fine"
        }
    }
}

/// The kinds of warning sign the app knows about.
/// Matches the checks planned for Phase 2.
nonisolated enum ReasonCategory: String, Codable, CaseIterable, Sendable {
    case urgencyOrThreat
    case credentialRequest
    case paymentRequest
    case suspiciousLink
    case senderLinkMismatch
    case feeForPrizeOrJob
    case other

    var title: String {
        switch self {
        case .urgencyOrThreat: "Pressure or threats"
        case .credentialRequest: "Asks for OTP, PIN or password"
        case .paymentRequest: "Asks you to pay or approve a payment"
        case .suspiciousLink: "Suspicious link"
        case .senderLinkMismatch: "Sender and link don't match"
        case .feeForPrizeOrJob: "Fee for a prize or job"
        case .other: "Other warning sign"
        }
    }

    /// SF Symbol name used next to the reason.
    var symbolName: String {
        switch self {
        case .urgencyOrThreat: "clock.badge.exclamationmark"
        case .credentialRequest: "key.fill"
        case .paymentRequest: "indianrupeesign.circle"
        case .suspiciousLink: "link"
        case .senderLinkMismatch: "person.crop.circle.badge.questionmark"
        case .feeForPrizeOrJob: "gift"
        case .other: "questionmark.circle"
        }
    }
}

/// How much a single warning sign counts on its own.
/// - strong: rarely appears in genuine messages (e.g. "share the OTP").
/// - weak: common in scams but also in real messages (e.g. a short link).
/// The verdict rules in VerdictPolicy.swift combine these.
nonisolated enum SignalStrength: String, Codable, Sendable {
    case strong
    case weak
}

/// A position inside the message, counted in Characters (what a person sees
/// as one letter or one emoji), not bytes. "start" is 0-based.
nonisolated struct TextSpan: Codable, Hashable, Sendable {
    let start: Int
    let length: Int

    var end: Int { start + length }

    /// The text this span covers in `message`, or nil if the span does not fit.
    func substring(in message: String) -> Substring? {
        guard start >= 0, length >= 0, end <= message.count else { return nil }
        let lower = message.index(message.startIndex, offsetBy: start)
        let upper = message.index(lower, offsetBy: length)
        return message[lower..<upper]
    }
}

/// One piece of evidence: what kind of warning sign, the exact words that
/// triggered it, where they are, and a plain-language explanation.
nonisolated struct Reason: Identifiable, Hashable, Sendable {
    let id: UUID
    let category: ReasonCategory
    /// Exact text copied from the message (same capitalisation as the message).
    let quote: String
    /// Where `quote` sits in the message.
    let span: TextSpan
    let explanation: String
    let strength: SignalStrength

    /// Builds a Reason by searching for `quote` in the message. Returns nil if `quote` is not in
    /// `message`, so a Reason with invented evidence cannot exist.
    ///
    /// - Parameter caseInsensitive: match "otp" against "OTP". The stored
    ///   quote is always the text as written in the message.
    init?(
        category: ReasonCategory,
        quote: String,
        explanation: String,
        in message: String,
        caseInsensitive: Bool = false,
        strength: SignalStrength = .weak
    ) {
        guard let found = QuoteLocator.locate(quote, in: message, caseInsensitive: caseInsensitive) else {
            return nil
        }
        self.id = UUID()
        self.category = category
        self.quote = found.exactText
        self.span = found.span
        self.explanation = explanation
        self.strength = strength
    }

    /// Builds a Reason from a range a rule has already matched. Used by the
    /// rules, because they know exactly WHERE they matched (searching for
    /// the text again could land on an earlier copy of the same words).
    /// Returns nil if the range does not belong to `message`.
    init?(
        category: ReasonCategory,
        strength: SignalStrength,
        range: Range<String.Index>,
        in message: String,
        explanation: String
    ) {
        guard range.lowerBound >= message.startIndex,
              range.upperBound <= message.endIndex,
              !range.isEmpty
        else { return nil }
        self.id = UUID()
        self.category = category
        self.quote = String(message[range])
        self.span = TextSpan(
            start: message.distance(from: message.startIndex, to: range.lowerBound),
            length: message.distance(from: range.lowerBound, to: range.upperBound)
        )
        self.explanation = explanation
        self.strength = strength
    }
}

/// Which analyzer produced a result. Shown in the UI so the app is honest
/// about where an answer came from.
nonisolated enum AnalysisSource: String, Codable, Sendable {
    case mock
    case rules
    case llm
    case combined
}

/// The full answer for one message.
nonisolated struct AnalysisResult: Identifiable, Hashable, Sendable {
    let id: UUID
    /// The message exactly as analysed. Reason spans point into this string.
    let message: String
    let verdict: Verdict
    let reasons: [Reason]
    let source: AnalysisSource
    /// 0...1 when the analyzer provides one (the LLM does).
    let confidence: Double?
    /// How many reasons were thrown away because they failed validation
    /// (e.g. the AI quoted words that aren't in the message). Shown to the
    /// user so the app is honest about it.
    let hiddenReasonCount: Int

    init(
        message: String,
        verdict: Verdict,
        reasons: [Reason],
        source: AnalysisSource,
        confidence: Double? = nil,
        hiddenReasonCount: Int = 0
    ) {
        self.id = UUID()
        self.message = message
        self.verdict = verdict
        self.reasons = reasons
        self.source = source
        self.confidence = confidence
        self.hiddenReasonCount = hiddenReasonCount
    }
}
