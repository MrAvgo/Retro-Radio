//
//  RetroRadioWidget.swift
//  Retro Radio Widget
//
//  SPDX-License-Identifier: MIT
//
//  Home-screen widget: station name plus a play/pause button that works without
//  opening the app. Tapping the button background-launches the app, which toggles
//  the real player and publishes the new state back here.
//

import AppIntents
import SwiftUI
import WidgetKit

struct RadioWidgetEntry: TimelineEntry {
    let date: Date
    let state: WidgetPlaybackState
}

struct RadioWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RadioWidgetEntry {
        RadioWidgetEntry(date: .now, state: WidgetPlaybackState(stationName: "复古电台", isPlaying: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (RadioWidgetEntry) -> Void) {
        completion(RadioWidgetEntry(date: .now, state: WidgetShared.readState()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RadioWidgetEntry>) -> Void) {
        let entry = RadioWidgetEntry(date: .now, state: WidgetShared.readState())
        // The app reloads timelines on every playback change; this is only a backstop.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct RetroRadioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "one.lxc.retroradio.widget", provider: RadioWidgetProvider()) { entry in
            RadioWidgetView(entry: entry)
        }
        .configurationDisplayName("复古电台")
        .description("在桌面直接播放或暂停，不用打开 App。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RadioWidgetView: View {
    let entry: RadioWidgetEntry
    @Environment(\.widgetFamily) private var family

    // Inlined palette: the widget bundle can't see the app's asset catalog.
    private let amber = Color(red: 1.0, green: 0.70, blue: 0.28)
    private let brass = Color(red: 0.78, green: 0.62, blue: 0.36)
    private let ink = Color(red: 0.08, green: 0.07, blue: 0.05)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.20, green: 0.13, blue: 0.09),
                                    Color(red: 0.09, green: 0.06, blue: 0.04)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 8) {
                Text(entry.state.stationName)
                    .font(.system(size: family == .systemMedium ? 16 : 14, weight: .semibold))
                    .foregroundStyle(amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Button(intent: TogglePlayIntent()) {
                    Image(systemName: entry.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(ink)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(amber))
                }
                .buttonStyle(.plain)
                Text(entry.state.isPlaying ? "播放中" : "已暂停")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(brass)
            }
            .padding()
        }
    }
}

@main
struct RetroRadioWidgetBundle: WidgetBundle {
    var body: some Widget {
        RetroRadioWidget()
    }
}
