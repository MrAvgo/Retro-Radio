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
import UIKit
import WidgetKit

/// Outcome of a manual logo re-fetch (`AppEnvironment.refreshLogo`).
enum RefreshLogoResult {
    /// A new logo URL was found and saved.
    case found(String)
    /// Discovery found the same URL as before; nothing changed.
    case unchanged
    /// Nothing better was found; the previous logo (if any) was restored.
    case keptOld
    /// Nothing found and there was no previous logo.
    case notFound
}

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
        stations = StationsStore(loader: MyStationsLoader(), player: player)
        artwork = ArtworkLoader()
        commands.bind(player: player, stations: stations)
        library.onChange = { [weak self] change in self?.libraryDidChange(change) }
        sleepTimer.onFire = { [weak self] in self?.player.stop() }
        WidgetPlaybackBridge.toggleHandler = {
            await AppEnvironment.shared.handleWidgetToggle()
        }
        observeArtwork()
        observeWidgetState()
        observeLastStation()
        observeLogoDiscovery()
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

    // MARK: - Widget: background play/pause without opening the UI

    /// Widget button entry point. Runs in the app process after the system
    /// background-launches the app; the UI is never shown.
    func handleWidgetToggle() async {
        if player.state == .playing || player.isBuffering {
            player.pause()
        } else {
            if stations.loadState != .loaded { await stations.load() }
            resumePlayback()
        }
        publishWidgetState()
    }

    /// Publishes the playback state to the App Group and asks WidgetKit to redraw.
    private func publishWidgetState() {
        WidgetShared.writeState(WidgetPlaybackState(
            stationName: stations.currentStation?.name ?? "复古电台",
            isPlaying: player.state == .playing || player.isBuffering
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Re-publishes whenever the station or playback state changes.
    private func observeWidgetState() {
        let snapshot = withObservationTracking {
            WidgetPlaybackState(
                stationName: self.stations.currentStation?.name ?? "复古电台",
                isPlaying: self.player.state == .playing || self.player.isBuffering
            )
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeWidgetState() }
        }
        WidgetShared.writeState(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
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

    // MARK: - Logo discovery

    /// Stations already tried this launch (hit or miss); misses are retried next launch.
    private var logoDiscoveryAttempted: Set<String> = []

    /// Short-timeout session for favicon/HTML fetches; discovery must not hang the UI.
    private static let discoverySession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    /// When tuning to a station that has no logo URL, try its website favicon.
    /// A hit is written back to the library (persisted), so preset keys and lists
    /// pick it up; the check runs on every tune, as requested.
    private func observeLogoDiscovery() {
        let station = withObservationTracking {
            stations.currentStation
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeLogoDiscovery() }
        }
        guard let station else { return }
        Task { [weak self] in await self?.discoverLogoIfNeeded(for: station) }
    }

    private func discoverLogoIfNeeded(for station: SwiftRadioCore.RadioStation) async {
        guard station.imageURL.isEmpty else { return }
        guard let website = station.website, !website.isEmpty,
              URL(string: website)?.host != nil else { return }
        guard logoDiscoveryAttempted.insert(station.id).inserted else { return }

        guard let found = await discoverLogoURL(for: station) else { return }
        var updated = station
        updated.imageURL = found
        if let index = library.stations.firstIndex(where: { $0.id == station.id }) {
            _ = library.update(library.stations[index], to: updated)
        }
    }

    /// Manual re-fetch: clears any existing (possibly wrong) logo and re-runs
    /// discovery, bypassing the once-per-launch guard. Restores the old URL when
    /// nothing better is found, so a failed refresh never loses the old logo.
    func refreshLogo(for station: SwiftRadioCore.RadioStation) async -> RefreshLogoResult {
        logoDiscoveryAttempted.remove(station.id)
        let oldURL = station.imageURL
        var cleared = station
        cleared.imageURL = ""
        guard let index = library.stations.firstIndex(where: { $0.id == station.id }) else {
            return .notFound
        }
        _ = library.update(library.stations[index], to: cleared)
        await discoverLogoIfNeeded(for: cleared)

        if let newURL = library.stations.first(where: { $0.id == station.id })?.imageURL,
           !newURL.isEmpty {
            // Discovery may return the same URL we just cleared; that is not an update.
            return newURL == oldURL ? .unchanged : .found(newURL)
        }
        if !oldURL.isEmpty,
           let index = library.stations.firstIndex(where: { $0.id == station.id }) {
            var restored = cleared
            restored.imageURL = oldURL
            _ = library.update(library.stations[index], to: restored)
            return .keptOld
        }
        return .notFound
    }

    /// Candidate logo URLs for a station, best-first: `<link rel="icon">` hints
    /// from the website HTML, then the conventional root locations.
    private func discoverLogoURL(for station: SwiftRadioCore.RadioStation) async -> String? {
        guard let website = station.website, !website.isEmpty,
              let pageURL = URL(string: website),
              let host = pageURL.host, !host.isEmpty else { return nil }

        var candidates: [String] = []
        if let links = await iconLinks(from: pageURL) {
            candidates.append(contentsOf: links)
        }
        candidates.append("https://\(host)/apple-touch-icon.png")
        candidates.append("https://\(host)/favicon.ico")

        for urlString in candidates {
            guard let url = URL(string: urlString),
                  await isValidFavicon(at: url) else { continue }
            return urlString
        }
        return nil
    }

    /// Parses `<link rel="icon" href="…">` (and apple-touch-icon variants) out of
    /// a website's HTML. Apple-touch icons come first; data: URLs are skipped.
    private func iconLinks(from pageURL: URL) async -> [String]? {
        guard let (data, response) = try? await Self.discoverySession.data(from: pageURL),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= 2_000_000,
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }

        guard let tagRegex = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: .caseInsensitive),
              let hrefRegex = try? NSRegularExpression(pattern: #"href\s*=\s*["']([^"']+)["']"#, options: .caseInsensitive)
        else { return nil }

        var touchIcons: [String] = []
        var otherIcons: [String] = []
        let fullRange = NSRange(html.startIndex..., in: html)
        for match in tagRegex.matches(in: html, range: fullRange) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard tag.range(of: #"rel\s*=\s*["'][^"']*icon[^"']*["']"#,
                            options: [.regularExpression, .caseInsensitive]) != nil,
                  let hrefMatch = hrefRegex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  hrefMatch.numberOfRanges > 1,
                  let hrefRange = Range(hrefMatch.range(at: 1), in: tag)
            else { continue }
            let href = String(tag[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, !href.lowercased().hasPrefix("data:"),
                  let absolute = URL(string: href, relativeTo: pageURL)?.absoluteURL,
                  let scheme = absolute.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else { continue }
            let urlString = absolute.absoluteString
            let isTouch = tag.range(of: "apple-touch-icon", options: .caseInsensitive) != nil
            if isTouch, !touchIcons.contains(urlString) {
                touchIcons.append(urlString)
            } else if !isTouch, !otherIcons.contains(urlString) {
                otherIcons.append(urlString)
            }
        }
        let all = touchIcons + otherIcons
        return all.isEmpty ? nil : all
    }

    private func isValidFavicon(at url: URL) async -> Bool {
        guard let (data, response) = try? await Self.discoverySession.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let image = UIImage(data: data),
              min(image.size.width, image.size.height) >= 16 else { return false }
        return true
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

    /// Siri / Shortcuts entry point: pause without opening the UI. Runs fine from a
    /// background launch; pausing needs no audio session and no station catalog.
    func pausePlayback() {
        player.pause()
    }

    /// Plays the current station, else the last-played one, else the first of My Stations.
    /// Never pauses: a playing or still-loading stream is left alone, a failed one is reloaded.
    func resumePlayback() {
        guard let station = stations.currentStation ?? rememberedStation() ?? stations.stations.first else { return }
        stations.activate(station, on: .carPlay)
    }

    private func rememberedStation() -> SwiftRadioCore.RadioStation? {
        guard let last = PlaybackMemory.lastStation else { return nil }
        // Presets are the first six of My Stations now, so the catalog check covers them.
        return stations.stations.first(where: { $0.streamURL == last.streamURL })
    }

    /// Reloads the shared store after an edit and keeps the current stream going when it still exists.
    private func libraryDidChange(_ change: MyStationsChange) {
        let current = stations.currentStation
        let wasActive = player.state == .playing || player.isBuffering
        var keepPlaying = current
        switch change {
        case .edited(let old, let new):
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
