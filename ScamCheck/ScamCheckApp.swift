//
//  ScamCheckApp.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The app's starting point. It creates the one CheckViewModel the app
//  uses and decides WHICH analyzers the user can pick from.
//
//  Phase 1: MockAnalyzer. Phase 2: RuleBasedAnalyzer.
//  Phase 3: adds OnDeviceLLMAnalyzer as a second choice. Rules stay the
//  default because they always work, even when the AI is unavailable.
//

import SwiftUI

@main
struct ScamCheckApp: App {
    // ⬇︎ The analyzers the user can choose from (first one is the default).
    @State private var viewModel = CheckViewModel(options: [
        AnalyzerOption(id: "rules", title: "Rules", analyzer: RuleBasedAnalyzer()),
        AnalyzerOption(id: "ai", title: "On-device AI", analyzer: OnDeviceLLMAnalyzer()),
    ])

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
