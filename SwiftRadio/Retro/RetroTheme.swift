//
//  RetroTheme.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//

import SwiftUI

/// Warm, restrained palette: walnut cabinet, cream backlit dial, amber display.
enum RetroPalette {
    static let cabinetTop = Color(red: 0.20, green: 0.13, blue: 0.09)
    static let cabinetBottom = Color(red: 0.09, green: 0.06, blue: 0.04)
    static let dialLight = Color(red: 0.97, green: 0.90, blue: 0.74)
    static let dialDeep = Color(red: 0.89, green: 0.76, blue: 0.52)
    static let dialInk = Color(red: 0.27, green: 0.18, blue: 0.11)
    static let brass = Color(red: 0.78, green: 0.62, blue: 0.36)
    static let brassDark = Color(red: 0.45, green: 0.33, blue: 0.17)
    static let needle = Color(red: 0.85, green: 0.20, blue: 0.12)
    static let lcdBackground = Color(red: 0.08, green: 0.07, blue: 0.05)
    static let amber = Color(red: 1.00, green: 0.70, blue: 0.28)
    static let amberDim = Color(red: 1.00, green: 0.70, blue: 0.28).opacity(0.35)
    static let keyFace = Color(red: 0.93, green: 0.89, blue: 0.80)
    static let keyShadow = Color(red: 0.55, green: 0.49, blue: 0.40)
}

/// The cabinet background behind the tuner.
struct CabinetBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [RetroPalette.cabinetTop, RetroPalette.cabinetBottom],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.07), .clear],
                           center: .top, startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
