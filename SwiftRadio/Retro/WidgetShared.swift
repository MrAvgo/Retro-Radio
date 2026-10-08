//
//  WidgetShared.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//
//  Shared between the main app and the widget extension (compiled into both):
//  the App Group used to publish playback state, and the play/pause intent behind
//  the widget button. The intent is performed in the main app process — the system
//  background-launches the app when the widget button is tapped — where the app
//  has registered its handler. It compiles in the widget extension too, which only
//  needs the type to build the button.
//

import AppIntents
import Foundation

/// App Group shared by the app and the widget. Both targets list it in their entitlements.
enum WidgetShared {
    static let appGroupID = "group.one.lxc.retroradio"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static let stateKey = "widget.playbackState"

    static func readState() -> WidgetPlaybackState {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(WidgetPlaybackState.self, from: data)
        else {
            return WidgetPlaybackState(stationName: "复古电台", isPlaying: false)
        }
        return state
    }

    static func writeState(_ state: WidgetPlaybackState) {
        guard let defaults = sharedDefaults,
              let data = try? JSONEncoder().encode(state)
        else { return }
        defaults.set(data, forKey: stateKey)
    }
}

/// What the widget shows. Written by the main app whenever playback changes.
struct WidgetPlaybackState: Codable, Sendable {
    var stationName: String
    var isPlaying: Bool
}

/// Bridge from the widget intent to the real player, which only exists in the main
/// app. The main app registers its handler at launch; the widget extension process
/// never sets it (and never needs to — perform() runs in the app process).
enum WidgetPlaybackBridge {
    /// Set once by the main app at launch.
    static var toggleHandler: (@Sendable () async -> Void)?
}

/// Widget button: toggles playback without opening the app UI.
struct TogglePlayIntent: AppIntent {
    static var title: LocalizedStringResource { "播放/暂停" }
    static var description: IntentDescription { "在不打开复古电台界面的情况下播放或暂停。" }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        await WidgetPlaybackBridge.toggleHandler?()
        return .result()
    }
}
