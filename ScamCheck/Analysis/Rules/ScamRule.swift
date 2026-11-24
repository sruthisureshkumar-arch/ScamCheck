//
//  ScamRule.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The contract for one rule: look at a message, return the warning signs
//  found (as Reasons). Each rule checks ONE kind of trick, so each can be
//  read, tested and explained on its own.
//
//  Also holds the shared negation check ("do NOT share your OTP" must not be
//  treated as a request to share it).
//

import Foundation

nonisolated protocol ScamRule: Sendable {
    func findReasons(in message: String) -> [Reason]
}

nonisolated enum Negation {

    /// Words that flip a request into a warning: "do not", "never", ...
    /// Handles both straight (') and curly (’) apostrophes, because iPhones
    /// type curly ones by default.
    static let pattern = Pattern(#"\b(?:do\s+not|don[’']?t|never|not\s+to|no\s+one|will\s+never|won[’']?t)\b"#)

    /// How far back (in characters) to look for a negation word.
    static let window = 25

    /// True if a negation word appears just before `range`, or inside it.
    static func isNegated(_ range: Range<String.Index>, in message: String) -> Bool {
        let lookBackStart = message.index(range.lowerBound, offsetBy: -window, limitedBy: message.startIndex)
            ?? message.startIndex
        let nearby = String(message[lookBackStart..<range.upperBound])
        return pattern.occurs(in: nearby)
    }
}
