//
//  MockAnalyzer.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  A FAKE analyzer used only to build and test the screens in Phase 1.
//  It looks for a short, hard-coded list of demo phrases. It is NOT scam
//  detection and will be replaced in Phase 2.
//
//  HOW IT DECIDES (deliberately simple)
//  - no demo phrase found  -> Looks fine
//  - one found             -> Suspicious
//  - two or more found     -> Likely scam
//
//  It waits a moment before answering so the "checking..." state in the UI
//  can be seen and tested. Tests set `delay` to zero.
//
//  KNOWN WRONG BEHAVIOUR (on purpose, it's a mock)
//  A genuine "Your OTP is 123456" message will be marked Suspicious because
//  "OTP" is a demo phrase. Phase 2 must fix this with a must-not-trigger test.
//

import Foundation

nonisolated struct MockAnalyzer: MessageAnalyzer {

    /// How long to pretend to think.
    var delay: Duration = .milliseconds(400)

    private struct DemoPhrase: Sendable {
        let phrase: String
        let category: ReasonCategory
        let explanation: String
    }

    private static let demoPhrases: [DemoPhrase] = [
        DemoPhrase(phrase: "urgent", category: .urgencyOrThreat,
                   explanation: "Scammers rush you so you act before thinking."),
        DemoPhrase(phrase: "blocked", category: .urgencyOrThreat,
                   explanation: "Threats to block your account are a common pressure tactic."),
        DemoPhrase(phrase: "OTP", category: .credentialRequest,
                   explanation: "Banks never ask you to share an OTP with anyone."),
        DemoPhrase(phrase: "collect request", category: .paymentRequest,
                   explanation: "Approving a UPI collect request sends money out of your account."),
        DemoPhrase(phrase: "bit.ly", category: .suspiciousLink,
                   explanation: "Shortened links hide where they really go."),
        DemoPhrase(phrase: "processing fee", category: .feeForPrizeOrJob,
                   explanation: "Real prizes and jobs don't ask you to pay first."),
    ]

    func analyze(_ message: String) async throws -> AnalysisResult {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalyzerError.emptyMessage
        }

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        // Reason(...) returns nil when the phrase is not in the message,
        // so compactMap keeps only phrases that were actually found.
        let reasons = Self.demoPhrases.compactMap { demo in
            Reason(
                category: demo.category,
                quote: demo.phrase,
                explanation: demo.explanation,
                in: message,
                caseInsensitive: true
            )
        }

        let verdict: Verdict = switch reasons.count {
        case 0: .looksFine
        case 1: .suspicious
        default: .likelyScam
        }

        return AnalysisResult(message: message, verdict: verdict, reasons: reasons, source: .mock)
    }
}
