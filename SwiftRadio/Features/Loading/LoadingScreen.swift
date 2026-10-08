//
//  LoadingScreen.swift
//  Swift Radio
//
//  Created by Fethi El Hassasna on 2026-09-07.
//
//  SPDX-License-Identifier: MIT
//  See LICENSE in the repository root.
//

import SwiftUI

/// Presents bootstrap progress or a recoverable catalog-loading failure.
@MainActor struct LoadingScreen: View {
    let error: String?
    let retry: () async -> Void

    var body: some View {
        ZStack {
            GradientBackground()
            VStack(spacing: 24) {
                Image(systemName: "radio")
                    .font(.system(size: 96, weight: .light))
                    .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.28))
                    .accessibilityHidden(true)
                if let error {
                    Text("电台列表加载失败").font(.headline)
                    Text(error).multilineTextAlignment(.center)
                    Button("重试") { Task { await retry() } }
                        .buttonStyle(.bordered)
                } else {
                    ProgressView("正在加载电台…")
                }
            }
            .padding()
        }
    }
}
