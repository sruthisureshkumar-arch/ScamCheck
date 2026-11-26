//
//  CombinationPolicy.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The single place that decides the verdict when BOTH the rules and the AI
//  have given an answer. Plain Swift, fully unit tested.
//
//  THE POLICY (version 2: precision first; the rules decide whether to warn)
//
//    Likely scam  ← rules AND AI both say Likely scam
//                 ← OR the rules found 2+ different kinds of STRONG sign
//    Suspicious   ← the rules flagged it (Suspicious / Likely scam) but the
//                   bar for Likely scam isn't met
//    Looks fine   ← the rules found nothing to warn about, WHATEVER THE AI
//                   SAYS. Anything the AI noticed is still listed under
//                   "Worth noticing", with a note.
//
//  WHY VERSION 2 (see WRONG_ANSWERS.md, 2026-11-26)
//  Version 1 showed "Suspicious" whenever rules and AI disagreed. On the
//  first evaluation the on-device AI flagged 17 of 20 genuine messages, so
//  every one of those became a "Suspicious" warning: Combined scored
//  precision 0.53, F0.5 0.58. The AI is now a second opinion that can
//  CONFIRM a scam (and explain it), but it can't raise a warning alone.
//
//  REASONS
//  Rules' reasons come first (they're deterministic). An AI reason is added
//  unless it overlaps a rules reason of the same kind (same evidence twice).
//  Every reason keeps its origin label (rules / AI).
//

import Foundation

nonisolated struct Combination: Sendable {
    let result: AnalysisResult
    /// True when the rules' verdict and the AI's (effective) verdict differ.
    let disagreed: Bool
}

nonisolated enum CombinationPolicy {

    static let strongEvidenceKinds = 2

    static func combine(rules: AnalysisResult, ai: AnalysisResult) -> Combination {
        var notes: [String] = []

        // Step 0: an AI flag without surviving evidence doesn't count.
        var aiVerdict = ai.verdict
        if aiVerdict != .looksFine && ai.reasons.isEmpty {
            aiVerdict = .looksFine
            notes.append("The AI flagged this message but couldn't point to exact words in it, so its view wasn't counted.")
        }

        let strongRuleKinds = Set(rules.reasons.filter { $0.strength == .strong }.map(\.category)).count
        let disagreed = rules.verdict != aiVerdict

        let verdict: Verdict
        if rules.verdict == .likelyScam && aiVerdict == .likelyScam {
            verdict = .likelyScam
        } else if strongRuleKinds >= strongEvidenceKinds {
            verdict = .likelyScam
            if aiVerdict != .likelyScam {
                notes.append("The AI was less sure, but the built-in rules found several strong warning signs.")
            }
        } else if rules.verdict == .looksFine {
            verdict = .looksFine
            if aiVerdict != .looksFine {
                notes.append("The AI noticed the points below, but the built-in rules found no clear warning sign, so this isn't flagged. Take a look and decide.")
            }
        } else {
            verdict = .suspicious
            if aiVerdict == .looksFine {
                notes.append("The built-in rules found a warning sign; the AI was less concerned.")
            }
        }

        let result = AnalysisResult(
            message: rules.message,
            verdict: verdict,
            reasons: mergedReasons(rules: rules.reasons, ai: ai.reasons),
            source: .combined,
            confidence: ai.confidence,
            hiddenReasonCount: ai.hiddenReasonCount,
            notes: rules.notes + ai.notes + notes
        )
        return Combination(result: result, disagreed: disagreed)
    }

    static func mergedReasons(rules: [Reason], ai: [Reason]) -> [Reason] {
        var merged = rules
        for aiReason in ai {
            let duplicate = rules.contains { rule in
                rule.category == aiReason.category
                    && aiReason.span.start < rule.span.end
                    && rule.span.start < aiReason.span.end
            }
            if !duplicate {
                merged.append(aiReason)
            }
        }
        return merged.sorted { $0.span.start < $1.span.start }
    }
}
