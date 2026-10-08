//
//  VolumeControl.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//
//  A second rotary knob driving the system volume, the way a real radio has
//  separate tuning and volume knobs. Setting goes through a hidden MPVolumeView
//  slider (no system HUD pops up); the side buttons and Control Center stay in
//  sync through KVO on AVAudioSession.outputVolume.
//

import AVFoundation
import MediaPlayer
import SwiftUI

/// Owns the hidden MPVolumeView slider and mirrors the system volume.
@MainActor @Observable final class VolumeController {
    /// 0...1, kept in sync with the device volume.
    private(set) var volume: Float = AVAudioSession.sharedInstance().outputVolume

    private weak var slider: UISlider?
    private var observation: NSKeyValueObservation?
    private var sliderLookupTask: Task<Void, Never>?

    init() {
        // NSKeyValueObservation invalidates itself on deinit; the stored task only
        // holds weak references, so no manual teardown is needed.
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.initial, .new]) {
            [weak self] _, change in
            guard let newValue = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.volume = newValue
            }
        }
    }

    /// Called by the hidden MPVolumeView wrapper once its slider exists.
    func attach(slider: UISlider) {
        sliderLookupTask?.cancel()
        sliderLookupTask = nil
        self.slider = slider
        volume = slider.value
    }

    /// The slider sometimes isn't in the hierarchy on the first layout pass;
    /// retry once shortly after.
    func attachSoon(from view: MPVolumeView) {
        sliderLookupTask?.cancel()
        sliderLookupTask = Task { [weak self, weak view] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, let view else { return }
            await MainActor.run {
                if let slider = view.subviews.first(where: { $0 is UISlider }) as? UISlider {
                    self.attach(slider: slider)
                }
            }
        }
    }

    func setVolume(_ newValue: Float) {
        let clamped = min(max(newValue, 0), 1)
        volume = clamped
        slider?.setValue(clamped, animated: false)
    }
}

/// A near-invisible MPVolumeView that gives `VolumeController` a real volume slider.
/// It only needs to sit in the window hierarchy; it never intercepts touches.
struct SystemVolumeBridge: UIViewRepresentable {
    let controller: VolumeController

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 4, height: 4))
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        if let slider = view.subviews.first(where: { $0 is UISlider }) as? UISlider {
            controller.attach(slider: slider)
        } else {
            controller.attachSoon(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// The volume knob: a smaller ribbed knob next to the tuning knob.
@MainActor struct VolumeKnobView: View {
    @Bindable var controller: VolumeController
    @State private var lastDragAngle: Double?

    private let size: CGFloat = 84
    /// Knob travel: -135° (silent) to +135° (full).
    private let sweep: Double = 270

    var body: some View {
        TuningKnob(angle: angle, size: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let center = CGPoint(x: size / 2, y: size / 2)
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        // Ignore the dead zone around the hub where angles jump wildly.
                        guard dx * dx + dy * dy > 64 else { return }
                        let angle = atan2(Double(dy), Double(dx)) * 180 / .pi
                        defer { lastDragAngle = angle }
                        guard let previous = lastDragAngle else { return }
                        var delta = angle - previous
                        if delta > 180 { delta -= 360 }
                        if delta < -180 { delta += 360 }
                        controller.setVolume(controller.volume + Float(delta / sweep))
                    }
                    .onEnded { _ in lastDragAngle = nil }
            )
            .accessibilityElement()
            .accessibilityLabel("音量旋钮")
            .accessibilityValue("\(Int((controller.volume * 100).rounded()))%")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: controller.setVolume(controller.volume + 0.05)
                case .decrement: controller.setVolume(controller.volume - 0.05)
                @unknown default: break
                }
            }
    }

    private var angle: Double {
        -sweep / 2 + Double(controller.volume) * sweep
    }
}
