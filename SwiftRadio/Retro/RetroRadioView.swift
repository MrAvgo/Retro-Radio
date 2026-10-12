//
//  RetroRadioView.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//
//  The whole phone UI: amber display, backlit dial with needle, six presets, play/pause and a
//  rotary tuning knob. Playback goes through the shared SwiftRadioCore StationsStore/PlayerService.
//

import SwiftRadioCore
import SwiftUI

@MainActor struct RetroRadioView: View {
    @Environment(StationsStore.self) private var stations
    @Environment(PlayerService.self) private var player
    @Environment(MyStationsLibrary.self) private var library
    @Environment(SleepTimer.self) private var sleepTimer

    /// Station index the knob/dial is pointing at while the user is tuning; nil follows playback.
    @State private var tunedIndex: Int?
    @State private var volumeController = VolumeController()
    @State private var lastDragAngle: Double?
    @State private var stepAccumulator: Double = 0
    @State private var tickCount = 0
    @State private var toast: String?
    @State private var showMyStations = false
    @State private var showSearch = false

    /// Degrees of knob rotation per station step.
    private let degreesPerStep: Double = 28
    private let knobSize: CGFloat = 112

    var body: some View {
        ZStack {
            CabinetBackground()
            VStack(spacing: 14) {
                header
                LCDDisplay(stationName: displayStationName,
                           nowPlaying: nowPlayingText,
                           status: statusText,
                           frequency: frequencyText,
                           isLive: player.state == .playing)
                DialFace(stationCount: stations.stations.count, needle: needlePosition) { fraction in
                    tune(toFraction: fraction)
                }
                .frame(height: 118)
                .accessibilityLabel("调谐刻度盘")
                presetRow
                Spacer(minLength: 0)
                controls
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(RetroPalette.lcdBackground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(RetroPalette.amber))
                        .shadow(radius: 6)
                        .padding(.bottom, 200)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .tint(RetroPalette.amber)
        .background {
            // Keeps a real volume slider in the hierarchy so the volume knob can
            // drive the system volume without showing the HUD.
            SystemVolumeBridge(controller: volumeController)
                .frame(width: 4, height: 4)
                .opacity(0.02)
                .allowsHitTesting(false)
        }
        .sensoryFeedback(.selection, trigger: tickCount)
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
        .sheet(isPresented: $showMyStations) {
            MyStationsView()
                .environment(stations)
                .environment(player)
                .environment(library)
        }
        .sheet(isPresented: $showSearch) {
            StationSearchView()
                .environment(stations)
                .environment(player)
                .environment(library)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text("复古电台")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(RetroPalette.brass)
            Spacer()
            Button { sleepTimer.cycle() } label: {
                VStack(spacing: 1) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 17))
                    Text("\(sleepTimer.remainingMinutes ?? 0)′")
                        .font(.system(size: 8, weight: .semibold))
                }
                .frame(width: 40, height: 40)
            }
            .accessibilityLabel(sleepTimer.isActive
                                ? "睡眠定时：还剩 \(sleepTimer.remainingMinutes ?? 0) 分钟"
                                : "睡眠定时")
            .accessibilityHint("轻点切换 15、30、60、90 分钟后停止播放")
            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("搜索电台")
            Button { showMyStations = true } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("我的电台")
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(RetroPalette.brass)
    }

