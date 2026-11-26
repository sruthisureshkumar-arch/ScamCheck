//
//  LLMAnswerTests.swift
//  ScamCheckTests
//
//  WHAT THESE TESTS PROVE
//  The AI's answer is checked before it is shown, WITHOUT needing the real
//  model (these run anywhere, including the Simulator):
//  - JSON decoding: good JSON works; broken or incomplete JSON gives a
//    clear, readable error.
//  - Validation: unknown verdicts and impossible confidence values are
//    rejected; reasons quoting words that aren't in the message are dropped;
//    "Likely scam" with no surviving evidence is lowered to "Suspicious".
//
//  At the bottom, one test talks to the real on-device model. It only runs
//  when the model is available (e.g. on your iPhone), and checks that an
//  answer comes back and has a valid SHAPE, not whether the verdict is
//  right. Accuracy is Phase 5's job.
//
//  All messages are invented.
//

import Foundation
import Testing
import FoundationModels
@testable import ScamCheck

// MARK: - Decoding JSON text

struct LLMDecodingTests {

    @Test func decodesValidJSON() throws {
        let json = """
        {"reasons":[{"category":"credentialRequest","quote":"share the OTP","explanation":"Never share OTPs."}],
         "verdict":"likelyScam","confidence":0.9}
        """
        let answer = try LLMVerdict.decode(json: json)
        #expect(answer.verdict == "likelyScam")
        #expect(answer.confidence == 0.9)
        #expect(answer.reasons.first?.quote == "share the OTP")
    }

    @Test func missingFieldGivesReadableError() {
        let json = #"{"reasons":[],"verdict":"looksFine"}"#
        #expect(throws: LLMDecodeError.invalid(detail: "Missing field \"confidence\".")) {
            try LLMVerdict.decode(json: json)
        }
    }

    @Test func wrongTypeGivesReadableError() {
        let json = #"{"reasons":[],"verdict":"looksFine","confidence":"high"}"#
        #expect(throws: LLMDecodeError.self) {
            try LLMVerdict.decode(json: json)
        }
    }

    @Test func extractsJSONFromSurroundingText() throws {
        let text = """
        Here is my answer:
        ```json
        {"reasons":[],"verdict":"looksFine","confidence":0.8}
        ```
        """
        let answer = try LLMVerdict.decode(json: LLMVerdict.extractJSONObject(from: text))
        #expect(answer.verdict == "looksFine")
    }

    @Test func extractLeavesTextWithoutBracesUnchanged() {
        #expect(LLMVerdict.extractJSONObject(from: "Sorry, I can't help with that.") == "Sorry, I can't help with that.")
    }

    @Test func proseInsteadOfJSONIsRejected() {
        #expect(throws: LLMDecodeError.invalid(detail: "The answer is not valid JSON.")) {
            try LLMVerdict.decode(json: "Sure! This looks like a scam because...")
        }
    }
}

// MARK: - Validating an answer

struct LLMValidationTests {

    private let message = "URGENT: share the OTP with our agent to stop the debit."

    /// Builds a model answer the same way a real JSON answer arrives:
    /// as JSON text, decoded with Codable.
    private func answer(_ verdict: String, _ confidence: Double, _ reasons: [(category: String, quote: String)]) throws -> LLMVerdict {
        let object: [String: Any] = [
            "verdict": verdict,
            "confidence": confidence,
            "reasons": reasons.map { ["category": $0.category, "quote": $0.quote, "explanation": "Test explanation."] },
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try LLMVerdict.decode(json: String(decoding: data, as: UTF8.self))
    }

    @Test func acceptsAGoodAnswer() throws {
        let validated = try LLMVerdictValidator.validate(
            answer("likelyScam", 0.92, [("credentialRequest", "share the OTP"), ("urgencyOrThreat", "URGENT")]),
            for: message
        )
        #expect(validated.result.verdict == .likelyScam)
        #expect(validated.result.reasons.map(\.quote) == ["URGENT", "share the OTP"])  // sorted by position
        #expect(validated.result.source == .llm)
        #expect(validated.result.confidence == 0.92)
        #expect(validated.rejectedReasons.isEmpty)
    }

    @Test func rejectsUnknownVerdict() throws {
        let bad = try answer("scam", 0.9, [])
        #expect(throws: LLMValidationError.unknownVerdict("scam")) {
            try LLMVerdictValidator.validate(bad, for: message)
        }
    }

