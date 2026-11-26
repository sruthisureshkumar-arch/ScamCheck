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
//  It is given one or more analyzers when created (see ScamCheckApp.swift).
//  With more than one, the screen shows a picker (e.g. Rules / On-device AI)
//  so the two can be compared side by side, which is handy in a demo.
//
//  `@Observable` makes SwiftUI redraw automatically when a property changes.
//  This class runs on the main thread (the project's default), which is what
//  UI state needs.
//

import Foundation
import Observation

/// One analyzer the user can choose, with the name shown in the picker.
struct AnalyzerOption: Identifiable {
    let id: String
    let title: String
    let analyzer: any MessageAnalyzer
}

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

    /// All analyzers the user can pick from. Never empty.
    let options: [AnalyzerOption]

    /// The analyzer currently chosen in the picker.
    var selectedOptionID: String

    private var analyzer: any MessageAnalyzer {
        (options.first { $0.id == selectedOptionID } ?? options[0]).analyzer
    }

    init(options: [AnalyzerOption]) {
        precondition(!options.isEmpty, "CheckViewModel needs at least one analyzer")
        self.options = options
        self.selectedOptionID = options[0].id
    }

    /// Convenience for a single analyzer (used by previews and tests).
    convenience init(analyzer: any MessageAnalyzer) {
        self.init(options: [AnalyzerOption(id: "default", title: "Default", analyzer: analyzer)])
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
        } catch let error as UserFacingError {
            state = .failed(error.userMessage)
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
