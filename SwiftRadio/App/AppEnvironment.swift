//
//  AppEnvironment.swift
//  Swift Radio
//
//  Created by Fethi El Hassasna on 2026-09-07.
//
//  SPDX-License-Identifier: MIT
//  See LICENSE in the repository root.
//

import Observation
import OSLog
import SwiftRadioCore

/// Composes the single playback owner, shared stores, and scene-independent artwork updates.
@MainActor final class AppEnvironment {
    /// The single intentional application global: UIKit CarPlay and SwiftUI share this instance.
    /// AppDelegate initializes it at launch. The audio session is activated by PlayerService when
    /// playback starts, not here: activating on launch would stop other apps' audio.
    static let shared = AppEnvironment()

    let stations: StationsStore
    let player: PlayerService
    let artwork: ArtworkLoader
    /// The user's editable station list that feeds `stations`.
    let library: MyStationsLibrary
    let presets: RadioPresets
    /// Sleep timer; stopping playback on fire.
    let sleepTimer = SleepTimer()
    private var stationArtworkTask: Task<Void, Never>?
    private var trackArtworkTask: Task<Void, Never>?

    private init() {
        let engine: any RadioPlaying
        #if DEBUG
        // Opt-in only: UI regressions exercise the real app without relying on remote streams.
        engine = ProcessInfo.processInfo.arguments.contains("--ui-test-playback")
            ? UITestRadioPlayer() : PlayerService.makeRadioPlayer()
        #else
        engine = PlayerService.makeRadioPlayer()
        #endif
        let commands = RemoteCommandsController()
        #if DEBUG
        if engine is UITestRadioPlayer {
            // A fake engine produces no audio: owning the session would only gate UI tests on the
            // simulator's audio server. Session behaviour is covered by the core package tests.
            player = PlayerService(player: engine, nowPlaying: NowPlayingInfoPublisher(),
                                   remoteCommands: commands, activateAudioSession: nil)
        } else {
            player = PlayerService(player: engine, nowPlaying: NowPlayingInfoPublisher(), remoteCommands: commands,
                                   mixesWithOtherAudio: Config.mixesWithOtherAudio)
        }
        #else
        player = PlayerService(player: engine, nowPlaying: NowPlayingInfoPublisher(), remoteCommands: commands,
                               mixesWithOtherAudio: Config.mixesWithOtherAudio)
        #endif
        // Seeds My Stations on first launch before the store's first load reads it.
        let library = MyStationsLibrary()
        self.library = library
        presets = RadioPresets(defaultStations: library.stations)
        stations = StationsStore(loader: MyStationsLoader(), player: player)
        artwork = ArtworkLoader()
        commands.bind(player: player, stations: stations)
        library.onChange = { [weak self] change in self?.libraryDidChange(change) }
        sleepTimer.onFire = { [weak self] in self?.player.stop() }
        observeArtwork()
        observeLastStation()
        if Config.debugLog { observePlayback() }
    }

    private func observeArtwork() {
        let (station, url) = withObservationTracking {
            (stations.currentStation, player.artworkURL)
        } onChange: { [weak self] in
            // Observation fires before mutation; re-read and re-register on the next actor turn.
            Task { @MainActor [weak self] in self?.observeArtwork() }
        }
        stationArtworkTask?.cancel()
        trackArtworkTask?.cancel()
        guard let station else { return }
        stationArtworkTask = Task { [weak self, artwork] in
            let image = await artwork.image(for: station)
            guard !Task.isCancelled, let self, stations.currentStation?.id == station.id else { return }
            player.updateArtwork(image, for: station.id, artworkURL: nil)
        }
        if let url {
            trackArtworkTask = Task { [weak self, artwork] in
                let image = await artwork.trackArtwork(at: url)
                guard !Task.isCancelled, let self, stations.currentStation?.id == station.id,
                      player.artworkURL == url else { return }
                player.updateArtwork(image, for: station.id, artworkURL: url)
            }
        }
    }

    // MARK: - Retro radio: resume, autoplay and library sync

    /// Remembers the most recent station so the next launch (or Siri) can resume it.
    private func observeLastStation() {
        let station = withObservationTracking {
            stations.currentStation
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeLastStation() }
        }
        if let station { PlaybackMemory.lastStation = station }
    }

    /// Called when the app opens. Respects the "打开 App 自动播放" setting.
    func autoplayOnOpen() {
        guard PlaybackMemory.autoplayOnOpen else { return }
        resumePlayback()
    }

    /// Siri / Shortcuts entry point: make sure the catalog is loaded, then play.
    func playLastStation() async {
        if stations.loadState != .loaded || stations.stations.isEmpty {
            await stations.load()
        }
        resumePlayback()
    }

    /// Plays the current station, else the last-played one, else the first of My Stations.
    /// Never pauses: a playing or still-loading stream is left alone, a failed one is reloaded.
    func resumePlayback() {
        guard let station = stations.currentStation ?? rememberedStation() ?? stations.stations.first else { return }
        stations.activate(station, on: .carPlay)
    }

    private func rememberedStation() -> SwiftRadioCore.RadioStation? {
        guard let last = PlaybackMemory.lastStation else { return nil }
        if let match = stations.stations.first(where: { $0.streamURL == last.streamURL }) { return match }
        // A station tuned from a preset or the search screen need not be in My Stations.
        return presets.contains(streamURL: last.streamURL) ? last : nil
    }

    /// Reloads the shared store after an edit and keeps the current stream going when it still exists.
    private func libraryDidChange(_ change: MyStationsChange) {
        let current = stations.currentStation
        let wasActive = player.state == .playing || player.isBuffering
        var keepPlaying = current
        switch change {
        case .edited(let old, let new):
            presets.replace(old, with: new)
            if current?.id == old.id { keepPlaying = new }
            if PlaybackMemory.lastStation?.id == old.id { PlaybackMemory.lastStation = new }
        case .deleted(let removed):
            if let current, removed.contains(where: { $0.id == current.id }) { keepPlaying = nil }
        case .added, .reordered, .reset:
            break
        }
        Task { [weak self] in
            guard let self else { return }
            await self.stations.load()
            // The store unloads a current station that left the catalog (or changed identity);
            // restart it when the user only edited or reordered.
            if wasActive, let keepPlaying, self.stations.currentStation?.id != keepPlaying.id {
                self.stations.select(keepPlaying)
            }
        }
    }

    private func observePlayback() {
        let (state, readiness) = withObservationTracking {
            (player.state, player.readiness)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observePlayback() }
        }
        Logger(subsystem: "SwiftRadio", category: "Playback")
            .info("Player state: \(String(describing: state), privacy: .public), readiness: \(String(describing: readiness), privacy: .public)")
    }
}
