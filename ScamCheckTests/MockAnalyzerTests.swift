//
//  MockAnalyzerTests.swift
//  ScamCheckTests
//
//  WHAT THESE TESTS PROVE
//  The fake analyzer behaves predictably, so the UI can be tested with it:
//  empty input is refused, the verdict follows the number of reasons, and
//  every quote it returns really exists in the message.
//
//  The mock is not real detection. These tests check its plumbing, not its
//  judgement. Phase 2 adds tests for real rules.
//

import Testing
@testable import ScamCheck

struct MockAnalyzerTests {

    private let analyzer = MockAnalyzer(delay: .zero)

    @Test func emptyMessageIsRefused() async {
        await #expect(throws: AnalyzerError.emptyMessage) {
            try await analyzer.analyze("   \n ")
        }
    }

    @Test func noDemoPhrasesLooksFine() async throws {
        let result = try await analyzer.analyze("Running 10 minutes late, see you soon.")
        #expect(result.verdict == .looksFine)
        #expect(result.reasons.isEmpty)
        #expect(result.source == .mock)
    }

    @Test func oneDemoPhraseIsSuspicious() async throws {
        let result = try await analyzer.analyze("Please click bit.ly/abc123 for details")
        #expect(result.verdict == .suspicious)
        #expect(result.reasons.count == 1)
    }

    @Test func twoOrMoreDemoPhrasesIsLikelyScam() async throws {
        let result = try await analyzer.analyze("URGENT: account blocked. Share OTP now.")
        #expect(result.verdict == .likelyScam)
        #expect(result.reasons.count >= 2)
    }

    @Test func everyQuoteIsReallyInTheMessage() async throws {
        let message = "Urgent! Pay the processing fee via bit.ly/job-offer or your offer is blocked"
        let result = try await analyzer.analyze(message)
        #expect(!result.reasons.isEmpty)
        for reason in result.reasons {
            #expect(reason.span.substring(in: message).map(String.init) == reason.quote)
        }
    }
}
