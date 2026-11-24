//
//  RuleTests.swift
//  ScamCheckTests
//
//  WHAT THESE TESTS PROVE
//  Each rule on its own: what it MUST catch, and, just as important, what it
//  must NOT catch (genuine OTPs, real bank alerts, real bank links).
//  Plus the link parser and the verdict policy.
//
//  All messages are invented.
//

import Testing
@testable import ScamCheck

/// Categories a single rule finds in a message.
private func categories(_ rule: some ScamRule, _ message: String) -> [ReasonCategory] {
    rule.findReasons(in: message).map(\.category)
}

private func quotes(_ rule: some ScamRule, _ message: String) -> [String] {
    rule.findReasons(in: message).map(\.quote)
}

// MARK: - Urgency

struct UrgencyRuleTests {
    let rule = UrgencyRule()

    @Test(arguments: [
        "URGENT: verify your account",
        "Respond within 24 hours or lose access",
        "Your account will be blocked tonight",
        "Last chance to claim",
        "Pay today itself to avoid legal action",
    ])
    func catchesPressure(_ message: String) {
        #expect(categories(rule, message).contains(.urgencyOrThreat))
    }

    @Test(arguments: [
        "Rs 1,250 debited. Not you? Call 1800-000-0000 immediately.",  // genuine debit alert
        "Your card ending 4421 has been blocked as requested.",         // past tense, user asked for it
        "Your OTP is 4412. Valid for 10 mins.",
    ])
    func ignoresGenuineAlerts(_ message: String) {
        #expect(categories(rule, message).isEmpty)
    }

    @Test func isAlwaysWeak() {
        #expect(rule.findReasons(in: "URGENT act now").allSatisfy { $0.strength == .weak })
    }
}

// MARK: - Credential requests

struct CredentialRequestRuleTests {
    let rule = CredentialRequestRule()

    @Test(arguments: [
        "Please share the OTP sent to your phone",
        "Send your UPI PIN to unlock",
        "Kindly provide your password to verify",
        "Tell our agent the CVV on your card",
        "The OTP you received, forward it to this number",
    ])
    func catchesRequests(_ message: String) {
        #expect(categories(rule, message) == [.credentialRequest])
    }

    @Test(arguments: [
        "482913 is your OTP for login. Do not share it with anyone.",
        "Your OTP is 1234. Never share your OTP, PIN or password.",
        "Your OTP is 1234. Please don’t share it with anyone.",   // curly apostrophe
        "Your OTP is 1234. Please don't share it with anyone.",   // straight apostrophe
        "XYZ Bank will never ask you to share your OTP.",
        "Can you send me the wifi password?",                     // a friend, not a credential theft
        "Share the discount code SAVE10 with friends",
    ])
    func ignoresWarningsAndOrdinaryMessages(_ message: String) {
        #expect(categories(rule, message).isEmpty)
    }

    @Test func quotesTheRequestItself() {
        #expect(quotes(rule, "Dear user, share the OTP now") == ["share the OTP"])
    }

    @Test func doesNotCrossSentences() {
        // "share" and "OTP" are in different sentences: not a request to share the OTP.
        #expect(categories(rule, "Please share this with family. Your OTP is 4412.").isEmpty)
    }
}

// MARK: - Payment requests

struct PaymentRequestRuleTests {
    let rule = PaymentRequestRule()

    @Test func pinToReceiveIsStrong() {
        let reasons = rule.findReasons(in: "Enter your UPI PIN to receive Rs 2,000")
        #expect(reasons.count == 1)
        #expect(reasons.first?.strength == .strong)
    }

    @Test func scanToReceiveIsStrong() {
        #expect(rule.findReasons(in: "Scan this QR code to receive your refund").first?.strength == .strong)
    }

    @Test func collectRequestIsOnlyWeak() {
        let reasons = rule.findReasons(in: "You have a collect request of Rs 299 from Café Brew.")
        #expect(reasons.map(\.strength) == [.weak])
    }

    @Test(arguments: [
        "Rs 500 received from Asha via UPI. Ref 6123.",
        "Enter your UPI PIN to complete the payment you started.",  // paying, not "to receive"
        "Your refund of Rs 300 has been credited.",
    ])
    func ignoresGenuinePayments(_ message: String) {
        #expect(categories(rule, message).isEmpty)
    }
}

// MARK: - Fees for prizes and jobs

struct FeeForPrizeOrJobRuleTests {
    let rule = FeeForPrizeOrJobRule()

    @Test(arguments: [
        "You are selected for a part-time job. Pay registration fee of Rs 499.",
        "You won a lucky draw! Pay processing fee Rs 4,999 to claim.",
        "Work from home, salary 30k. Refundable deposit of ₹2,000 required.",
    ])
    func catchesPayToReceive(_ message: String) {
        #expect(categories(rule, message).contains(.feeForPrizeOrJob))
    }

