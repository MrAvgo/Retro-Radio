//
//  MyStationsView.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//

import SwiftRadioCore
import SwiftUI

/// Add, edit, delete and reorder My Stations. The dial tunes across this list in this order.
@MainActor struct MyStationsView: View {
    @Environment(MyStationsLibrary.self) private var library
    @Environment(StationsStore.self) private var stations
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss
    @AppStorage(RetroDefaultsKey.autoplayOnOpen) private var autoplayOnOpen = true
    @State private var draft: StationDraft?
    @State private var confirmReset = false
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if library.stations.isEmpty {
                        Text("还没有电台。点右上角 + 添加，或从电台库搜索。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.stations) { station in
                        Button {
                            stations.activate(station, on: .carPlay)
                        } label: {
                            row(for: station)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { library.delete(station) } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button { draft = StationDraft(editing: station) } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button { draft = StationDraft(editing: station) } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            Button(role: .destructive) { library.delete(station) } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { library.delete(at: $0) }
                    .onMove { library.move(from: $0, to: $1) }
                } header: {
                    Text("我的电台（\(library.stations.count)）")
                } footer: {
                    Text("旋钮和刻度盘按这个顺序调台。左滑可编辑或删除，点“编辑”可拖动排序。")
                }

                Section {
                    Button { showSearch = true } label: {
                        Label("从电台库搜索添加", systemImage: "magnifyingglass")
                    }
                    Button { draft = StationDraft() } label: {
                        Label("手动添加电台（名称 + 流地址）", systemImage: "plus")
                    }
                }

                Section {
                    Toggle("打开 App 时自动播放", isOn: $autoplayOnOpen)
                    Button("恢复默认电台列表", role: .destructive) { confirmReset = true }
                } header: {
                    Text("设置")
                } footer: {
                    Text("开启后，从主屏幕点开 App 就会继续播放上次的电台。")
                }
            }
            .navigationTitle("我的电台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { draft = StationDraft() } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加电台")
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $draft) { item in
                StationEditorView(draft: item) { result in
                    save(result)
                }
            }
            .sheet(isPresented: $showSearch) {
                StationSearchView()
                    .environment(stations)
                    .environment(player)
                    .environment(library)
            }
            .confirmationDialog("恢复默认电台列表？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("恢复默认", role: .destructive) { library.restoreDefaults() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("你添加的电台会被清除，预设按钮不受影响。")
            }
        }
        .tint(RetroPalette.amber)
    }

    private func row(for station: SwiftRadioCore.RadioStation) -> some View {
        let isCurrent = station.id == stations.currentStation?.id
        return HStack(spacing: 12) {
            Image(systemName: isCurrent && player.state == .playing ? "speaker.wave.2.fill" : "radio")
                .foregroundStyle(isCurrent ? RetroPalette.amber : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(station.desc.isEmpty ? station.streamURL : station.desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Returns an error message to keep the editor open, or nil when saved.
    private func save(_ result: StationDraft) -> String? {
        let station = result.makeStation()
        if let original = result.original {
            return library.update(original, to: station)
        }
        return library.add(station)
    }
}

/// Form state for adding or editing a station.
struct StationDraft: Identifiable {
    let id = UUID()
    var original: SwiftRadioCore.RadioStation?
    var name = ""
    var streamURL = ""
    var desc = ""

    init() {}

    init(editing station: SwiftRadioCore.RadioStation) {
        original = station
        name = station.name
        streamURL = station.streamURL
        desc = station.desc
    }

    func makeStation() -> SwiftRadioCore.RadioStation {
        SwiftRadioCore.RadioStation(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            website: original?.website,
            streamURL: streamURL.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURL: original?.imageURL ?? "",
            desc: desc.trimmingCharacters(in: .whitespacesAndNewlines),
            longDesc: original?.longDesc ?? ""
        )
    }
}

@MainActor struct StationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StationDraft
    @State private var error: String?
    let onSave: (StationDraft) -> String?

    init(draft: StationDraft, onSave: @escaping (StationDraft) -> String?) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("电台名称", text: $draft.name)
                    TextField("流地址，例如 https://example.com/live.mp3", text: $draft.streamURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("简介（可选）", text: $draft.desc)
                } footer: {
                    Text("支持 MP3 / AAC / HLS (.m3u8) 等直播流地址。")
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(draft.original == nil ? "添加电台" : "编辑电台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let message = onSave(draft) {
                            error = message
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
        .tint(RetroPalette.amber)
    }
}
