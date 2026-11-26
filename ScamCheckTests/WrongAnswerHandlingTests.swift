//
//  WrongAnswerHandlingTests.swift
//  ScamCheckTests
//
//  WHAT THESE TESTS PROVE (Phase 4)
//  Using a FAKE model that misbehaves on purpose (ScriptedClient):
//  - An unusable answer is retried exactly once, with the error sent back.
//  - Two unusable answers in a row → give up with an error.
//  - Failures that a retry can't fix (safety filter, unavailable) aren't retried.
//  - The combined analyzer falls back to the rules when the AI fails.
//  - The combination policy only says "Likely scam" when both agree or the
//    rules have strong evidence; otherwise "Suspicious".
//  - Every failure lands in the debug log.
//
//  None of this needs the real model, so it runs in the Simulator too.
//  All messages are invented.
//

import Foundation
import Testing
@testable import ScamCheck

// MARK: - Test helpers

/// A fake LLMClient that plays back a script of replies, one per call,
/// and remembers every prompt it was sent.
final class ScriptedClient: LLMClient, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [Result<LLMClientReply, LLMAnalyzerError>]
    private var _prompts: [String] = []
    private let unavailable: LLMAnalyzerError?

    init(_ script: [Result<LLMClientReply, LLMAnalyzerError>], unavailable: LLMAnalyzerError? = nil) {
        self.script = script
        self.unavailable = unavailable
    }

    var prompts: [String] { lock.withLock { _prompts } }

    func checkAvailability() throws {
        if let unavailable { throw unavailable }
    }

    func reply(to prompt: String) async throws -> LLMClientReply {
        let next: Result<LLMClientReply, LLMAnalyzerError> = lock.withLock {
            _prompts.append(prompt)
            return script.isEmpty ? .failure(.generationFailed("script ran out")) : script.removeFirst()
        }
        return try next.get()
    }
}

/// Builds a model answer from JSON, exactly as a real JSON answer would arrive.
private func answer(_ verdict: String, _ confidence: Double = 0.9, quotes: [(String, String)] = []) -> LLMClientReply {
    let reasons = quotes.map { #"{"category":"\#($0.0)","quote":"\#($0.1)","explanation":"Test."}"# }
    let json = #"{"reasons":[\#(reasons.joined(separator: ","))],"verdict":"\#(verdict)","confidence":\#(confidence)}"#
    // Force-try is fine in a test helper: a typo here should fail loudly.
    return LLMClientReply(answer: try! LLMVerdict.decode(json: json), path: .scripted)
}

private let scamMessage = "URGENT: share the OTP with our agent at sbi-kyc-update.com"
private let safeMessage = "Running late, see you at 6."

// MARK: - Retry once

struct RetryTests {

    @Test func unusableAnswerIsRetriedOnceWithTheError() async throws {
        let client = ScriptedClient([
            .failure(.invalidAnswer("Missing field \"confidence\".")),
            .success(answer("looksFine")),
        ])
        let log = DebugLog(fileURL: nil)
        let outcome = try await OnDeviceLLMAnalyzer(client: client, log: log).analyzeInDetail(safeMessage)

        #expect(outcome.attempts == 2)
        #expect(client.prompts.count == 2)
        #expect(!client.prompts[0].contains("could not be used"))
        #expect(client.prompts[1].contains("Missing field \"confidence\"."))   // the error was sent back
        #expect(outcome.validated.result.notes.contains { $0.contains("asked again") })

        let events = await log.entries().map(\.event)
        #expect(events == [.invalidAnswer, .retrySucceeded])
    }

    @Test func failedValidationIsAlsoRetried() async throws {
        let client = ScriptedClient([
            .success(answer("scam")),            // not an allowed verdict
            .success(answer("looksFine")),
        ])
        let outcome = try await OnDeviceLLMAnalyzer(client: client, log: DebugLog(fileURL: nil)).analyzeInDetail(safeMessage)
        #expect(outcome.attempts == 2)
        #expect(client.prompts[1].contains("\"verdict\" was \"scam\""))
    }

    @Test func givesUpAfterTwoUnusableAnswers() async {
        let client = ScriptedClient([
            .failure(.invalidAnswer("The answer is not valid JSON.")),
            .failure(.invalidAnswer("The answer is not valid JSON.")),
            .success(answer("looksFine")),      // must never be reached
        ])
        let log = DebugLog(fileURL: nil)
        await #expect(throws: LLMAnalyzerError.invalidAnswer("The answer is not valid JSON.")) {
            try await OnDeviceLLMAnalyzer(client: client, log: log).analyzeInDetail(safeMessage)
        }
        #expect(client.prompts.count == 2)
        #expect(await log.entries().map(\.event) == [.invalidAnswer, .aiFailed])
    }

    @Test func safetyFilterBlockIsNotRetried() async {
        let client = ScriptedClient([.failure(.blockedBySafetyFilter), .success(answer("looksFine"))])
        await #expect(throws: LLMAnalyzerError.blockedBySafetyFilter) {
            try await OnDeviceLLMAnalyzer(client: client, log: DebugLog(fileURL: nil)).analyzeInDetail(safeMessage)
        }
        #expect(client.prompts.count == 1)
    }

    @Test func unavailableModelIsLoggedAndNotCalled() async {
        let client = ScriptedClient([], unavailable: .modelUnavailable("deviceNotEligible"))
        let log = DebugLog(fileURL: nil)
        await #expect(throws: LLMAnalyzerError.modelUnavailable("deviceNotEligible")) {
            try await OnDeviceLLMAnalyzer(client: client, log: log).analyzeInDetail(safeMessage)
        }
        #expect(client.prompts.isEmpty)
        #expect(await log.entries().map(\.event) == [.aiUnavailable])
    }

    @Test func inventedQuotesAreDroppedAndLogged() async throws {
        let client = ScriptedClient([
            .success(answer("suspicious", quotes: [("credentialRequest", "share the OTP"), ("suspiciousLink", "bit.ly/xyz")])),
        ])
        let log = DebugLog(fileURL: nil)
        let outcome = try await OnDeviceLLMAnalyzer(client: client, log: log).analyzeInDetail(scamMessage)
        #expect(outcome.validated.result.reasons.map(\.quote) == ["share the OTP"])
        #expect(outcome.attempts == 1)   // a bad quote is dropped, not retried
        #expect(await log.entries().map(\.event) == [.reasonRejected])
    }
}

