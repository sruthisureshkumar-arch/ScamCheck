//
//  LLMClient.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The contract for "something that can ask a language model a question and
//  hand back an LLMVerdict". OnDeviceLLMAnalyzer talks to the model ONLY
//  through this.
//
//  WHY IT EXISTS (Phase 4)
//  To test the wrong-answer handling (retry once, give up, log), the tests
//  need a model that misbehaves on purpose: invalid JSON first, a good answer
//  second, and so on. A fake LLMClient can do that; the real model can't be
//  told to fail. Production uses FoundationModelsClient.
//
//  It also keeps the door open for a different model later (e.g. a remote
//  one): write another LLMClient, nothing else changes.
//

import Foundation

/// Which way the answer was obtained (recorded in the debug log).
nonisolated enum AIPath: String, Codable, Sendable {
    /// Apple guided generation (@Generable), default safety filter.
    case guided
    /// Permissive mode, JSON text decoded with Codable (used when guided was blocked).
    case jsonFallback
    /// A test double.
    case scripted
}

nonisolated struct LLMClientReply: Sendable {
    let answer: LLMVerdict
    let path: AIPath
}

nonisolated protocol LLMClient: Sendable {
    /// Throws LLMAnalyzerError.modelUnavailable if the model can't be used now.
    func checkAvailability() throws
    /// Sends `prompt` to the model. Throws LLMAnalyzerError on failure;
    /// `.invalidAnswer` means "the model answered, but not in a usable form"
    /// and is the only kind of failure worth retrying.
    func reply(to prompt: String) async throws -> LLMClientReply
}
