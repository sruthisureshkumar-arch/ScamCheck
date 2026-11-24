//
//  FeeForPrizeOrJobRule.swift
//  ScamCheck
//
//  WHAT IT DETECTS
//  A prize, reward or job that asks YOU to pay first:
//  "You are selected... pay registration fee of Rs 499".
//
//  STRENGTH: strong
//
//  HOW IT AVOIDS FALSE ALARMS
//  It needs BOTH:
//   1. context: prize / lottery / won / reward / job / selected / salary ...
//   2. a fee: "registration fee", "processing fee", "pay Rs 499", "deposit of ₹2,000" ...
//  So "Electricity bill: pay Rs 450" (no prize/job) and "You won Rs 50
//  cashback, credited" (no fee) do not trigger.
//
//  KNOWN MISS
//  Delivery scams ("parcel held, pay Rs 25 redelivery") aren't covered here,
//  because genuine couriers also say "pay Rs 450 on delivery". Accepted for
//  precision; the language model (Phase 3) should help.
//

import Foundation

nonisolated struct FeeForPrizeOrJobRule: ScamRule {

    private static let context = Pattern(#"\b(?:won|winner|prize|lottery|lucky\s+draw|reward|selected|shortlisted|job|hiring|work\s+from\s+home|part[\s-]time|salary|offer\s+letter)\b"#)

    private static let feePatterns: [Pattern] = [
        Pattern(#"\b(?:registration|processing|joining|verification|security|refundable|delivery|clearance)\s+(?:fee|fees|charges?|deposit|amount)\b"#),
        Pattern(#"\bpay\s+(?:rs\.?|inr|₹)\s*[\d,]+"#),
        Pattern(#"\b(?:fee|fees|charges?|deposit)\s+of\s+(?:rs\.?|inr|₹)\s*[\d,]+"#),
    ]

    func findReasons(in message: String) -> [Reason] {
        guard Self.context.occurs(in: message) else { return [] }
        return Self.feePatterns.flatMap { $0.matches(in: message) }.compactMap { match in
            Reason(
                category: .feeForPrizeOrJob,
                strength: .strong,
                range: match.range,
                in: message,
                explanation: "Real prizes and real jobs don't ask you to pay to receive them."
            )
        }
    }
}
