//
//  LinkRule.swift
//  ScamCheck
//
//  WHAT IT DETECTS (in order of checking each link)
//  1. Link to a raw IP address (http://192.168.1.4/login)      → strong
//  2. Link shortener (bit.ly, tinyurl ...)                      → weak
//     Real companies use shorteners too, so this alone is only a note.
//  3. Lookalike: the link contains a brand's name but isn't that brand's
//     real domain ("sbi-kyc-update.com"), including number swaps
//     ("amaz0n-refund.com", "1c1c1-verify.com")                 → strong
//  4. Sender/link mismatch: the message names a brand ("SBI alert") but the
//     link goes to a domain that brand doesn't use               → strong
//
//  Links ending in .bank.in are never called lookalikes (see KnownBrands).
//

import Foundation

nonisolated struct LinkRule: ScamRule {

    func findReasons(in message: String) -> [Reason] {
        let mentionedBrands = KnownBrands.mentioned(in: message)
        var reasons: [Reason] = []

        for link in LinkExtractor.links(in: message) {
            if let reason = reason(for: link, in: message, mentionedBrands: mentionedBrands) {
                reasons.append(reason)
            }
        }
        return reasons
    }

    private func reason(for link: FoundLink, in message: String, mentionedBrands: [Brand]) -> Reason? {
        if link.isIPAddress {
            return Reason(category: .suspiciousLink, strength: .strong, range: link.range, in: message,
                          explanation: "This link goes to a bare number address instead of a company website. Real companies don't do this.")
        }

        let domain = link.registrableDomain

        if KnownBrands.shorteners.contains(domain) {
            return Reason(category: .suspiciousLink, strength: .weak, range: link.range, in: message,
                          explanation: "Short links hide where they really go. Be careful before opening.")
        }

        let owner = KnownBrands.owner(of: domain)
        let isBankDomain = domain.hasSuffix(".bank.in")

        if owner == nil, !isBankDomain, let imitated = imitatedBrand(host: link.host) {
            return Reason(category: .suspiciousLink, strength: .strong, range: link.range, in: message,
                          explanation: "This link uses the name \"\(imitated.keywords[0].uppercased())\" but isn't their real website. Lookalike links are a common way to steal logins.")
        }

        if let claimed = mentionedBrands.first(where: { $0.name != owner?.name }) {
            return Reason(category: .senderLinkMismatch, strength: .strong, range: link.range, in: message,
                          explanation: "The message says it's from \(claimed.displayName), but the link goes to a website they don't use.")
        }

        return nil
    }

    /// The brand a host seems to imitate, checking common number-for-letter swaps.
    private func imitatedBrand(host: String) -> Brand? {
        let plain = host.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ".", with: "")
        let variants = [plain, swapDigits(plain, oneAs: "l"), swapDigits(plain, oneAs: "i")]
        return KnownBrands.all.first { brand in
            variants.contains { $0.contains(brand.domainToken) }
        }
    }

    private func swapDigits(_ text: String, oneAs one: Character) -> String {
        let map: [Character: Character] = ["0": "o", "1": one, "3": "e", "4": "a", "5": "s", "7": "t"]
        return String(text.map { map[$0] ?? $0 })
    }
}
