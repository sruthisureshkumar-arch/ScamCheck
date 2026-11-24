//
//  CredentialRequestRule.swift
//  ScamCheck
//
//  WHAT IT DETECTS
//  Someone asking you to SHARE a secret: "share the OTP", "send your UPI PIN",
//  "your password, forward it to...".
//
//  STRENGTH: strong
//  No bank, app or delivery company ever asks you to send these.
//
//  HOW IT AVOIDS FALSE ALARMS (the most important part)
//  - It needs a request verb (share, send, tell, give, provide, forward,
//    reply with, disclose) near the secret. "482913 is your OTP" has no verb,
//    so it never triggers.
//  - If "do not", "never", "don't" (etc.) appears just before or inside the
//    match, it is a WARNING, not a request: "Do not share it" is ignored.
//  - Plain "PIN" / "password" only count with "your" ("send your password"),
//    so "send me the wifi password" from a friend doesn't trigger.
//    OTP, CVV, UPI PIN etc. count on their own.
//
//  KNOWN MISS
//  "OTP 4412 do not share. Our agent will call, please share it with him."
//  The second request says "it", not "OTP", so it isn't caught. Accepted to
//  keep precision high; logged in WRONG_ANSWERS.md.
//

import Foundation

nonisolated struct CredentialRequestRule: ScamRule {

    private static let verb = #"(?:share|send|tell|give|provide|forward|reply\s+with|disclose|whatsapp|sms)"#
    private static let secret = #"(?:otp|one[\s-]time\s+password|upi\s+pin|atm\s+pin|m-?pin|cvv|verification\s+code|security\s+code|your\s+(?:pin|password|passcode))"#
    /// Up to 30 characters, not crossing the end of a sentence.
    private static let gap = #"[^.!?\n]{0,30}?"#

    private static let patterns: [Pattern] = [
        Pattern(#"\b"# + verb + #"\b"# + gap + #"\b"# + secret + #"\b"#),   // "share the OTP"
        Pattern(#"\b"# + secret + #"\b"# + gap + #"\b"# + verb + #"\b"#),   // "OTP ... share it"
    ]

    func findReasons(in message: String) -> [Reason] {
        Self.patterns
            .flatMap { $0.matches(in: message) }
            .filter { !Negation.isNegated($0.range, in: message) }
            .compactMap { match in
                Reason(
                    category: .credentialRequest,
                    strength: .strong,
                    range: match.range,
                    in: message,
                    explanation: "Banks and apps never ask you to share an OTP, PIN, password or CVV. Anyone who has it can take your money."
                )
            }
    }
}
