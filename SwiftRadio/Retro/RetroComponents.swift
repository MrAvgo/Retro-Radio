//
//  RetroComponents.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//

import SwiftUI

// MARK: - Amber display

/// Backlit amber display: station, now playing and status.
struct LCDDisplay: View {
    let stationName: String
    let nowPlaying: String
    let status: String
    let frequency: String
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isLive ? RetroPalette.amber : RetroPalette.amberDim)
                    .frame(width: 7, height: 7)
                    .shadow(color: isLive ? RetroPalette.amber : .clear, radius: 4)
                Text(status)
                Spacer(minLength: 8)
                Text(frequency)
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(RetroPalette.amber.opacity(0.75))

            Text(stationName)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(RetroPalette.amber)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: RetroPalette.amber.opacity(0.55), radius: 6)

            Text(nowPlaying)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(RetroPalette.amber.opacity(0.85))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(RetroPalette.lcdBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.06), .clear],
                                             startPoint: .top, endPoint: .center))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.8), lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(RetroPalette.brassDark.opacity(0.9), lineWidth: 1)
                .padding(-3)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dial face

/// Cream backlit dial with an FM-style scale, station markers and a red needle.
/// `needle` is 0...1 across the scale, or nil when the current station is not on the dial.
struct DialFace: View {
    let stationCount: Int
    let needle: Double?
    let onTapPosition: (Double) -> Void

    let inset: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let usable = max(1, width - inset * 2)
            let count = stationCount
            let pad = inset
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [RetroPalette.dialLight, RetroPalette.dialDeep],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(RadialGradient(colors: [Color.white.opacity(0.45), .clear],
                                         center: .center, startRadius: 4, endRadius: width * 0.55))

                Canvas { [count, pad] context, size in
                    let ink = GraphicsContext.Shading.color(RetroPalette.dialInk)
                    let left = pad
                    let right = size.width - pad
                    let span = max(1, right - left)
                    // FM scale 88-108 with major ticks every 2 MHz and minor every 0.5 MHz.
                    let scaleBaseline = size.height * 0.46
                    var minor = Path()
                    var major = Path()
                    for step in 0...40 {
                        let x = left + span * CGFloat(step) / 40
                        if step % 4 == 0 {
                            major.move(to: CGPoint(x: x, y: scaleBaseline - 14))
                            major.addLine(to: CGPoint(x: x, y: scaleBaseline))
                        } else {
                            minor.move(to: CGPoint(x: x, y: scaleBaseline - 7))
                            minor.addLine(to: CGPoint(x: x, y: scaleBaseline))
                        }
                    }
                    var baseline = Path()
                    baseline.move(to: CGPoint(x: left, y: scaleBaseline))
                    baseline.addLine(to: CGPoint(x: right, y: scaleBaseline))
                    context.stroke(minor, with: ink, lineWidth: 0.8)
                    context.stroke(major, with: ink, lineWidth: 1.4)
                    context.stroke(baseline, with: ink, lineWidth: 1)

                    for mhz in stride(from: 88, through: 108, by: 4) {
                        let x = left + span * CGFloat(mhz - 88) / 20
                        var label = context.resolve(Text("\(mhz)")
                            .font(.system(size: 11, weight: .semibold, design: .serif)))
                        label.shading = ink
                        context.draw(label, at: CGPoint(x: x, y: scaleBaseline - 24))
                    }
                    var fm = context.resolve(Text("FM").font(.system(size: 10, weight: .bold, design: .serif)))
                    fm.shading = ink
                    context.draw(fm, at: CGPoint(x: left - 4, y: 12), anchor: .leading)
                    var mhzLabel = context.resolve(Text("MHz").font(.system(size: 10, weight: .bold, design: .serif)))
                    mhzLabel.shading = ink
                    context.draw(mhzLabel, at: CGPoint(x: right + 4, y: 12), anchor: .trailing)

                    // Station markers along the lower track.
                    let markerY = size.height * 0.72
                    if count > 0 {
                        for index in 0..<count {
                            let fraction = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0.5
                            let x = left + span * fraction
                            let rect = CGRect(x: x - 2.5, y: markerY - 2.5, width: 5, height: 5)
                            context.fill(Path(ellipseIn: rect), with: .color(RetroPalette.brassDark))
                        }
                    }
                }

                if let needle {
                    let x = inset + usable * CGFloat(min(max(needle, 0), 1))
                    Capsule()
                        .fill(RetroPalette.needle)
                        .frame(width: 3, height: height - 16)
                        .shadow(color: RetroPalette.needle.opacity(0.6), radius: 4)
                        .position(x: x, y: height / 2)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: needle)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard stationCount > 0 else { return }
                let fraction = Double((location.x - inset) / usable)
                onTapPosition(min(max(fraction, 0), 1))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LinearGradient(colors: [RetroPalette.brass, RetroPalette.brassDark],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
    }
}

// MARK: - Tuning knob

/// A ribbed rotary knob. Rotation is driven by the parent.
struct TuningKnob: View {
    let angle: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.34), Color(white: 0.10)],
                                     center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 2, endRadius: size * 0.8))
                .shadow(color: .black.opacity(0.65), radius: 10, y: 6)
            ForEach(0..<40, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 2, height: size * 0.08)
                    .offset(y: -size / 2 + size * 0.06)
                    .rotationEffect(.degrees(Double(index) * 9))
            }
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.22)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.62, height: size * 0.62)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
            Circle()
                .fill(RetroPalette.amber)
                .frame(width: size * 0.07, height: size * 0.07)
                .shadow(color: RetroPalette.amber, radius: 3)
                .offset(y: -size * 0.22)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
    }
}

// MARK: - Preset key

/// One mechanical preset key: number plus a short station name.
struct PresetKey: View {
    let number: Int
    let title: String?
    let isActive: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("\(number)")
                .font(.system(size: 17, weight: .bold, design: .serif))
            Text(title ?? "—")
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(RetroPalette.dialInk)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [RetroPalette.keyFace, RetroPalette.keyFace.opacity(0.82)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(isActive ? 0.2 : 0.55), radius: isActive ? 1 : 3,
                        y: isActive ? 1 : 3)
        )
        .overlay(alignment: .top) {
            Capsule()
                .fill(isActive ? RetroPalette.amber : Color.clear)
                .frame(width: 18, height: 3)
                .shadow(color: isActive ? RetroPalette.amber : .clear, radius: 3)
                .padding(.top, 4)
        }
        .offset(y: isActive ? 2 : 0)
        .opacity(title == nil ? 0.75 : 1)
    }
}
