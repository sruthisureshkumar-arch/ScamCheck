//
//  ScamCheckApp.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  The app's starting point. It creates the one CheckViewModel the app
//  uses and decides WHICH analyzers the user can pick from.
//
//  Phase 1: MockAnalyzer. Phase 2: RuleBasedAnalyzer.
//  Phase 3: adds OnDeviceLLMAnalyzer as a second choice.
//  Phase 4: CombinedAnalyzer (rules + AI, conservative, falls back to the
//  rules if the AI fails) becomes the default. Rules and AI stay available
//  on their own so results can be compared side by side.
//

import SwiftUI

@main
struct ScamCheckApp: App {
    // ⬇︎ The analyzers the user can choose from (first one is the default).
    @State private var viewModel = CheckViewModel(options: [
        AnalyzerOption(id: "combined", title: "Combined", analyzer: CombinedAnalyzer()),
        AnalyzerOption(id: "rules", title: "Rules", analyzer: RuleBasedAnalyzer()),
        AnalyzerOption(id: "ai", title: "AI only", analyzer: OnDeviceLLMAnalyzer()),
    ])

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
