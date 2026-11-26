//
//  OnDeviceLLMAnalyzer.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The AI analyzer. It asks a language model (through an LLMClient) to check
//  the message, validates the answer, and handles wrong answers.
//
//  HANDLING WRONG ANSWERS (Phase 4)
//  - If the answer is unusable (invalid JSON, a missing field, a verdict or
//    confidence that fails validation), ask AGAIN ONCE, telling the model
//    exactly what was wrong. If the second answer is also unusable, give up
//    with an error. CombinedAnalyzer then falls back to the rules.
//  - Other failures (model unavailable, safety filter, timeout) are NOT
//    retried: asking the same thing again won't change them.
//  - Reasons whose quote isn't in the message are dropped by the validator
//    (not a reason to retry: the rest of the answer may be fine).
//  - Every failure, retry and dropped reason is written to the DebugLog.
//
//  WHY ON-DEVICE (Phase 3)
//  Privacy (the message never leaves the phone), no API key, no network.
//

import Foundation

nonisolated enum LLMAnalyzerError: Error, Equatable, UserFacingError {
    case modelUnavailable(String)
    case messageTooLong
    case blockedBySafetyFilter
    case modelRefused
    case invalidAnswer(String)
    case generationFailed(String)

    var userMessage: String {
        switch self {
        case .modelUnavailable:
            "On-device AI isn't available on this device right now. Try the Rules checker."
        case .messageTooLong:
            "This message is too long for the on-device AI. Try the Rules checker."
        case .blockedBySafetyFilter, .modelRefused:
            "The on-device AI declined to check this message. Try the Rules checker."
        case .invalidAnswer, .generationFailed:
            "The on-device AI gave an answer that couldn't be used. Try again or use the Rules checker."
        }
    }
}

/// Everything about one AI check, for CombinedAnalyzer and the tests.
nonisolated struct LLMOutcome: Sendable {
    let validated: ValidatedLLMAnswer
    let path: AIPath
    /// 1, or 2 if the first answer had to be retried.
    let attempts: Int
}

nonisolated struct OnDeviceLLMAnalyzer: MessageAnalyzer {

    /// Keeps the prompt well inside the model's context window.
    static let maxMessageLength = 2_000

    /// How many times to ask in total (first try + one retry).
    static let maxAttempts = 2

    let client: any LLMClient
    let log: DebugLog

    init(client: any LLMClient = FoundationModelsClient(), log: DebugLog = .shared) {
        self.client = client
        self.log = log
    }

    static func prompt(for message: String, retryFeedback: String? = nil) -> String {
        var text = """
            Message to check:
            <<<
            \(message)
            >>>
            """
        if let retryFeedback {
            text += """


                Your previous answer could not be used: \(retryFeedback)
                Answer again. Follow the format exactly, use only the allowed values, \
                and quote only words that appear exactly in the message.
                """
        }
        return text
    }

    func analyze(_ message: String) async throws -> AnalysisResult {
        try await analyzeInDetail(message).validated.result
    }

    func analyzeInDetail(_ message: String) async throws -> LLMOutcome {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalyzerError.emptyMessage
        }
        guard message.count <= Self.maxMessageLength else {
            throw LLMAnalyzerError.messageTooLong
        }

        do {
            try client.checkAvailability()
        } catch {
            await log.record(.aiUnavailable, detail: String(describing: error), message: message)
            throw error
        }

        var feedback: String?
        for attempt in 1...Self.maxAttempts {
            do {
                let reply = try await client.reply(to: Self.prompt(for: message, retryFeedback: feedback))
                if reply.path == .jsonFallback {
                    await log.record(.guidedBlockedUsedJSON, detail: "Guided generation was blocked or refused; the JSON path answered.", message: message)
                }

                let validated: ValidatedLLMAnswer
                do {
                    validated = try LLMVerdictValidator.validate(reply.answer, for: message)
                } catch {
                    throw LLMAnalyzerError.invalidAnswer(Self.describe(error))
                }

                for rejected in validated.rejectedReasons {
                    await log.record(.reasonRejected, detail: rejected.why, message: message)
                }
                if attempt > 1 {
                    await log.record(.retrySucceeded, detail: "Attempt \(attempt) was usable (path: \(reply.path.rawValue)).", message: message)
                }

                var result = validated.result
                if attempt > 1 {
                    result = result.adding(notes: ["The AI's first answer couldn't be used, so it was asked again."])
                }
                return LLMOutcome(
                    validated: ValidatedLLMAnswer(result: result, rejectedReasons: validated.rejectedReasons),
                    path: reply.path,
                    attempts: attempt
                )
            } catch LLMAnalyzerError.invalidAnswer(let detail) where attempt < Self.maxAttempts {
                await log.record(.invalidAnswer, detail: "Attempt \(attempt): \(detail) Retrying once.", message: message)
                feedback = detail
            } catch {
                await log.record(.aiFailed, detail: "Attempt \(attempt): \(error)", message: message)
                throw error
            }
        }
        // The loop always returns or throws; this line is never reached.
        throw LLMAnalyzerError.generationFailed("No attempts were made.")
    }

    /// Turns a validation error into a sentence the model can act on.
    private static func describe(_ error: Error) -> String {
        switch error as? LLMValidationError {
        case .unknownVerdict(let value)?:
            "\"verdict\" was \"\(value)\" but must be likelyScam, suspicious or looksFine."
        case .confidenceOutOfRange(let value)?:
            "\"confidence\" was \(value) but must be between 0.0 and 1.0."
        case nil:
            String(describing: error)
        }
    }
}
