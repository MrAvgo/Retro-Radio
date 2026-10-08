//
//  MyStationsLibrary.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//

import Foundation
import Observation
import SwiftRadioCore
import SwiftUI

/// On-disk storage for "My Stations": a JSON file in Application Support using the same
/// envelope as the bundled `stations.json`, so both decode with `StationsResponse`.
enum MyStationsFile {
    static var url: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("my-stations.json")
    }

    static func read() throws -> [SwiftRadioCore.RadioStation] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StationsResponse.self, from: data).station
    }

    static func write(_ stations: [SwiftRadioCore.RadioStation]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(StationsResponse(station: stations))
        try data.write(to: url, options: .atomic)
    }

    /// The seed catalog shipped in the app bundle.
    static func bundled() -> [SwiftRadioCore.RadioStation] {
        guard let url = Bundle.main.url(forResource: "stations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let response = try? JSONDecoder().decode(StationsResponse.self, from: data) else { return [] }
        return response.station
    }
}

/// Feeds `StationsStore` from the user's own list, so the dial, Next/Previous and the
/// lock-screen commands all walk "My Stations".
struct MyStationsLoader: StationsLoader {
    func load() async throws -> [SwiftRadioCore.RadioStation] {
        if let saved = try? MyStationsFile.read() { return saved }
        return MyStationsFile.bundled()
    }
}

/// What changed in the library, so the composition root can keep playback sensible.
enum MyStationsChange: Sendable {
    case added
    case edited(old: SwiftRadioCore.RadioStation, new: SwiftRadioCore.RadioStation)
    case deleted([SwiftRadioCore.RadioStation])
    case reordered
    case reset
}

/// The editable source of truth for "My Stations". Every mutation is written to disk first and
/// then announced through `onChange`, which reloads the shared `StationsStore`.
@MainActor @Observable final class MyStationsLibrary {
    private(set) var stations: [SwiftRadioCore.RadioStation]
    @ObservationIgnored var onChange: (@MainActor (MyStationsChange) -> Void)?

    init() {
        if let saved = try? MyStationsFile.read() {
            stations = saved
        } else {
            let seed = MyStationsFile.bundled()
            stations = seed
            try? MyStationsFile.write(seed)
        }
    }

    func contains(streamURL: String) -> Bool {
        stations.contains { Self.sameStream($0.streamURL, streamURL) }
    }

    /// Returns an error message in Chinese, or nil on success.
    @discardableResult func add(_ station: SwiftRadioCore.RadioStation) -> String? {
        if let problem = Self.validate(name: station.name, streamURL: station.streamURL) { return problem }
        guard !contains(streamURL: station.streamURL) else { return "这个电台已经在“我的电台”里了" }
        stations.append(station)
        commit(.added)
        return nil
    }

    @discardableResult func update(_ old: SwiftRadioCore.RadioStation,
                                   to new: SwiftRadioCore.RadioStation) -> String? {
        if let problem = Self.validate(name: new.name, streamURL: new.streamURL) { return problem }
        guard let index = stations.firstIndex(where: { $0.id == old.id }) else { return "找不到要修改的电台" }
        let duplicate = stations.indices.contains { other in
            other != index && Self.sameStream(stations[other].streamURL, new.streamURL)
        }
        guard !duplicate else { return "已有电台使用这个地址" }
        stations[index] = new
        commit(.edited(old: old, new: new))
        return nil
    }

    func delete(at offsets: IndexSet) {
        let removed = offsets.compactMap { stations.indices.contains($0) ? stations[$0] : nil }
        guard !removed.isEmpty else { return }
        stations.remove(atOffsets: offsets)
        commit(.deleted(removed))
    }

    func delete(_ station: SwiftRadioCore.RadioStation) {
        guard let index = stations.firstIndex(where: { $0.id == station.id }) else { return }
        delete(at: IndexSet(integer: index))
    }

    func move(from source: IndexSet, to destination: Int) {
        stations.move(fromOffsets: source, toOffset: destination)
        commit(.reordered)
    }

    func restoreDefaults() {
        stations = MyStationsFile.bundled()
        commit(.reset)
    }

    private func commit(_ change: MyStationsChange) {
        try? MyStationsFile.write(stations)
        onChange?(change)
    }

    static func validate(name: String, streamURL: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写电台名称" }
        guard let url = URL(string: streamURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              !(url.host ?? "").isEmpty else {
            return "请填写以 http:// 或 https:// 开头的流地址"
        }
        return nil
    }

    private static func sameStream(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