    /// Six preset keys bound live to the first six of My Stations: reordering or
    /// editing the list updates the keys automatically. Each key shows the
    /// station's logo when one can be loaded, otherwise the default key face.
    private var presetRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { slot in
                    let station: RadioStation? = slot < stations.stations.count ? stations.stations[slot] : nil
                    PresetKey(number: slot + 1,
                              station: station,
                              isActive: station != nil && station?.id == stations.currentStation?.id)
                        .contentShape(Rectangle())
                        .onTapGesture { if let station { playPreset(station) } }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("预设 \(slot + 1)：\(station?.name ?? "空")")
                        .accessibilityHint("轻点播放")
                        .accessibilityAddTraits(.isButton)
                }
            }
            Text("预设对应「我的电台」\(stations.stations.count) 个中的前 6 个")
                .font(.system(size: 10))
                .foregroundStyle(RetroPalette.brass.opacity(0.6))
                .frame(maxWidth: .infinity)
        }
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(spacing: 6) {
                TuningKnob(angle: tuningKnobAngle, size: knobSize)
                    .contentShape(Circle())
                    .gesture(knobGesture)
                    .accessibilityElement()
                    .accessibilityLabel("调谐旋钮")
                    .accessibilityValue(displayStationName)
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: step(1, commit: true)
                        case .decrement: step(-1, commit: true)
                        @unknown default: break
                        }
                    }
                Text("转动调台")
                    .font(.system(size: 10))
                    .foregroundStyle(RetroPalette.brass.opacity(0.6))
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Button { togglePlayback() } label: {
                    Image(systemName: isActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(RetroPalette.lcdBackground)
                        .frame(width: 84, height: 84)
                        .background(
                            Circle().fill(LinearGradient(colors: [RetroPalette.amber, RetroPalette.brass],
                                                         startPoint: .top, endPoint: .bottom))
                        )
                        .overlay(Circle().strokeBorder(RetroPalette.brassDark, lineWidth: 2))
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
                }
                .accessibilityLabel(isActive ? "暂停" : "播放")
                Text(isActive ? "暂停" : "播放")
                    .font(.system(size: 10))
                    .foregroundStyle(RetroPalette.brass.opacity(0.6))
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                VolumeKnobView(controller: volumeController, size: knobSize)
                Text("音量")
                    .font(.system(size: 10))
                    .foregroundStyle(RetroPalette.brass.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Derived display values

    private var currentIndex: Int? {
        guard let current = stations.currentStation else { return nil }
        return stations.stations.firstIndex { $0.id == current.id }
    }

    private var pointedIndex: Int? { tunedIndex ?? currentIndex }

    private var pointedStation: SwiftRadioCore.RadioStation? {
        if let tunedIndex, stations.stations.indices.contains(tunedIndex) { return stations.stations[tunedIndex] }
        return stations.currentStation
    }

    private var needlePosition: Double? {
        let count = stations.stations.count
        guard count > 0 else { return nil }
        guard let index = pointedIndex else { return stations.currentStation == nil ? 0 : nil }
        return count > 1 ? Double(index) / Double(count - 1) : 0.5
    }

    /// Tuning knob dot angle, absolute like the needle: -135° at the first
    /// station, +135° at the last, so the dot always sits on the same side
    /// as the needle. While dragging, the in-progress detent fraction adds
    /// smooth geared motion; at rest (accumulator = 0) it matches exactly.
    private var tuningKnobAngle: Double {
        let count = stations.stations.count
        let fraction = needlePosition ?? 0
        var angle = -135 + 270 * fraction
        if count > 1 {
            let perStationDegrees = 270 / Double(count - 1)
            angle += (stepAccumulator / degreesPerStep) * perStationDegrees
        }
        return angle
    }

    private var frequencyText: String {
        guard let position = needlePosition else { return "FM --.-" }
        return String(format: "FM %.1f", 88.0 + 20.0 * position)
    }

    private var displayStationName: String {
        pointedStation?.name ?? "未选择电台"
    }

    private var isActive: Bool {
        player.state == .playing || player.isBuffering
    }

    private var statusText: String {
        if tunedIndex != nil { return "调谐中…" }
        if case .failed = player.state { return "无法播放" }
        if player.isBuffering { return "缓冲中…" }
        switch player.state {
        case .playing: return "播放中"
        case .paused: return "已暂停"
        case .stopped: return "已停止"
        case .idle, .failed: return stations.currentStation == nil ? "待机" : "就绪"
        }
    }

    private var nowPlayingText: String {
        if tunedIndex != nil { return pointedStation?.desc ?? "" }
        guard let station = stations.currentStation else { return "转动旋钮或按预设开始收听" }
        if case .failed = player.state { return "无法连接这个电台，请换一个试试" }
        let track = player.track?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = player.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !track.isEmpty {
            return artist.isEmpty ? track : "\(artist) — \(track)"
        }
        return station.desc.isEmpty ? "正在收听" : station.desc
    }

    // MARK: Actions

    private func togglePlayback() {
        guard let current = stations.currentStation else {
            AppEnvironment.shared.resumePlayback()
            return
        }
        if case .failed = player.state {
            stations.select(current)
        } else {
            player.togglePlayPause()
        }
    }

    private func playPreset(_ station: RadioStation) {
        tunedIndex = nil
        stations.activate(station, on: .carPlay)
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
    }

    /// Moves the pointer by whole stations; `commit` tunes immediately (buttons, VoiceOver).
    /// Stops at the first/last station; no wrap-around.
    private func step(_ delta: Int, commit: Bool) {
        let count = stations.stations.count
        guard count > 0 else { return }
        let start = pointedIndex ?? (delta > 0 ? -1 : count)
        let target = min(max(start + delta, 0), count - 1)
        if target != pointedIndex {
            tunedIndex = target
            tickCount += 1
        }
        if commit { commitTuning() }
    }

    private func tune(toFraction fraction: Double) {
        let count = stations.stations.count
        guard count > 0 else { return }
        let target = Int((fraction * Double(count - 1)).rounded())
        if target != pointedIndex {
            tunedIndex = target
            tickCount += 1
        }
        commitTuning()
    }

    /// Starts the station under the needle, if it differs from what is already playing.
    private func commitTuning() {
        defer { tunedIndex = nil }
        guard let index = tunedIndex, stations.stations.indices.contains(index) else { return }
        let station = stations.stations[index]
        if station.id == stations.currentStation?.id && isActive { return }
        stations.activate(station, on: .carPlay)
    }

    private var knobGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let center = CGPoint(x: knobSize / 2, y: knobSize / 2)
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                // Ignore the dead zone around the hub where angles jump wildly.
                guard dx * dx + dy * dy > 144 else { return }
                let angle = atan2(Double(dy), Double(dx)) * 180 / .pi
                defer { lastDragAngle = angle }
                guard let previous = lastDragAngle else { return }
                var delta = angle - previous
                if delta > 180 { delta -= 360 }
                if delta < -180 { delta += 360 }
                stepAccumulator += delta
                while abs(stepAccumulator) >= degreesPerStep {
                    let direction = stepAccumulator > 0 ? 1 : -1
                    stepAccumulator -= Double(direction) * degreesPerStep
                    stepPointer(direction)
                }
            }
            .onEnded { _ in
                lastDragAngle = nil
                stepAccumulator = 0
                commitTuning()
            }
    }

    /// Knob detent: move the needle one station without starting playback yet.
    /// Stops at the ends; hitting an end drops the accumulated excess so
    /// reversing direction responds immediately.
    private func stepPointer(_ delta: Int) {
        let count = stations.stations.count
        guard count > 0 else { return }
        let start = pointedIndex ?? (delta > 0 ? -1 : count)
        let target = min(max(start + delta, 0), count - 1)
        guard target != pointedIndex else {
            stepAccumulator = 0
            return
        }
        tunedIndex = target
        tickCount += 1
    }
}
