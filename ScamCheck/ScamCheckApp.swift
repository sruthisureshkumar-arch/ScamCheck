//
//  ScamCheckApp.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The app's starting point. It creates the one CheckViewModel the app
//  uses and decides WHICH analyzer it gets.
//
//  To switch analyzers in later phases, change only the line marked below.
//

import SwiftUI

@main
struct ScamCheckApp: App {
    // ⬇︎ The analyzer the app uses.
    // Phase 1: MockAnalyzer (fake). Phase 2: RuleBasedAnalyzer (real rules).
    @State private var viewModel = CheckViewModel(analyzer: RuleBasedAnalyzer())

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
