//
//  RadioPresets.swift
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

/// Six preset buttons. A slot keeps a full station so it still plays after the station is
/// removed from My Stations.
@MainActor @Observable final class RadioPresets {
    static let slotCount = 6
    private static let key = "retro.presets"

    private(set) var slots: [SwiftRadioCore.RadioStation?]

    init(defaultStations: [SwiftRadioCore.RadioStation]) {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([SwiftRadioCore.RadioStation?].self, from: data) {
            slots = Self.normalized(saved)
        } else {
            // First launch: fill the presets with the first stations of the seed list.
            slots = Self.normalized(defaultStations.prefix(Self.slotCount).map { Optional($0) })
            persist()
        }
    }

    func station(at slot: Int) -> SwiftRadioCore.RadioStation? {
        slots.indices.contains(slot) ? slots[slot] : nil
    }

    func save(_ station: SwiftRadioCore.RadioStation, to slot: Int) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = station
        persist()
    }

    func clear(slot: Int) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = nil
        persist()
    }

    /// Keeps presets pointing at a station after it was edited in My Stations.
    func replace(_ old: SwiftRadioCore.RadioStation, with new: SwiftRadioCore.RadioStation) {
        var changed = false
        for index in slots.indices where slots[index]?.id == old.id {
            slots[index] = new
            changed = true
        }
        if changed { persist() }
    }

    func contains(streamURL: String) -> Bool {
        slots.contains { $0?.streamURL == streamURL }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private static func normalized(_ values: [SwiftRadioCore.RadioStation?]) -> [SwiftRadioCore.RadioStation?] {
        var result = Array(values.prefix(slotCount))
        while result.count < slotCount { result.append(nil) }
        return result
    }
}