// MARK: - Combined analyzer: fallback

struct CombinedAnalyzerTests {

    @Test func fallsBackToRulesWhenTheAIFails() async throws {
        let log = DebugLog(fileURL: nil)
        let ai = OnDeviceLLMAnalyzer(client: ScriptedClient([.failure(.blockedBySafetyFilter)]), log: log)
        let combined = CombinedAnalyzer(ai: ai, log: log)

        let result = try await combined.analyze(scamMessage)
        let rulesOnly = try await RuleBasedAnalyzer().analyze(scamMessage)

        #expect(result.verdict == rulesOnly.verdict)
        #expect(result.source == .rules)
        #expect(result.notes.contains { $0.contains("only the built-in rules were used") })
        #expect(await log.entries().map(\.event).contains(.fellBackToRules))
    }

    @Test func emptyMessageIsStillRefused() async {
        await #expect(throws: AnalyzerError.emptyMessage) {
            try await CombinedAnalyzer(ai: OnDeviceLLMAnalyzer(client: ScriptedClient([]), log: DebugLog(fileURL: nil)),
                                       log: DebugLog(fileURL: nil)).analyze("  ")
        }
    }

    @Test func disagreementIsLogged() async throws {
        let log = DebugLog(fileURL: nil)
        // The rules find nothing in this message; the fake AI calls it a scam with real evidence.
        let message = "Hi, please call me back about the money today"
        let ai = OnDeviceLLMAnalyzer(client: ScriptedClient([.success(answer("likelyScam", quotes: [("other", "the money today")]))]), log: log)
        let result = try await CombinedAnalyzer(ai: ai, log: log).analyze(message)

        #expect(result.verdict == .looksFine)      // the AI alone can't raise a warning (policy v2)
        #expect(result.source == .combined)
        #expect(result.notes.contains { $0.contains("AI noticed") })
        #expect(result.reasons.map(\.origin) == [.ai])   // but what it noticed is still shown
        #expect(await log.entries().map(\.event).contains(.rulesAndAIDisagreed))
    }
}

// MARK: - Combination policy (the decision table)

struct CombinationPolicyTests {

    private let message = "URGENT: share the OTP now. Login at sbi-kyc-update.com"

    /// A result with reasons found by quote, so they really are in `message`.
    private func result(_ verdict: Verdict, _ source: AnalysisSource,
                        _ reasons: [(ReasonCategory, String, SignalStrength)]) -> AnalysisResult {
        let origin: ReasonOrigin = source == .llm ? .ai : .rules
        let built = reasons.compactMap {
            Reason(category: $0.0, quote: $0.1, explanation: "Test.", in: message, strength: $0.2, origin: origin)
        }
        #expect(built.count == reasons.count, "every test quote must be in the message")
        return AnalysisResult(message: message, verdict: verdict, reasons: built, source: source)
    }

    @Test func bothSayLikelyScam() {
        let combined = CombinationPolicy.combine(
            rules: result(.likelyScam, .rules, [(.credentialRequest, "share the OTP", .strong), (.urgencyOrThreat, "URGENT", .weak)]),
            ai: result(.likelyScam, .llm, [(.credentialRequest, "share the OTP", .weak)])
        )
        #expect(combined.result.verdict == .likelyScam)
        #expect(!combined.disagreed)
    }

