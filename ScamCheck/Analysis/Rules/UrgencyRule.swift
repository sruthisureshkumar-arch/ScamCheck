//
//  UrgencyRule.swift
//  ScamCheck
//
//  WHAT IT DETECTS
//  Pressure and threats: "URGENT", "within 24 hours", "last chance",
//  "your account will be blocked", "legal action", "arrest".
//
//  STRENGTH: weak
//  Real messages are sometimes urgent too, so this alone never makes a
//  message Suspicious. It only adds weight to other signs.
//
//  DELIBERATELY NOT INCLUDED
//  "immediately" — genuine bank debit alerts say "Not you? Call immediately".
//  "has been blocked" — genuine "card blocked as requested" confirmations.
//  Only FUTURE threats ("will be blocked") count.
//

import Foundation

nonisolated struct UrgencyRule: ScamRule {

    private static let patterns: [Pattern] = [
        Pattern(#"\burgent(?:ly)?\b"#),
        Pattern(#"\bwithin\s+\d+\s*(?:hours?|hrs?|minutes?|mins?)\b"#),
        Pattern(#"\btoday\s+itself\b"#),
        Pattern(#"\b(?:last|final)\s+(?:chance|notice|warning|reminder)\b"#),
        Pattern(#"\bact\s+now\b"#),
        Pattern(#"\b(?:will|shall)\s+be\s+(?:blocked|suspended|deactivated|frozen|closed|terminated|disconnected)\b"#),
        Pattern(#"\blegal\s+action\b"#),
        Pattern(#"\barrest(?:ed)?\b"#),
    ]

    func findReasons(in message: String) -> [Reason] {
        Self.patterns.flatMap { $0.matches(in: message) }.compactMap { match in
            Reason(
                category: .urgencyOrThreat,
                strength: .weak,
                range: match.range,
                in: message,
                explanation: "Scammers create pressure so you act before checking."
            )
        }
    }
}
