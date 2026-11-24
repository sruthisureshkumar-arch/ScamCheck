//
//  VerdictPolicy.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The single place that turns a list of warning signs into a verdict.
//
//  THE POLICY (precision first: wrongly calling a real message a scam is
//  worse than missing one scam)
//
//  Count DIFFERENT kinds of sign (two urgency phrases still count as one).
//
//    Likely scam  ← two strong kinds, OR one strong + one weak kind
//    Suspicious   ← one strong kind alone, OR two weak kinds
//    Looks fine   ← nothing, OR a single weak kind
//                   (the weak sign is still shown as "worth noticing")
//
//  Example: a genuine shop's "collect request" (one weak sign) stays
//  "Looks fine" with a note, instead of being called Suspicious.
//
//  Phase 4 will reuse this when combining rules with the language model.
//

import Foundation

nonisolated enum VerdictPolicy {

    static func verdict(for reasons: [Reason]) -> Verdict {
        let strongKinds = Set(reasons.filter { $0.strength == .strong }.map(\.category))
        // A category already counted as strong isn't counted again as weak.
        let weakKinds = Set(reasons.filter { $0.strength == .weak }.map(\.category))
            .subtracting(strongKinds)

        if strongKinds.count >= 2 || (!strongKinds.isEmpty && !weakKinds.isEmpty) {
            return .likelyScam
        }
        if !strongKinds.isEmpty || weakKinds.count >= 2 {
            return .suspicious
        }
        return .looksFine
    }
}
