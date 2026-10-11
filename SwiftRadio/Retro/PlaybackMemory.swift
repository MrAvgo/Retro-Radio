//
//  PlaybackMemory.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//

import Foundation
import Observation
import SwiftRadioCore

/// UserDefaults keys, kept nonisolated so property wrappers can use them.
enum RetroDefaultsKey {
    static let autoplayOnOpen = "retro.autoplayOnOpen"
}

/// Small values remembered between launches in UserDefaults.
@MainActor enum PlaybackMemory {
    private static let lastStationKey = "retro.lastStation"
    /// Shared with the `@AppStorage` toggle in My Stations.
    static var autoplayKey: String { RetroDefaultsKey.autoplayOnOpen }

    /// The station that was playing most recently, stored whole so it survives catalog edits.
    static var lastStation: SwiftRadioCore.RadioStation? {
        get {
            guard let data = UserDefaults.standard.data(forKey: lastStationKey) else { return nil }
            return try? JSONDecoder().decode(SwiftRadioCore.RadioStation.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: lastStationKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastStationKey)
            }
        }
    }

    /// Defaults to on: opening the app should start the radio.
    static var autoplayOnOpen: Bool {
        UserDefaults.standard.object(forKey: autoplayKey) as? Bool ?? true
    }
}


