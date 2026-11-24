//
//  RuleBasedAnalyzer.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The real (non-AI) analyzer. It runs every rule over the message, tidies
//  up the findings, and asks VerdictPolicy for the verdict.
//
//  WHY RULES FIRST
//  Rules are fast, work offline, never make things up, and every decision
//  can be explained by pointing at one line of code. They are also the
//  safety net: if the language model fails in Phase 3/4, the app falls
//  back to these.
//
//  TIDYING UP
//  - If two findings of the same kind overlap (e.g. "registration fee" and
//    "fee of Rs 499"), only the first is kept, so the card isn't repetitive.
//  - Reasons are sorted by where they appear in the message.
//

import Foundation

nonisolated struct RuleBasedAnalyzer: MessageAnalyzer {

    private let rules: [any ScamRule]

    init(rules: [any ScamRule] = RuleBasedAnalyzer.defaultRules) {
        self.rules = rules
    }

    static let defaultRules: [any ScamRule] = [
        UrgencyRule(),
        CredentialRequestRule(),
        PaymentRequestRule(),
        FeeForPrizeOrJobRule(),
        LinkRule(),
    ]

    func analyze(_ message: String) async throws -> AnalysisResult {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalyzerError.emptyMessage
        }
        let reasons = findReasons(in: message)
        return AnalysisResult(
            message: message,
            verdict: VerdictPolicy.verdict(for: reasons),
            reasons: reasons,
            source: .rules
        )
    }

    /// Runs every rule; no async needed. Handy for tests and for Phase 4.
    func findReasons(in message: String) -> [Reason] {
        let all = rules.flatMap { $0.findReasons(in: message) }
            .sorted { lhs, rhs in
                // Strong first so that, when two overlap, the strong one is kept.
                if lhs.strength != rhs.strength { return lhs.strength == .strong }
                return lhs.span.start < rhs.span.start
            }

        var kept: [Reason] = []
        for reason in all {
            let overlapsSameKind = kept.contains { other in
                other.category == reason.category
                    && reason.span.start < other.span.end
                    && other.span.start < reason.span.end
            }
            if !overlapsSameKind {
                kept.append(reason)
            }
        }
        return kept.sorted { $0.span.start < $1.span.start }
    }
}
