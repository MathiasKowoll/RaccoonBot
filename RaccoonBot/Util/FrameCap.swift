//
//  FrameCap.swift
//  RaccoonBot
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

/// Which frame rates a cap can hold on a display, and what to hand D3DMetal 4
/// so it holds the one chosen.
///
/// D3DMetal 4 enforces D3DM_MAX_FPS with presentDrawable:afterMinimumDuration:
/// (read from its binary): each frame is shown no sooner than 1/cap after the
/// one before. A display only shows frames at multiples of its update
/// granularity. This machine's ProMotion panel reports 1/240 s, between 1/120
/// and 1/24 s (NSScreen, 2026-09-26), so the rates it holds are 240/n: 120, 80,
/// 60, 48, 40, 34.3, 30, 26.7, 24. A cap of 60 asks for "no sooner than
/// 16.67 ms", the 60 Hz slot sits at exactly 16.67 ms, and the smallest delay
/// pushes a frame past it to the next slot, 20.83 ms: 48 fps. Measured by the
/// user the same day: any cap from 48 to 60 held 48, and a cap of 70 held 60.00
/// with a flat 16.67 ms frame interval.
///
/// So the slider offers only the rates the display holds, and D3DMetal is
/// handed a value between the chosen rate and the next faster one -- the
/// midpoint of their frame durations. 60 becomes 69: the 60 Hz slot is then the
/// first a frame may land in, and the 80 Hz one is still too early.
nonisolated enum FrameCap {

    struct Display: Equatable, Sendable {
        var minInterval: Double
        var maxInterval: Double
        var granularity: Double
        var maxFPS: Int
    }

    /// The display this was measured on, for when none can be read.
    static let promotion = Display(minInterval: 1.0 / 120, maxInterval: 1.0 / 24,
                                   granularity: 1.0 / 240, maxFPS: 120)

    /// Anything at or below this reads as "no cap" elsewhere (`> 20`).
    static let floor: Double = 20

    /// Every rate the display holds, fastest first, its own maximum included.
    ///
    /// A variable-refresh display holds whole multiples of its granularity
    /// between its shortest and longest interval. One with a single rate --
    /// the same shortest and longest interval, or no granularity -- holds its
    /// divisors.
    static func allRates(on d: Display) -> [Double] {
        if d.granularity > 0, d.minInterval > 0 {
            let first = Int((d.minInterval / d.granularity).rounded())
            let last = Int((d.maxInterval / d.granularity).rounded())
            if first >= 1, last > first {
                return (first...last).map { 1 / (Double($0) * d.granularity) }
            }
        }
        let top = d.maxFPS > 0 ? Double(d.maxFPS) : (d.minInterval > 0 ? (1 / d.minInterval).rounded() : 0)
        guard top > floor else { return [] }
        return (1...Int(top / floor)).map { top / Double($0) }.filter { $0 > floor }
    }

    /// The rates a cap can be set to: all but the display's own maximum, which
    /// would be no cap at all.
    static func rates(on d: Display) -> [Double] {
        Array(allRates(on: d).dropFirst())
    }

    /// The rate a stored value holds on this display: the fastest one not
    /// above it, or the slowest offered when it is below them all. Half a frame
    /// of slack, because a rate is stored rounded (34.3 as 34).
    static func snapped(_ value: Double, on d: Display) -> Double? {
        let offered = rates(on: d)
        guard let slowest = offered.last else { return nil }
        return offered.first { $0 <= value + 0.5 } ?? slowest
    }

    /// What D3DM_MAX_FPS is given for a stored cap, or nil when the display
    /// offers nothing to hold.
    static func envValue(for value: Double, on d: Display) -> Int? {
        guard !isNoLimit(value, on: d), let rate = snapped(value, on: d) else { return nil }
        let all = allRates(on: d)
        guard let i = all.firstIndex(of: rate), i > 0 else { return nil }
        return Int((2 / (1 / rate + 1 / all[i - 1])).rounded())
    }

    /// The display's own maximum. As a cap it is no cap at all, so it is the
    /// slider's top stop and reads as "No limit" -- the same state as the
    /// switch being off.
    static func maximum(on d: Display) -> Double? { allRates(on: d).first }

    /// Whether a stored value means no cap: off (20 or below, which the launch
    /// line has always taken as off), or the display's maximum or more. A value
    /// above the maximum was possible with the old 19...240 slider, and on this
    /// display it never limited anything.
    static func isNoLimit(_ value: Double, on d: Display) -> Bool {
        if value <= floor { return true }
        guard let top = maximum(on: d) else { return false }
        return value >= top - 0.5
    }

    /// The slider's stops, slowest first, ending with the display's maximum.
    static func stops(on d: Display) -> [Double] {
        Array(allRates(on: d).filter { $0 > floor }.reversed())
    }

    /// Which stop a stored value sits at: the top one for no cap.
    static func stopIndex(for value: Double, on d: Display) -> Int {
        let s = stops(on: d)
        guard !s.isEmpty else { return 0 }
        guard !isNoLimit(value, on: d), let held = snapped(value, on: d),
              let i = s.firstIndex(of: held) else { return s.count - 1 }
        return i
    }

    /// What a stop stores: the rate, rounded, or 0 -- off -- for the top one.
    static func stored(forStop index: Int, on d: Display) -> Double {
        let s = stops(on: d)
        guard !s.isEmpty else { return 0 }
        let i = min(max(index, 0), s.count - 1)
        return i == s.count - 1 ? 0 : s[i].rounded()
    }

    /// The next stop up or down, for the controller. Up from the fastest rate
    /// is no limit.
    static func nudged(_ value: Double, forward: Bool, on d: Display) -> Double {
        let i = stopIndex(for: value, on: d)
        return stored(forStop: forward ? i + 1 : i - 1, on: d)
    }

    static func label(_ rate: Double) -> String { "\(Int(rate.rounded()))" }

    /// The main display, as macOS describes its refresh.
    @MainActor static func mainDisplay() -> Display? {
        guard let s = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return Display(minInterval: s.minimumRefreshInterval, maxInterval: s.maximumRefreshInterval,
                       granularity: s.displayUpdateGranularity, maxFPS: s.maximumFramesPerSecond)
    }
}
