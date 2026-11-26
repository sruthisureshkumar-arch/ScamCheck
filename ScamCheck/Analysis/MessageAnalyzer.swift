//
//  MessageAnalyzer.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The contract every analyzer must follow: give it a message, get back an
//  AnalysisResult (or an error).
//
//  WHY A PROTOCOL
//  The screen and view model only know about "some MessageAnalyzer". That
//  lets us swap the mock (Phase 1) for the rules (Phase 2), the language
//  model (Phase 3) or the combined version (Phase 4) without touching the UI.
//  It also makes testing easy: tests can pass in any analyzer they like.
//
//  `async throws` because the language model version will take time and can
//  fail. The mock and rules versions simply return quickly.
//

import Foundation

nonisolated protocol MessageAnalyzer: Sendable {
    func analyze(_ message: String) async throws -> AnalysisResult
}

/// An error that carries a calm, plain-language message for the user.
/// The view model shows `userMessage` instead of technical error text.
nonisolated protocol UserFacingError: Error {
    var userMessage: String { get }
}

/// Errors any analyzer may throw.
nonisolated enum AnalyzerError: Error, Equatable {
    /// The message was empty or only spaces.
    case emptyMessage
}