    @Test(arguments: [-0.1, 1.5])
    func rejectsImpossibleConfidence(_ confidence: Double) throws {
        let bad = try answer("suspicious", confidence, [])
        #expect(throws: LLMValidationError.confidenceOutOfRange(confidence)) {
            try LLMVerdictValidator.validate(bad, for: message)
        }
    }

    @Test func dropsReasonWhoseQuoteIsInvented() throws {
        let validated = try LLMVerdictValidator.validate(
            answer("suspicious", 0.7, [("credentialRequest", "share the OTP"), ("suspiciousLink", "bit.ly/abc")]),
            for: message
        )
        #expect(validated.result.reasons.map(\.quote) == ["share the OTP"])
        #expect(validated.rejectedReasons.count == 1)
        #expect(validated.result.hiddenReasonCount == 1)
    }

    @Test func dropsReasonWithUnknownCategory() throws {
        let validated = try LLMVerdictValidator.validate(
            answer("suspicious", 0.6, [("phishing", "share the OTP")]),
            for: message
        )
        #expect(validated.result.reasons.isEmpty)
        #expect(validated.rejectedReasons.first?.why.contains("unknown category") == true)
    }

    @Test func toleratesCapitalisationAndQuoteMarks() throws {
        let validated = try LLMVerdictValidator.validate(
            answer("suspicious", 0.6, [("credentialRequest", "“Share the otp”")]),
            for: message
        )
        // Stored quote is the message's own spelling.
        #expect(validated.result.reasons.map(\.quote) == ["share the OTP"])
    }

    @Test func flagWithoutSurvivingEvidenceBecomesLooksFine() throws {
        let validated = try LLMVerdictValidator.validate(
            answer("likelyScam", 0.95, [("suspiciousLink", "http://not-in-message.com")]),
            for: message
        )
        #expect(validated.result.verdict == .looksFine)
        #expect(validated.result.reasons.isEmpty)
        #expect(!validated.result.notes.isEmpty)
    }

    // Stricter evidence checks (added after the first evaluation run).

    @Test func wholeSentenceIsNotSpecificEvidence() throws {
        let long = "Rs 2,340 debited from A/c XX4412 on 25-11-26 at a shop near the station today."
        let validated = try LLMVerdictValidator.validate(
            answer("suspicious", 0.8, [("urgencyOrThreat", long)]),
            for: long
        )
        #expect(validated.result.reasons.isEmpty)
        #expect(validated.rejectedReasons.first?.why.contains("too long") == true)
    }

    @Test func doNotShareIsNotACredentialRequest() throws {
        let otp = "482913 is your OTP. Do not share this OTP with anyone."
        let validated = try LLMVerdictValidator.validate(
            answer("suspicious", 0.8, [("credentialRequest", "Do not share this OTP with anyone.")]),
            for: otp
        )
        #expect(validated.result.reasons.isEmpty)
        #expect(validated.result.verdict == .looksFine)
    }

    @Test(arguments: [
        "Track it at https://www.amazon.in/track/1",
        "Statement at https://www.hdfc.bank.in/cards",
    ])
    func officialLinkIsNotASuspiciousLink(_ text: String) throws {
        let link = String(text.split(separator: " ").last!)
        let validated = try LLMVerdictValidator.validate(
            answer("suspicious", 0.7, [("suspiciousLink", link)]),
            for: text
        )
        #expect(validated.result.reasons.isEmpty)
        #expect(validated.rejectedReasons.first?.why.contains("official") == true)
    }

    @Test func linkReasonNeedsALink() throws {
        let text = "XYZ Bank: your new card has been dispatched."
        let validated = try LLMVerdictValidator.validate(
            answer("suspicious", 0.7, [("senderLinkMismatch", "XYZ Bank")]),
            for: text
        )
        #expect(validated.result.reasons.isEmpty)
    }

    @Test func lookalikeLinkIsStillAccepted() throws {
        let text = "Verify now at http://sbi-kyc-update.com/login"
        let validated = try LLMVerdictValidator.validate(
            answer("likelyScam", 0.9, [("suspiciousLink", "http://sbi-kyc-update.com/login")]),
            for: text
        )
        #expect(validated.result.reasons.count == 1)
        #expect(validated.result.verdict == .likelyScam)
    }

    @Test func looksFineWithNoReasonsIsFine() throws {
        let validated = try LLMVerdictValidator.validate(answer("looksFine", 0.8, []), for: "See you at 6.")
        #expect(validated.result.verdict == .looksFine)
    }
}

// MARK: - Analyzer guards that don't need the model

struct OnDeviceLLMAnalyzerGuardTests {

    @Test func emptyMessageIsRefused() async {
        await #expect(throws: AnalyzerError.emptyMessage) {
            try await OnDeviceLLMAnalyzer().analyze("   ")
        }
    }

    @Test func veryLongMessageIsRefused() async {
        let long = String(repeating: "a", count: OnDeviceLLMAnalyzer.maxMessageLength + 1)
        await #expect(throws: LLMAnalyzerError.messageTooLong) {
            try await OnDeviceLLMAnalyzer().analyze(long)
        }
    }
}

// MARK: - Real model (runs only where the on-device model is available)

struct OnDeviceModelSmokeTests {

    /// The Simulator reports the model as "available" but can't run it unless
    /// the Mac's macOS is at least the Simulator's iOS version. So this test
    /// only runs on a real device. (Found the hard way; see WRONG_ANSWERS.md.)
    static var canRunRealModel: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return SystemLanguageModel.default.isAvailable
        #endif
    }

    @Test(
        .enabled(if: canRunRealModel, "Needs a real device with the on-device model"),
        .timeLimit(.minutes(2)),
        arguments: [
            "URGENT: your SBI account will be blocked today. Share the OTP to verify at sbi-kyc-update.com",
            "482913 is your OTP for login to XYZ Bank. Do not share it with anyone.",
        ]
    )
    func answerHasValidShape(_ message: String) async throws {
        // Since the permissive JSON fallback was added, a safety-filter
        // block should no longer reach here. Any error now fails the test,
        // so the report shows exactly which message and why.
        let result = try await OnDeviceLLMAnalyzer().analyze(message)
        #expect(result.source == .llm)
        for reason in result.reasons {
            #expect(reason.span.substring(in: message).map(String.init) == reason.quote)
        }
    }
}
