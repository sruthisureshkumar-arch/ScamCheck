//
//  CheckViewModel.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The "brain" behind the screen (the VM in MVVM). It holds what the user
//  typed, whether a check is running, and the latest result. The views only
//  read this state and call its methods; they contain no analysis logic.
//
//  HOW IT CONNECTS
//  It is given a MessageAnalyzer when created (see ScamCheckApp.swift).
//  Swapping the mock for the real analyzer later is a one-line change there.
//
//  `@Observable` makes SwiftUI redraw automatically when a property changes.
//  This class runs on the main thread (the project's default), which is what
//  UI state needs.
//

import Foundation
import Observation

@Observable
final class CheckViewModel {

    enum State: Equatable {
        case idle
        case checking
        case failed(String)
    }

    /// The text in the message box.
    var messageText = ""

    /// Whether a check is running or the last one failed.
    private(set) var state: State = .idle

    /// The latest result. When this is non-nil the result card is shown;
    /// setting it back to nil hides the card.
    var result: AnalysisResult?

    private let analyzer: any MessageAnalyzer

    init(analyzer: any MessageAnalyzer) {
        self.analyzer = analyzer
    }

    /// The Check button is only enabled when there is something to check
    /// and no check is already running.
    var canCheck: Bool {
        state != .checking
            && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Called by the Paste button with whatever text was on the clipboard.
    func paste(_ strings: [String]) {
        guard let first = strings.first else { return }
        messageText = first
        state = .idle
    }

    /// Runs the analyzer and stores the result.
    func check() async {
        guard canCheck else { return }
        state = .checking
        result = nil
        do {
            result = try await analyzer.analyze(messageText)
            state = .idle
        } catch {
            // Never show raw error text to the user; keep it calm and clear.
            state = .failed("Couldn't check this message. Please try again.")
        }
    }

    /// Hides the result card. The message stays so the user can edit it.
    func dismissResult() {
        result = nil
    }

    /// Empties the message box and resets everything.
    func clear() {
        messageText = ""
        result = nil
        state = .idle
    }
}
