//
//  SyntheticMessageTests.swift
//  ScamCheckTests
//
//  WHAT THESE TESTS PROVE
//  The whole rule-based analyzer, end to end, on 38 invented messages:
//  genuine ones that must stay "Looks fine" (real OTPs, balance and debit
//  alerts, .bank.in links, a friend asking for the wifi password) and scams
//  that must be caught.
//
//  These were designed and checked in a Python prototype first, then copied
//  here automatically so the two lists are identical.
//
//  Every message is synthetic. None comes from a real person.
//
//  This is NOT the Phase 5 evaluation set. That one is separate, so the
//  rules aren't tuned on the same messages they're scored on.
//

import Testing
@testable import ScamCheck

struct RuleCase: Sendable, CustomTestStringConvertible {
    let message: String
    let expect: Verdict
    let mustFind: [ReasonCategory]
    let mustNotFind: [ReasonCategory]

    init(_ message: String, expect: Verdict, mustFind: [ReasonCategory], mustNotFind: [ReasonCategory]) {
        self.message = message
        self.expect = expect
        self.mustFind = mustFind
        self.mustNotFind = mustNotFind
    }

    var testDescription: String { message }

    static let all: [RuleCase] = [
        RuleCase("482913 is your OTP for login to XYZ Bank. Do not share it with anyone. -XYZ Bank",
                 expect: .looksFine, mustFind: [], mustNotFind: [.credentialRequest]),
        RuleCase("Your OTP is 771204. Never share your OTP, PIN or password with anyone, including bank staff.",
                 expect: .looksFine, mustFind: [], mustNotFind: [.credentialRequest]),
        RuleCase("OTP 5521 for txn of Rs 2,499 at ShopKart. Valid 10 mins. Do not share.",
                 expect: .looksFine, mustFind: [], mustNotFind: [.credentialRequest]),
        RuleCase("Your A/c XX1234 is credited with Rs 5,000.00 on 24-11-26. Avl Bal Rs 12,345.67. -XYZ Bank",
                 expect: .looksFine, mustFind: [], mustNotFind: [.suspiciousLink, .urgencyOrThreat]),
        RuleCase("Rs 1,250 debited from A/c XX9911 on 24-11-26. Avl Bal:Rs.8,240.10. Not you? Call 1800-000-0000 immediately.",
                 expect: .looksFine, mustFind: [], mustNotFind: [.urgencyOrThreat, .suspiciousLink]),
        RuleCase("Your Amazon order #402-1234 has shipped. Track it at https://amazon.in/track/abc123",
                 expect: .looksFine, mustFind: [], mustNotFind: [.suspiciousLink, .senderLinkMismatch]),
        RuleCase("SBI: Visit https://sbi.bank.in for our new net banking site.",
                 expect: .looksFine, mustFind: [], mustNotFind: [.suspiciousLink, .senderLinkMismatch]),
        RuleCase("HDFC Bank: your statement is ready at www.hdfc.bank.in/statements",
                 expect: .looksFine, mustFind: [], mustNotFind: [.suspiciousLink, .senderLinkMismatch]),
        RuleCase("Rs 500 received from Asha via UPI. Ref 6123. -PayBank",
                 expect: .looksFine, mustFind: [], mustNotFind: []),
        RuleCase("Your interview with Acme Corp is on Monday 10am. Reply YES to confirm.",
                 expect: .looksFine, mustFind: [], mustNotFind: [.feeForPrizeOrJob]),
        RuleCase("Electricity bill of Rs 450 due on 30 Nov. Pay via the official app.",
                 expect: .looksFine, mustFind: [], mustNotFind: [.feeForPrizeOrJob]),
        RuleCase("You won Rs 50 cashback on your last recharge! Credited to your wallet.",
                 expect: .looksFine, mustFind: [], mustNotFind: [.feeForPrizeOrJob]),
        RuleCase("Share the discount code SAVE10 with your friends!",
                 expect: .looksFine, mustFind: [], mustNotFind: [.credentialRequest]),
        RuleCase("Mail us at support@xyzbank.com for help.",
                 expect: .looksFine, mustFind: [], mustNotFind: [.suspiciousLink]),
        RuleCase("Meeting moved to 4pm, see you at e.g. the cafe near Bal.Rs office",
                 expect: .looksFine, mustFind: [], mustNotFind: [.suspiciousLink]),
        RuleCase("You have a collect request of Rs 299 from Café Brew. Approve only if you placed this order.",
                 expect: .looksFine, mustFind: [], mustNotFind: []),
        RuleCase("Hey, can you send me the wifi password? Forgot it again",
                 expect: .looksFine, mustFind: [], mustNotFind: [.credentialRequest]),
        RuleCase("Your card ending 4421 has been blocked as requested. -XYZ Bank",
                 expect: .looksFine, mustFind: [], mustNotFind: [.urgencyOrThreat]),
        RuleCase("Do not share your OTP or PIN. XYZ Bank will never ask for it.",
                 expect: .looksFine, mustFind: [], mustNotFind: [.credentialRequest]),
        RuleCase("Your OTP is 1234. Please don’t share it with anyone.",
                 expect: .looksFine, mustFind: [], mustNotFind: [.credentialRequest]),
        RuleCase("Your SBI Card statement is ready. View at https://www.sbicard.com/statement",
                 expect: .looksFine, mustFind: [], mustNotFind: [.suspiciousLink, .senderLinkMismatch]),
        RuleCase("ICICI: verify your account at http://1c1c1-verify.com",
                 expect: .suspicious, mustFind: [.suspiciousLink], mustNotFind: []),
        RuleCase("Hi, it's Mom. Running late, will call later.",
                 expect: .looksFine, mustFind: [], mustNotFind: []),
        RuleCase("URGENT: your SBI account will be blocked today. Update KYC at sbi-kyc-update.com",
                 expect: .likelyScam, mustFind: [.urgencyOrThreat, .suspiciousLink], mustNotFind: []),
        RuleCase("Dear customer, share the OTP sent to your number with our executive to stop the debit.",
                 expect: .suspicious, mustFind: [.credentialRequest], mustNotFind: []),
        RuleCase("Your parcel is held at our warehouse. Pay Rs 25 redelivery: bit.ly/3xYz9",
                 expect: .looksFine, mustFind: [.suspiciousLink], mustNotFind: []),
        RuleCase("India Post: parcel held due to incomplete address. Update within 24 hours at indiapost-track.in/upd",
                 expect: .likelyScam, mustFind: [.urgencyOrThreat, .suspiciousLink], mustNotFind: []),
        RuleCase("Congratulations! You are selected for a work from home job. Pay registration fee of Rs 499 to get your offer letter.",
                 expect: .suspicious, mustFind: [.feeForPrizeOrJob], mustNotFind: []),
        RuleCase("You won a lucky draw prize of Rs 25,00,000! Pay processing fee Rs 4,999 to claim.",
                 expect: .suspicious, mustFind: [.feeForPrizeOrJob], mustNotFind: []),
        RuleCase("Enter your UPI PIN to receive Rs 2,000 cashback from PhonePe.",
                 expect: .suspicious, mustFind: [.paymentRequest], mustNotFind: []),
        RuleCase("HDFC: Your netbanking is suspended. Verify at http://hdfc-secure-login.xyz/verify within 2 hrs",
                 expect: .likelyScam, mustFind: [.suspiciousLink, .urgencyOrThreat], mustNotFind: []),
        RuleCase("Your Paytm KYC expires today. Complete at http://paytm-kyc.online and share the OTP you receive.",
                 expect: .likelyScam, mustFind: [.suspiciousLink, .credentialRequest], mustNotFind: []),
        RuleCase("Amazon refund pending. Claim at http://amaz0n-refund.com",
                 expect: .suspicious, mustFind: [.suspiciousLink], mustNotFind: []),
        RuleCase("SBI alert: reward points expiring. Redeem now at rewardz-point.top/sbi",
                 expect: .suspicious, mustFind: [.senderLinkMismatch], mustNotFind: []),
        RuleCase("Visit http://192.168.10.4/login to verify your account",
                 expect: .suspicious, mustFind: [.suspiciousLink], mustNotFind: []),
        RuleCase("Please send your password to verify your account",
                 expect: .suspicious, mustFind: [.credentialRequest], mustNotFind: []),
        RuleCase("Send your UPI PIN to our support team to unlock your account",
                 expect: .suspicious, mustFind: [.credentialRequest], mustNotFind: []),
        RuleCase("Scan this QR code to receive Rs 5000 refund",
                 expect: .suspicious, mustFind: [.paymentRequest], mustNotFind: []),
    ]
}

struct SyntheticMessageTests {

    private let analyzer = RuleBasedAnalyzer()

    @Test(arguments: RuleCase.all)
    func verdictAndReasons(_ testCase: RuleCase) async throws {
        let result = try await analyzer.analyze(testCase.message)
        let found = Set(result.reasons.map(\.category))

        #expect(result.verdict == testCase.expect, "reasons: \(result.reasons.map { "\($0.category): \($0.quote)" })")
        for category in testCase.mustFind {
            #expect(found.contains(category), "expected \(category)")
        }
        for category in testCase.mustNotFind {
            #expect(!found.contains(category), "must not find \(category)")
        }
        // Every quote must be real text from the message, at the stored position.
        for reason in result.reasons {
            #expect(reason.span.substring(in: testCase.message).map(String.init) == reason.quote)
        }
        #expect(result.source == .rules)
    }
}
