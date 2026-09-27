//
//  FrameCapTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

@Suite("A frame-rate cap the display can hold")
struct DisplayFrameCapTests {

    private let promotion = FrameCap.promotion
    private let fixed60 = FrameCap.Display(minInterval: 1.0 / 60, maxInterval: 1.0 / 60, granularity: 1.0 / 60, maxFPS: 60)

    private func near(_ a: [Double], _ b: [Double]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 0.01 }
    }

    // MARK: - What the display holds

    /// Measured from NSScreen on 2026-09-26: 1/240 s between 1/120 and 1/24.
    @Test func theProMotionPanelHolds240OverN() {
        #expect(near(FrameCap.rates(on: promotion), [80, 60, 48, 40, 34.2857, 30, 26.6667, 24]))
    }

    @Test func itsOwnMaximumIsNotOfferedBecauseItIsNoCap() {
        #expect(!FrameCap.rates(on: promotion).contains { abs($0 - 120) < 0.01 })
    }

    @Test func aSingleRateDisplayHoldsItsDivisors() {
        #expect(near(FrameCap.rates(on: fixed60), [30]))
        let noGranularity = FrameCap.Display(minInterval: 1.0 / 144, maxInterval: 1.0 / 144, granularity: 0, maxFPS: 144)
        #expect(near(FrameCap.rates(on: noGranularity), [72, 48, 36, 28.8, 24, 20.5714]))
    }

    // MARK: - A stored value

    @Test func aStoredValueHoldsTheFastestRateNotAboveIt() {
        #expect(FrameCap.snapped(60, on: promotion) == 60)
        #expect(FrameCap.snapped(55, on: promotion) == 48)
        #expect(FrameCap.snapped(100, on: promotion) == 80)
        #expect(FrameCap.snapped(240, on: promotion) == 80)
        #expect(FrameCap.snapped(10, on: promotion) == 24)
    }

    /// The value the user set to test the diagnosis stays a 60.
    @Test func theSeventyTheUserSetReadsAsSixty() {
        #expect(FrameCap.snapped(70, on: promotion) == 60)
    }

    /// Rates are stored rounded, so 34.3 is kept as 34 and must still read as it.
    @Test func aRoundedRateReadsAsItself() {
        #expect(abs((FrameCap.snapped(34, on: promotion) ?? 0) - 34.2857) < 0.01)
        #expect(abs((FrameCap.snapped(27, on: promotion) ?? 0) - 26.6667) < 0.01)
    }

    // MARK: - What D3DMetal is handed

    /// Measured: a cap of 70 held 60.00. The midpoint gives 69.
    @Test func sixtyIsHandedOverAsSixtyNine() {
        #expect(FrameCap.envValue(for: 60, on: promotion) == 69)
    }

    /// Strictly between the rate and the next faster one, for every rate:
    /// equal to the rate is the 48 the user saw, equal to the faster one lets
    /// the faster one through.
    @Test func everyValueHandedOverSitsBetweenItsRateAndTheNextFaster() {
        let all = FrameCap.allRates(on: promotion)
        for rate in FrameCap.rates(on: promotion) {
            let i = all.firstIndex(of: rate)!
            let handed = Double(FrameCap.envValue(for: rate.rounded(), on: promotion)!)
            #expect(handed > rate && handed < all[i - 1], "rate \(rate) handed \(handed)")
        }
    }

    @Test func theOtherRatesAreHandedOverAsExpected() {
        #expect(FrameCap.envValue(for: 80, on: promotion) == 96)
        #expect(FrameCap.envValue(for: 48, on: promotion) == 53)
        #expect(FrameCap.envValue(for: 40, on: promotion) == 44)
        #expect(FrameCap.envValue(for: 30, on: promotion) == 32)
        #expect(FrameCap.envValue(for: 24, on: promotion) == 25)
        #expect(FrameCap.envValue(for: 30, on: fixed60) == 40)
    }

    @Test func aDisplayWithNothingToHoldHandsNothingOver() {
        let tiny = FrameCap.Display(minInterval: 0, maxInterval: 0, granularity: 0, maxFPS: 0)
        #expect(FrameCap.envValue(for: 60, on: tiny) == nil)
        #expect(FrameCap.snapped(60, on: tiny) == nil)
    }

    // MARK: - The controller

    @Test func theControllerStepsBetweenHeldRates() {
        #expect(FrameCap.nudged(60, forward: true, on: promotion) == 80)
        #expect(FrameCap.nudged(60, forward: false, on: promotion) == 48)
        #expect(FrameCap.nudged(80, forward: true, on: promotion) == 0, "up from 80 is no limit")
        #expect(FrameCap.nudged(0, forward: false, on: promotion) == 80, "down from no limit is 80")
        #expect(FrameCap.nudged(0, forward: true, on: promotion) == 0)
        #expect(FrameCap.nudged(240, forward: false, on: promotion) == 80)
        #expect(FrameCap.nudged(24, forward: false, on: promotion) == 24)
        #expect(FrameCap.nudged(70, forward: false, on: promotion) == 48)
    }

    // MARK: - The top stop is no limit

    @Test func theTopStopIsTheDisplaysOwnMaximum() {
        let stops = FrameCap.stops(on: promotion)
        #expect(near(stops, [24, 26.6667, 30, 34.2857, 40, 48, 60, 80, 120]))
        #expect(FrameCap.maximum(on: promotion) == 120)
    }

    /// Off, the display's maximum and anything above it are one state.
    @Test func offAndTheMaximumAreTheSameState() {
        for v in [0.0, 20, 119.6, 120, 144, 240] { #expect(FrameCap.isNoLimit(v, on: promotion), "\(v)") }
        for v in [24.0, 48, 60, 80, 100] { #expect(!FrameCap.isNoLimit(v, on: promotion), "\(v)") }
        #expect(FrameCap.stopIndex(for: 0, on: promotion) == 8)
        #expect(FrameCap.stopIndex(for: 240, on: promotion) == 8)
        #expect(FrameCap.stored(forStop: 8, on: promotion) == 0)
        #expect(FrameCap.envValue(for: 0, on: promotion) == nil)
        #expect(FrameCap.envValue(for: 240, on: promotion) == nil)
    }

    @Test func aStopStoresItsRateRounded() {
        #expect(FrameCap.stopIndex(for: 60, on: promotion) == 6)
        #expect(FrameCap.stopIndex(for: 70, on: promotion) == 6)
        #expect(FrameCap.stored(forStop: 6, on: promotion) == 60)
        #expect(FrameCap.stored(forStop: 3, on: promotion) == 34)
        #expect(FrameCap.stored(forStop: -5, on: promotion) == 24)
        #expect(FrameCap.stored(forStop: 99, on: promotion) == 0)
    }

    /// From reading the code, not measured on a real monitor: a 240 Hz panel
    /// tops out at 240 = no limit with 120 below it, and a fixed 144 Hz one
    /// has no 60.
    @Test func otherDisplaysTopOutAtTheirOwnMaximum() {
        let hz240 = FrameCap.Display(minInterval: 1.0 / 240, maxInterval: 1.0 / 24, granularity: 1.0 / 240, maxFPS: 240)
        let s240 = FrameCap.stops(on: hz240)
        #expect(s240.last == 240 && s240[s240.count - 2] == 120)
        let hz144 = FrameCap.Display(minInterval: 1.0 / 144, maxInterval: 1.0 / 144, granularity: 0, maxFPS: 144)
        #expect(FrameCap.stops(on: hz144).last == 144)
        #expect(!FrameCap.stops(on: hz144).contains(60))
        #expect(FrameCap.snapped(60, on: hz144) == 48)
    }

    @Test func theLabelIsAWholeNumber() {
        #expect(FrameCap.label(34.2857) == "34")
        #expect(FrameCap.label(26.6667) == "27")
        #expect(FrameCap.label(60) == "60")
    }
}
