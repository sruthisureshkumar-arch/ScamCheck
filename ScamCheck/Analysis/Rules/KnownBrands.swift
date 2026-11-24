//
//  KnownBrands.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  A small list of brands that scammers often impersonate in India, with
//  the web domains each brand really uses.
//
//  HOW IT IS USED (by LinkRule)
//  - If a link's domain contains a brand's name but ISN'T one of that brand's
//    real domains (e.g. "sbi-kyc-update.com"), it's a lookalike.
//  - If a message names a brand ("SBI alert: ...") but its link goes to a
//    domain that brand doesn't use, the sender and link don't match.
//
//  THE .bank.in RULE
//  Since October 2025, RBI requires Indian banks to use ".bank.in" web
//  addresses, and only RBI-regulated banks can register them. So a link
//  ending in ".bank.in" is never treated as a lookalike.
//
//  ⚠️ CHECK BEFORE RELYING ON IT
//  Domains change. This list was put together from public information in
//  Nov 2026 and should be reviewed. Adding a real domain can only REDUCE
//  false alarms. A missing one causes a false alarm (the worse error here).
//

import Foundation

nonisolated struct Brand: Sendable {
    /// Short name used in code and tests.
    let name: String
    /// How the brand is written in explanations shown to the user.
    let displayName: String
    /// Words that mean a message claims to be from this brand.
    let keywords: [String]
    /// Text that, inside a link, suggests the link is pretending to be this brand.
    let domainToken: String
    /// The brand's real domains (registrable part, e.g. "hdfc.bank.in").
    let officialDomains: Set<String>
}

nonisolated enum KnownBrands {

    static let all: [Brand] = [
        Brand(name: "sbi", displayName: "SBI", keywords: ["sbi", "state bank"], domainToken: "sbi",
              officialDomains: ["sbi.bank.in", "sbi.co.in", "onlinesbi.sbi", "onlinesbi.com",
                                "sbicard.com", "sbilife.co.in", "sbimf.com", "sbigeneral.in"]),
        Brand(name: "hdfc", displayName: "HDFC Bank", keywords: ["hdfc"], domainToken: "hdfc",
              officialDomains: ["hdfc.bank.in", "hdfcbank.com", "hdfc.com", "hdfclife.com",
                                "hdfcergo.com", "hdfcsec.com", "hdfcfund.com"]),
        Brand(name: "icici", displayName: "ICICI Bank", keywords: ["icici"], domainToken: "icici",
              officialDomains: ["icici.bank.in", "icicibank.com", "icicidirect.com",
                                "iciciprulife.com", "icicilombard.com"]),
        Brand(name: "axis", displayName: "Axis Bank", keywords: ["axis bank"], domainToken: "axisbank",
              officialDomains: ["axis.bank.in", "axisbank.com"]),
        Brand(name: "kotak", displayName: "Kotak", keywords: ["kotak"], domainToken: "kotak",
              officialDomains: ["kotak.bank.in", "kotak.com", "kotaksecurities.com"]),
        Brand(name: "pnb", displayName: "PNB", keywords: ["pnb", "punjab national"], domainToken: "pnb",
              officialDomains: ["pnb.bank.in", "pnbindia.in", "pnbhousing.com"]),
        Brand(name: "paytm", displayName: "Paytm", keywords: ["paytm"], domainToken: "paytm",
              officialDomains: ["paytm.com", "paytm.in", "paytmbank.com", "paytmmoney.com"]),
        Brand(name: "phonepe", displayName: "PhonePe", keywords: ["phonepe"], domainToken: "phonepe",
              officialDomains: ["phonepe.com"]),
        Brand(name: "amazon", displayName: "Amazon", keywords: ["amazon"], domainToken: "amazon",
              officialDomains: ["amazon.in", "amazon.com", "amazon.co.uk", "amazonaws.com",
                                "amazonpay.in", "amzn.in", "amzn.to"]),
        Brand(name: "flipkart", displayName: "Flipkart", keywords: ["flipkart"], domainToken: "flipkart",
              officialDomains: ["flipkart.com", "fkrt.it"]),
        Brand(name: "indiapost", displayName: "India Post", keywords: ["india post", "indiapost"], domainToken: "indiapost",
              officialDomains: ["indiapost.gov.in"]),
        Brand(name: "irctc", displayName: "IRCTC", keywords: ["irctc"], domainToken: "irctc",
              officialDomains: ["irctc.co.in", "irctctourism.com"]),
        Brand(name: "incometax", displayName: "the Income Tax Department", keywords: ["income tax"], domainToken: "incometax",
              officialDomains: ["incometax.gov.in"]),
    ]

    /// The brand that really owns `registrableDomain`, if any.
    static func owner(of registrableDomain: String) -> Brand? {
        all.first { $0.officialDomains.contains(registrableDomain) }
    }

    /// Brands the message claims to be from (whole-word match, any case).
    static func mentioned(in message: String) -> [Brand] {
        all.filter { brand in
            brand.keywords.contains { keyword in
                Pattern(#"\b"# + NSRegularExpression.escapedPattern(for: keyword) + #"\b"#).occurs(in: message)
            }
        }
    }

    /// Link shorteners: they hide where a link really goes.
    static let shorteners: Set<String> = [
        "bit.ly", "tinyurl.com", "t.co", "goo.gl", "cutt.ly", "rb.gy", "is.gd", "ow.ly",
        "shorturl.at", "tiny.cc", "t.ly", "rebrand.ly", "s.id", "v.gd",
    ]
}