    @Test func strongRuleEvidenceIsEnoughEvenIfAIDisagrees() {
        let combined = CombinationPolicy.combine(
            rules: result(.likelyScam, .rules, [(.credentialRequest, "share the OTP", .strong), (.suspiciousLink, "sbi-kyc-update.com", .strong)]),
            ai: result(.looksFine, .llm, [])
        )
        #expect(combined.result.verdict == .likelyScam)
        #expect(combined.disagreed)
        #expect(combined.result.notes.contains { $0.contains("several strong warning signs") })
    }

    @Test func aiAloneCannotRaiseAWarning() {
        // Policy v2: on the first evaluation, version 1 turned the AI's false
        // alarms into "Suspicious" warnings (precision 0.53).
        let combined = CombinationPolicy.combine(
            rules: result(.looksFine, .rules, []),
            ai: result(.likelyScam, .llm, [(.credentialRequest, "share the OTP", .weak)])
        )
        #expect(combined.result.verdict == .looksFine)
        #expect(combined.disagreed)
        #expect(combined.result.reasons.count == 1)   // still listed as "worth noticing"
    }

    @Test func aiCanConfirmButNotUpgradeOnItsOwn() {
        // Rules: Suspicious (one strong sign). AI: Likely scam. Not both Likely → Suspicious.
        let combined = CombinationPolicy.combine(
            rules: result(.suspicious, .rules, [(.credentialRequest, "share the OTP", .strong)]),
            ai: result(.likelyScam, .llm, [(.credentialRequest, "share the OTP", .weak)])
        )
        #expect(combined.result.verdict == .suspicious)
    }

    @Test func rulesWithOneStrongSignAndAIUnsureIsSuspicious() {
        let combined = CombinationPolicy.combine(
            rules: result(.likelyScam, .rules, [(.credentialRequest, "share the OTP", .strong), (.urgencyOrThreat, "URGENT", .weak)]),
            ai: result(.suspicious, .llm, [(.urgencyOrThreat, "URGENT", .weak)])
        )
        #expect(combined.result.verdict == .suspicious)
    }

    @Test func bothSayLooksFine() {
        let combined = CombinationPolicy.combine(rules: result(.looksFine, .rules, []), ai: result(.looksFine, .llm, []))
        #expect(combined.result.verdict == .looksFine)
        #expect(combined.result.notes.isEmpty)
    }

    @Test func aiFlagWithoutEvidenceDoesNotCount() {
        let combined = CombinationPolicy.combine(rules: result(.looksFine, .rules, []), ai: result(.suspicious, .llm, []))
        #expect(combined.result.verdict == .looksFine)
        #expect(combined.result.notes.contains { $0.contains("couldn't point to exact words") })
    }

    @Test func sameEvidenceIsNotShownTwiceAndOriginsAreKept() {
        let combined = CombinationPolicy.combine(
            rules: result(.suspicious, .rules, [(.credentialRequest, "share the OTP", .strong)]),
            ai: result(.suspicious, .llm, [(.credentialRequest, "the OTP", .weak), (.suspiciousLink, "sbi-kyc-update.com", .weak)])
        )
        let reasons = combined.result.reasons
        #expect(reasons.map(\.quote) == ["share the OTP", "sbi-kyc-update.com"])
        #expect(reasons.map(\.origin) == [.rules, .ai])
        #expect(combined.result.source == .combined)
    }
}

// MARK: - Debug log

struct DebugLogTests {

    @Test func persistsToFileAndReloads() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scamcheck-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        await DebugLog(fileURL: url).record(.aiFailed, detail: "first", message: "Test message one")
        let reopened = DebugLog(fileURL: url)
        await reopened.record(.fellBackToRules, detail: "second", message: nil)

        let entries = await reopened.entries()
        #expect(entries.map(\.detail) == ["first", "second"])
    }

    @Test func keepsOnlyTheNewestEntries() async {
        let log = DebugLog(fileURL: nil)
        for index in 0..<(DebugLog.maxEntries + 5) {
            await log.record(.reasonRejected, detail: "\(index)", message: nil)
        }
        let entries = await log.entries()
        #expect(entries.count == DebugLog.maxEntries)
        #expect(entries.first?.detail == "5")
    }

    @Test func markdownExportIsReadyForWrongAnswers() async {
        let log = DebugLog(fileURL: nil)
        await log.record(.invalidAnswer, detail: "Attempt 1: Missing field.", message: "Test message")
        let markdown = await log.markdown()
        #expect(markdown.contains("**invalidAnswer**"))
        #expect(markdown.contains("Attempt 1: Missing field."))
    }
}
