//
//  DualSenseRouteTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Which way a DualSense goes through winebus, from how it is attached.
struct DualSenseRouteTests {

    private func pad(_ pid: Int, _ transport: String) -> SonyPads.Pad { .init(productID: pid, transport: transport) }
    private func hidraw(_ o: [DualSenseRoute.Override], _ pid: Int) -> UInt32? {
        o.first { $0.path == DualSenseRoute.sectionPath(productID: pid) }?.hidraw
    }

    /// The key winebus enumerates: Devices\<vid>/<pid>, lowercase hex, four
    /// digits each, doubled backslashes as the .reg file has them.
    @Test func theSectionIsTheOneWinebusReads() {
        #expect(DualSenseRoute.sectionPath(productID: 0x0DF2)
                == "System\\\\CurrentControlSet\\\\Services\\\\winebus\\\\Devices\\\\054c/0df2")
    }

    /// Measured: over Bluetooth the raw path never rumbles, the SDL one does.
    @Test func aBluetoothDualSenseGoesThroughSDL() {
        let o = DualSenseRoute.overrides(for: [pad(SonyPads.dualSenseEdge, "Bluetooth")], sdlEnabled: true)
        #expect(hidraw(o, SonyPads.dualSenseEdge) == 0)
        #expect(hidraw(o, SonyPads.dualSense) == 1, "the model that is not here stays raw")
    }

    /// Over USB the raw path works and keeps touchpad, gyro and triggers.
    @Test func aUSBDualSenseStaysRaw() {
        let o = DualSenseRoute.overrides(for: [pad(SonyPads.dualSense, "USB")], sdlEnabled: true)
        #expect(hidraw(o, SonyPads.dualSense) == 1)
    }

    /// Explicit state, always: with nothing attached both models are written
    /// raw, so a 0 left by an earlier Bluetooth session cannot linger.
    @Test func nothingAttachedWritesRawForBothModels() {
        let o = DualSenseRoute.overrides(for: [], sdlEnabled: true)
        #expect(o.count == 2)
        #expect(o.allSatisfy { $0.hidraw == 1 })
    }

    /// The override only stops the raw copy; it does not make the SDL one.
    /// With SDL off a Bluetooth pad would vanish, so it stays raw.
    @Test func withSDLOffTheOverrideIsNeverWritten() {
        let o = DualSenseRoute.overrides(for: [pad(SonyPads.dualSenseEdge, "Bluetooth")], sdlEnabled: false)
        #expect(hidraw(o, SonyPads.dualSenseEdge) == 1)
        #expect(DualSenseRoute.summary(for: [pad(SonyPads.dualSenseEdge, "Bluetooth")], sdlEnabled: false)?
                    .contains("turn Enable SDL on") == true)
    }

    /// Two of one model, one on each transport: the key cannot tell them
    /// apart, and the one that would otherwise be silent wins.
    @Test func bluetoothWinsWhenTheSameModelIsOnBoth() {
        let o = DualSenseRoute.overrides(for: [pad(SonyPads.dualSense, "USB"), pad(SonyPads.dualSense, "BluetoothLowEnergy")],
                                         sdlEnabled: true)
        #expect(hidraw(o, SonyPads.dualSense) == 0)
    }

    @Test func somebodyElsesPadIsNotMentioned() {
        #expect(DualSenseRoute.summary(for: [pad(0x05C4, "Bluetooth")], sdlEnabled: true) == nil)
    }
}
