//
//  StationSearchView.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//

import SwiftRadioCore
import SwiftUI

/// Searches the Radio Browser directory by name, country and tag; tap to preview, + to add.
@MainActor struct StationSearchView: View {
    @Environment(MyStationsLibrary.self) private var library
    @Environment(StationsStore.self) private var stations
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var query = RadioSearchQuery(chineseOnly: true)
    @State private var results: [RadioBrowserStation] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?
    @State private var notice: String?

    private let client = RadioBrowserClient()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("电台名称（可留空）", text: $query.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { runSearch() }
                    TextField("标签，例如 jazz、news、classical", text: $query.tag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { runSearch() }
                    Toggle("只看中文电台", isOn: $query.chineseOnly)
                    Picker("国家/地区", selection: $query.countryCode) {
                        ForEach(SearchCountry.all) { country in
                            Text(country.title).tag(country.code)
                        }
                    }
                    .disabled(query.chineseOnly)
                    Button { runSearch() } label: {
                        HStack {
                            Spacer()
                            if isSearching {
                                ProgressView()
                            } else {
                                Label("搜索", systemImage: "magnifyingglass")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSearching)
                } footer: {
                    Text("数据来自免费的 Radio Browser 电台库。开启“只看中文”时会搜索中文/普通话/粤语以及中国大陆、台湾、香港、澳门的电台。")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                if hasSearched && !isSearching && results.isEmpty && errorMessage == nil {
                    Section {
                        Text("没有找到电台，换个关键词试试。").foregroundStyle(.secondary)
                    }
                }

                if !results.isEmpty {
                    Section {
                        ForEach(results) { result in
                            resultRow(result)
                        }
                    } header: {
                        Text("结果（\(results.count)）· 轻点试听")
                    }
                }
            }
            .navigationTitle("电台库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let notice {
                    Text(notice)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(RetroPalette.lcdBackground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(RetroPalette.amber))
                        .padding(.bottom, 24)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .task(id: notice) {
                guard notice != nil else { return }
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                withAnimation { notice = nil }
            }
            .task {
                if !hasSearched { runSearch() }
            }
            .onDisappear { searchTask?.cancel() }
        }
        .tint(RetroPalette.amber)
    }

    private func resultRow(_ result: RadioBrowserStation) -> some View {
        let station = result.radioStation
        let isCurrent = stations.currentStation?.streamURL == station.streamURL
        let isAdded = library.contains(streamURL: station.streamURL)
        return HStack(spacing: 12) {
            Button {
                stations.activate(station, on: .carPlay)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isCurrent && player.state == .playing ? "speaker.wave.2.fill" : "play.circle")
                        .foregroundStyle(isCurrent ? RetroPalette.amber : .secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.displayName)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(result.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if isAdded { return }
                if let message = library.add(station) {
                    notice = message
                } else {
                    notice = "已添加到我的电台"
                }
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isAdded ? Color.green : RetroPalette.amber)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isAdded ? "已在我的电台" : "添加到我的电台")
        }
    }

    private func runSearch() {
        searchTask?.cancel()
        let current = query
        isSearching = true
        errorMessage = nil
        searchTask = Task {
            do {
                let found = try await client.search(current)
                guard !Task.isCancelled else { return }
                results = found
                hasSearched = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                hasSearched = true
                errorMessage = "搜索失败，请检查网络后重试。"
            }
            isSearching = false
        }
    }
}

/// Country filter options for the search screen.
struct SearchCountry: Identifiable, Sendable {
    let code: String
    let title: String
    var id: String { code }

    static let all: [SearchCountry] = [
        SearchCountry(code: "", title: "全部"),
        SearchCountry(code: "CN", title: "中国大陆"),
        SearchCountry(code: "TW", title: "台湾"),
        SearchCountry(code: "HK", title: "香港"),
        SearchCountry(code: "MO", title: "澳门"),
        SearchCountry(code: "SG", title: "新加坡"),
        SearchCountry(code: "MY", title: "马来西亚"),
        SearchCountry(code: "JP", title: "日本"),
        SearchCountry(code: "KR", title: "韩国"),
        SearchCountry(code: "US", title: "美国"),
        SearchCountry(code: "CA", title: "加拿大"),
        SearchCountry(code: "GB", title: "英国"),
        SearchCountry(code: "FR", title: "法国"),
        SearchCountry(code: "DE", title: "德国"),
        SearchCountry(code: "AU", title: "澳大利亚")
    ]
}
