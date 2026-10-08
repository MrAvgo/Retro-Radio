//
//  SleepTimer.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//
//  Sleep timer: stops playback after 15/30/60/90 minutes. Tapping the moon button
//  cycles through the durations; the remaining minutes show under the icon.
//

import Foundation
import Observation

@MainActor @Observable final class SleepTimer {
    static let options = [15, 30, 60, 90]

    /// Minutes left, or nil when the timer is off.
    private(set) var remainingMinutes: Int?
    /// Fired on the main actor when the countdown reaches zero.
    var onFire: (@MainActor () -> Void)?

    private var task: Task<Void, Never>?

    var isActive: Bool { remainingMinutes != nil }

    /// off -> 15 -> 30 -> 60 -> 90 -> off …
    func cycle() {
        if let current = remainingMinutes,
           let index = Self.options.firstIndex(of: current),
           index + 1 < Self.options.count {
            start(minutes: Self.options[index + 1])
        } else if remainingMinutes != nil {
            cancel()
        } else {
            start(minutes: Self.options[0])
        }
    }

    func start(minutes: Int) {
        cancel()
        remainingMinutes = minutes
        task = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<minutes {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { return }
                await self.tick()
            }
            if Task.isCancelled { return }
            await self.fire()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        remainingMinutes = nil
    }

    private func tick() {
        if let rest = remainingMinutes, rest > 0 {
            remainingMinutes = rest - 1
        }
    }

    private func fire() {
        remainingMinutes = nil
        task = nil
        onFire?()
    }
}
