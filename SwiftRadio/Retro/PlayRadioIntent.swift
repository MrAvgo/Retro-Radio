//
//  PlayRadioIntent.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//
//  Siri / Shortcuts / Spotlight action. Lives in the main app target (no extension), so it
//  needs no extra entitlement and works with a free Apple ID signature.
//

import AppIntents

struct PlayRadioIntent: AppIntent {
    static var title: LocalizedStringResource { "播放电台" }
    static var description: IntentDescription { "打开复古电台并继续播放上次收听的电台。" }
    /// Opening the app guarantees the audio session can start from the foreground.
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        await AppEnvironment.shared.playLastStation()
        return .result()
    }
}

struct RetroRadioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayRadioIntent(),
            phrases: [
                "Play \(.applicationName)",
                "Start \(.applicationName)",
                "Play radio with \(.applicationName)"
            ],
            shortTitle: "播放电台",
            systemImageName: "radio"
        )
    }
}
