//
//  RootView.swift
//  Swift Radio
//
//  Created by Fethi El Hassasna on 2026-09-07.
//  Retro radio rework: the retro tuner is the whole phone UI and playback starts on open.
//
//  SPDX-License-Identifier: MIT
//  See LICENSE in the repository root.
//

import SwiftRadioCore
import SwiftUI

/// Loads My Stations, shows the retro tuner, and starts playback when the app is opened.
@MainActor struct RootView: View {
    @Environment(StationsStore.self) private var stations
    @Environment(\.scenePhase) private var scenePhase
    @State private var bootstrapped = false
    @State private var backgroundedAt: Date?

    /// Returning from the background after at least this long counts as "opening the app" again,
    /// so a tap on the home-screen icon resumes the radio. Quick app switches are ignored.
    private static let reopenThreshold: TimeInterval = 20

    var body: some View {
        Group {
            if bootstrapped {
                RetroRadioView()
            } else {
                LoadingScreen(error: loadingError) { await stations.load() }
            }
        }
        .task {
            if stations.loadState == .idle { await stations.load() }
        }
        .onChange(of: stations.loadState, initial: true) { _, state in
            guard state == .loaded, !bootstrapped else { return }
            bootstrapped = true
            // Top priority: one tap on the icon starts the last station.
            AppEnvironment.shared.autoplayOnOpen()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                if let since = backgroundedAt, bootstrapped,
                   Date().timeIntervalSince(since) >= Self.reopenThreshold {
                    AppEnvironment.shared.autoplayOnOpen()
                }
                backgroundedAt = nil
            default:
                break
            }
        }
    }

    private var loadingError: String? {
        if case .failed(let message) = stations.loadState { return message }
        return nil
    }
}
