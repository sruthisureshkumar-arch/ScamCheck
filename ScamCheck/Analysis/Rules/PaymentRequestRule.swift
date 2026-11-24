//
//  PaymentRequestRule.swift
//  ScamCheck
//
//  WHAT IT DETECTS
//  Tricks that make money LEAVE your account while pretending you'll receive it.
//
//  STRONG signs (you never need these to RECEIVE money):
//  - "Enter your UPI PIN to receive ₹2,000"
//  - "Scan this QR code to receive your refund"
//
//  WEAK signs (also used by real shops):
//  - "collect request", "approve the payment request"
//
//  LIMITATION: "from unknown senders"
//  A pasted message doesn't tell the app who sent it or whether they are in
//  your contacts, so this rule can't check the sender. That's why a plain
//  collect request is only a weak sign. Noted in DECISIONS.md.
//

import Foundation

nonisolated struct PaymentRequestRule: ScamRule {

    private static let strongPatterns: [Pattern] = [
        Pattern(#"\b(?:enter|use|type)\s+(?:your\s+)?(?:upi\s+)?(?:pin|m-?pin)\s+to\s+(?:receive|get|claim|accept)\b"#),
        Pattern(#"\bscan\b[^.!?\n]{0,30}?\b(?:qr|code)\b[^.!?\n]{0,20}?\bto\s+(?:receive|get|claim)\b"#),
    ]

    private static let weakPatterns: [Pattern] = [
        Pattern(#"\bcollect\s+request\b"#),
        Pattern(#"\b(?:approve|accept)\s+(?:the\s+|this\s+)?(?:payment\s+)?request\b"#),
    ]

    func findReasons(in message: String) -> [Reason] {
        let strong = Self.strongPatterns.flatMap { $0.matches(in: message) }.compactMap { match in
            Reason(
                category: .paymentRequest,
                strength: .strong,
                range: match.range,
                in: message,
                explanation: "You never need to enter a PIN or scan a code to RECEIVE money. Doing this sends money out of your account."
            )
        }
        let weak = Self.weakPatterns.flatMap { $0.matches(in: message) }.compactMap { match in
            Reason(
                category: .paymentRequest,
                strength: .weak,
                range: match.range,
                in: message,
                explanation: "Approving a collect request pays the sender. Only approve if you started this payment yourself."
            )
        }
        return strong + weak
    }
}
