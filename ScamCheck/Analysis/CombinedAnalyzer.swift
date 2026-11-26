//
//  CombinedAnalyzer.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The analyzer the app uses by default from Phase 4: it runs the rules AND
//  the on-device AI, then combines them with CombinationPolicy.
//
//  FALLBACK
//  If the AI can't give a usable answer (unavailable, blocked, two unusable
//  answers in a row...), the user still gets an answer: the rules' result,
//  with a note saying the AI wasn't used. The app never shows a dead end
//  just because the AI failed.
//
//  Everything that goes wrong is written to the DebugLog.
//

import Foundation

nonisolated struct CombinedAnalyzer: MessageAnalyzer {

    let rules: RuleBasedAnalyzer
    let ai: OnDeviceLLMAnalyzer
    let log: DebugLog

    init(
        rules: RuleBasedAnalyzer = RuleBasedAnalyzer(),
        ai: OnDeviceLLMAnalyzer = OnDeviceLLMAnalyzer(),
        log: DebugLog = .shared
    ) {
        self.rules = rules
        self.ai = ai
        self.log = log
    }

    func analyze(_ message: String) async throws -> AnalysisResult {
        // Rules first: fast, and they also reject an empty message.
        let rulesResult = try await rules.analyze(message)

        let outcome: LLMOutcome
        do {
            outcome = try await ai.analyzeInDetail(message)
        } catch {
            await log.record(.fellBackToRules, detail: "AI failed: \(error)", message: message)
            return rulesResult.adding(notes: [
                "The on-device AI couldn't check this message, so only the built-in rules were used.",
            ])
        }

        let combination = CombinationPolicy.combine(rules: rulesResult, ai: outcome.validated.result)
        if combination.disagreed {
            await log.record(
                .rulesAndAIDisagreed,
                detail: "Rules: \(rulesResult.verdict.rawValue), AI: \(outcome.validated.result.verdict.rawValue) (path: \(outcome.path.rawValue)) → \(combination.result.verdict.rawValue)",
                message: message
            )
        }
        return combination.result
    }
}
