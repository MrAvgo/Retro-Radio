//
//  PlayRadioIntent.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//
//  Siri / Shortcuts / Spotlight actions. Live in the main app target (no extension), so they
//  need no extra entitlement and work with a free Apple ID signature.
//
//  Both intents run WITHOUT opening the app (`openAppWhenRun = false`): the system
//  background-launches the app, `AppEnvironment` initializes scene-independently, and the
//  `audio` background mode lets playback start/stop from the background. This is the same
//  background-launch path the (now stripped) widget used, and it keeps working even after
//  iOS has terminated the app — which is exactly when the lock-screen card is gone and
//  voice control is the only way back without opening the UI.
//

import AppIntents

struct PlayRadioIntent: AppIntent {
    static var title: LocalizedStringResource { "播放电台" }
    static var description: IntentDescription { "在后台继续播放上次收听的电台，不打开 App 界面。" }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        await AppEnvironment.shared.playLastStation()
        return .result()
    }
}

struct PauseRadioIntent: AppIntent {
    static var title: LocalizedStringResource { "暂停电台" }
    static var description: IntentDescription { "在后台暂停复古电台，不打开 App 界面。" }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.shared.pausePlayback()
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
                "Play radio with \(.applicationName)",
                "用\(.applicationName)播放电台",
                "播放电台"
            ],
            shortTitle: "播放电台",
            systemImageName: "radio"
        )
        AppShortcut(
            intent: PauseRadioIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Stop \(.applicationName)",
                "Pause radio with \(.applicationName)",
                "用\(.applicationName)暂停电台",
                "暂停电台"
            ],
            shortTitle: "暂停电台",
            systemImageName: "pause.circle"
        )
    }
}