    @Test(arguments: [
        "Electricity bill of Rs 450 due. Pay Rs 450 via the official app.",  // fee but no prize/job
        "You won Rs 50 cashback! Credited to your wallet.",                 // prize but no fee
        "Your interview with Acme is on Monday 10am.",                      // job but no fee
    ])
    func needsBothPrizeOrJobAndFee(_ message: String) {
        #expect(categories(rule, message).isEmpty)
    }
}

// MARK: - Links

struct LinkExtractorTests {

    @Test func findsLinksWithAndWithoutScheme() {
        let message = "Go to https://sbi.bank.in/x or bit.ly/abc or www.example.org."
        let hosts = LinkExtractor.links(in: message).map(\.host)
        #expect(hosts == ["sbi.bank.in", "bit.ly", "www.example.org"])
    }

    @Test func trailingFullStopIsNotPartOfTheLink() throws {
        let message = "Visit www.example.org."
        let link = try #require(LinkExtractor.links(in: message).first)
        #expect(message[link.range] == "www.example.org")
    }

    @Test(arguments: [
        "Mail us at support@xyzbank.com",   // email address
        "Avl Bal:Rs.8,240.10",              // amounts with dots
        "see e.g. the note",
    ])
    func ignoresThingsThatAreNotLinks(_ message: String) {
        #expect(LinkExtractor.links(in: message).isEmpty)
    }

    @Test(arguments: [
        ("www.hdfc.bank.in", "hdfc.bank.in"),
        ("secure.sbi-kyc.com", "sbi-kyc.com"),
        ("irctc.co.in", "irctc.co.in"),
        ("bit.ly", "bit.ly"),
    ])
    func registrableDomain(_ host: String, _ expected: String) {
        #expect(LinkExtractor.registrableDomain(of: host) == expected)
    }
}

struct LinkRuleTests {
    let rule = LinkRule()

    @Test func shortenerIsWeak() {
        #expect(rule.findReasons(in: "Details: bit.ly/3xYz9").map(\.strength) == [.weak])
    }

    @Test(arguments: [
        "Update KYC at sbi-kyc-update.com",
        "Claim at http://amaz0n-refund.com",       // zero instead of o
        "Verify at http://1c1c1-verify.com",        // ones instead of i
        "Login: http://secure.hdfc.verify-now.xyz", // brand hidden in a subdomain
    ])
    func catchesLookalikes(_ message: String) {
        let reasons = rule.findReasons(in: message)
        #expect(reasons.map(\.category) == [.suspiciousLink])
        #expect(reasons.first?.strength == .strong)
    }

    @Test func catchesBrandAndLinkMismatch() {
        #expect(categories(rule, "SBI alert: redeem points at rewardz-point.top/x") == [.senderLinkMismatch])
    }

    @Test func catchesIPAddressLinks() {
        #expect(categories(rule, "Verify at http://192.168.10.4/login") == [.suspiciousLink])
    }

    @Test(arguments: [
        "SBI: visit https://sbi.bank.in",
        "HDFC Bank: statement at www.hdfc.bank.in/statements",
        "ICICI Bank: login at https://www.icici.bank.in",
        "Your Amazon order shipped: https://amazon.in/track/1",
        "Your SBI Card statement: https://www.sbicard.com/s",
        "Meet me at the cafe, menu at cafebrew.in",   // ordinary link, no brand
    ])
    func trustsRealDomains(_ message: String) {
        #expect(categories(rule, message).isEmpty)
    }
}

// MARK: - Verdict policy

struct VerdictPolicyTests {

    private func reason(_ category: ReasonCategory, _ strength: SignalStrength) -> Reason {
        let message = "x"
        return Reason(category: category, strength: strength,
                      range: message.startIndex..<message.endIndex, in: message, explanation: "")!
    }

    @Test func nothingLooksFine() {
        #expect(VerdictPolicy.verdict(for: []) == .looksFine)
    }

    @Test func oneWeakSignStillLooksFine() {
        #expect(VerdictPolicy.verdict(for: [reason(.suspiciousLink, .weak)]) == .looksFine)
    }

    @Test func twoWeakOfTheSameKindStillLooksFine() {
        #expect(VerdictPolicy.verdict(for: [reason(.urgencyOrThreat, .weak), reason(.urgencyOrThreat, .weak)]) == .looksFine)
    }

    @Test func twoWeakKindsAreSuspicious() {
        #expect(VerdictPolicy.verdict(for: [reason(.urgencyOrThreat, .weak), reason(.suspiciousLink, .weak)]) == .suspicious)
    }

    @Test func oneStrongIsSuspicious() {
        #expect(VerdictPolicy.verdict(for: [reason(.credentialRequest, .strong)]) == .suspicious)
    }

    @Test func strongPlusWeakIsLikelyScam() {
        #expect(VerdictPolicy.verdict(for: [reason(.credentialRequest, .strong), reason(.urgencyOrThreat, .weak)]) == .likelyScam)
    }

    @Test func twoStrongKindsIsLikelyScam() {
        #expect(VerdictPolicy.verdict(for: [reason(.credentialRequest, .strong), reason(.suspiciousLink, .strong)]) == .likelyScam)
    }
}
