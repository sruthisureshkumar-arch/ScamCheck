//
//  Pattern.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  A thin wrapper around Apple's NSRegularExpression (regular expressions:
//  a mini-language for describing text patterns, e.g. "the word share, then
//  up to 30 characters, then OTP").
//
//  WHY A WRAPPER
//  - Every rule matches case-insensitively, so the option is set once here.
//  - NSRegularExpression works with NSRange (UTF-16 positions). This file
//    converts results back to Swift String ranges, so the rest of the app
//    never deals with that conversion.
//  - Patterns are compiled once, when first used, not on every message.
//
//  WHY NSRegularExpression AND NOT SWIFT'S NEWER Regex
//  Its pattern syntax is the long-standing ICU one, which I could test in
//  Python before writing Swift (no Swift compiler was available while the
//  rules were designed). Recorded in DECISIONS.md.
//
//  `@unchecked Sendable`: NSRegularExpression is documented as safe to share
//  between threads once created, but older SDKs don't mark it Sendable.
//

import Foundation

nonisolated struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    /// Patterns are fixed text written in this codebase. If one is invalid
    /// it is a programmer mistake, so crash loudly (the unit tests will
    /// catch it immediately) rather than silently never matching.
    init(_ pattern: String) {
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            fatalError("Invalid regular expression: \(pattern) — \(error)")
        }
    }

    /// Every match in `text`, as full-match ranges plus their capture groups.
    func matches(in text: String) -> [PatternMatch] {
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            let groups: [Range<String.Index>?] = (0..<result.numberOfRanges).map {
                Range(result.range(at: $0), in: text)
            }
            return PatternMatch(range: range, groups: groups)
        }
    }

    /// True if the pattern appears anywhere in `text`.
    func occurs(in text: String) -> Bool {
        let whole = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: whole) != nil
    }
}

nonisolated struct PatternMatch: Sendable {
    /// The whole match.
    let range: Range<String.Index>
    /// Capture groups; index 0 is the whole match. nil if a group didn't take part.
    let groups: [Range<String.Index>?]
}
