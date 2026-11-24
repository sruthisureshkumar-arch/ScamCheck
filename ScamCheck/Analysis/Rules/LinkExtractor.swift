//
//  LinkExtractor.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  Finds web links in a message and works out their domain.
//
//  WHAT COUNTS AS A LINK
//  - Anything starting with http:// or https://
//  - Anything starting with www.
//  - Otherwise, something like "name.com/abc" ONLY if it ends in a common web
//    ending (.com, .in, .ly, .xyz ...). This stops "Bal.Rs" or "e.g." being
//    read as links.
//  - Email addresses (support@bank.com) are NOT links.
//
//  "REGISTRABLE DOMAIN"
//  The part a company actually owns: for "www.hdfc.bank.in/login" it's
//  "hdfc.bank.in"; for "secure.sbi-kyc.com" it's "sbi-kyc.com". This is what
//  gets compared against KnownBrands.
//

import Foundation

nonisolated struct FoundLink: Sendable {
    /// Where the link is in the message (trailing punctuation removed).
    let range: Range<String.Index>
    /// Lowercased host, e.g. "www.hdfc.bank.in".
    let host: String
    /// e.g. "hdfc.bank.in".
    let registrableDomain: String
    /// True for links like http://192.168.1.4/...
    let isIPAddress: Bool
}

nonisolated enum LinkExtractor {

    // Group 1: scheme (http/https). Group 2: host. Group 3: path.
    private static let urlPattern = Pattern(
        #"(?<![@\w.])(?:(https?)://)?((?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,24})(?::\d+)?(/[^\s]*)?"#
    )
    private static let ipURLPattern = Pattern(#"\bhttps?://\d{1,3}(?:\.\d{1,3}){3}\b[^\s]*"#)

    /// Endings accepted for links written without http:// or www.
    private static let bareTopLevelDomains: Set<String> = [
        "com", "in", "net", "org", "co", "io", "ly", "gl", "me", "info", "xyz", "top", "app",
        "link", "click", "site", "online", "live", "shop", "store", "sbi", "bank", "gov", "us",
        "uk", "cc", "tk", "ml", "ga", "cf", "gq", "ws", "biz", "at", "to", "gd", "ai", "id", "ru", "cn",
    ]

    /// Endings made of two parts, e.g. ".co.in", ".bank.in".
    private static let twoPartEndings: Set<String> = [
        "co.in", "gov.in", "org.in", "net.in", "ac.in", "bank.in", "fin.in", "co.uk", "com.au",
    ]

    private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "'", "\"", "’", "”"]

    static func links(in message: String) -> [FoundLink] {
        var found: [FoundLink] = []

        for match in ipURLPattern.matches(in: message) {
            let range = trimmed(match.range, in: message)
            found.append(FoundLink(range: range, host: "", registrableDomain: "", isIPAddress: true))
        }

        for match in urlPattern.matches(in: message) {
            guard match.groups.count > 2, let hostRange = match.groups[2] else { continue }
            let host = message[hostRange].lowercased()
            let hasScheme = match.groups[1] != nil
            let hasWWW = host.hasPrefix("www.")
            let topLevel = host.split(separator: ".").last.map(String.init) ?? ""

            if !hasScheme && !hasWWW && !bareTopLevelDomains.contains(topLevel) {
                continue
            }
            found.append(FoundLink(
                range: trimmed(match.range, in: message),
                host: host,
                registrableDomain: registrableDomain(of: host),
                isIPAddress: false
            ))
        }
        return found
    }

    static func registrableDomain(of host: String) -> String {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return host }
        let lastTwo = parts.suffix(2).joined(separator: ".")
        if parts.count >= 3, twoPartEndings.contains(lastTwo) {
            return parts.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    /// Drops punctuation that ends a sentence rather than the link.
    private static func trimmed(_ range: Range<String.Index>, in message: String) -> Range<String.Index> {
        var upper = range.upperBound
        while upper > range.lowerBound {
            let previous = message.index(before: upper)
            guard trailingPunctuation.contains(message[previous]) else { break }
            upper = previous
        }
        return range.lowerBound..<upper
    }
}
