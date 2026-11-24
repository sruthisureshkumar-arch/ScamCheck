//
//  QuoteLocator.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  A small helper that answers one question: "Is this quote really in the
//  message, and if so, where?"
//
//  WHY IT EXISTS
//  Every reason the app shows must point at real words in the message.
//  The mock, the rules and (later) the language model all go through this,
//  so there is exactly one place that decides what counts as a real quote.
//
//  KNOWN LIMITATION
//  It finds the FIRST occurrence only. If a phrase appears twice, only the
//  first is highlighted. That is acceptable for now; noted in DECISIONS.md.
//

import Foundation

nonisolated enum QuoteLocator {

    /// Finds `quote` inside `message`.
    ///
    /// - Returns: the span and the text exactly as it appears in the message,
    ///   or nil if the quote is empty or not present.
    static func locate(
        _ quote: String,
        in message: String,
        caseInsensitive: Bool = false
    ) -> (span: TextSpan, exactText: String)? {
        guard !quote.isEmpty else { return nil }

        var options: String.CompareOptions = []
        if caseInsensitive {
            options.insert(.caseInsensitive)
        }

        guard let range = message.range(of: quote, options: options) else {
            return nil
        }

        // Convert String.Index positions into plain Character counts,
        // which are easy to store, test and explain.
        let start = message.distance(from: message.startIndex, to: range.lowerBound)
        let length = message.distance(from: range.lowerBound, to: range.upperBound)
        return (TextSpan(start: start, length: length), String(message[range]))
    }
}
