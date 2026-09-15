//
//  MacIdleDisconnectTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Which DualSense a launch writes a console line about, and that a pad never
/// changes what a launch does.
///
/// The IOKit read is not here; the filter it feeds is. Every expectation is
/// on the whole returned array, so a pad the code should not have returned is
/// a failure rather than something a `contains` walks past.
struct MacIdleDisconnectTests {

    /// The string measured on 2026-09-14 on both the driver's entry and the
    /// pad's IOHIDUserDevice.
    private let measured = "50:EE:32:C4:8E:F2"

    private func pad(_ pid: Int = SonyPads.dualSenseEdge, _ transport: String = "Bluetooth",
                     serial: String? = "50:EE:32:C4:8E:F2") -> SonyPads.Pad {
        .init(productID: pid, transport: transport, serialNumber: serial)
    }

    private func game(native: Bool = false, custom: Bool = false, exe: URL? = nil) -> Game {
        var g = Game(from: Game.steamMock, id: "1", isNative: native,
                     downloadProgress: 100, isInstalled: true, appNames: [])
        g.isCustom = custom
        g.appExeURL = exe
        return g
    }

    @Test func aBluetoothPadTheDriverHoldsIsAtRisk() {
        let p = pad()
        #expect(MacIdleDisconnect.padsAtRisk(pads: [p], driverSerials: [measured], engineSeizes: true) == [p])
    }

    @Test func noDriverNoRisk() {
        #expect(MacIdleDisconnect.padsAtRisk(pads: [pad()], driverSerials: [], engineSeizes: true) == [])
    }

    @Test func aWiredPadIsNotAtRisk() {
        #expect(MacIdleDisconnect.padsAtRisk(pads: [pad(SonyPads.dualSense, "USB")],
                                             driverSerials: [measured], engineSeizes: true) == [])
    }

    /// The plugin's idle disconnect is for Bluetooth Classic.
    @Test func bluetoothLowEnergyIsNotAtRisk() {
        #expect(MacIdleDisconnect.padsAtRisk(pads: [pad(SonyPads.dualSense, "BluetoothLowEnergy")],
                                             driverSerials: [measured], engineSeizes: true) == [])
    }

    /// The measured spelling against the two it could plausibly arrive in
    /// from the other side.
    @Test func theMeasuredSerialMatchesAcrossCaseAndSeparator() {
        let lower = pad(serial: "50:ee:32:c4:8e:f2")
        let dashes = pad(serial: "50-EE-32-C4-8E-F2")
        let bare = pad(serial: "50EE32C48EF2")
        #expect(MacIdleDisconnect.normalized(" 50-ee-32-c4-8e-f2 ") == "50EE32C48EF2")
        #expect(MacIdleDisconnect.normalized(measured) == "50EE32C48EF2")
        #expect(MacIdleDisconnect.padsAtRisk(pads: [lower], driverSerials: [measured], engineSeizes: true) == [lower])
        #expect(MacIdleDisconnect.padsAtRisk(pads: [dashes], driverSerials: [measured], engineSeizes: true) == [dashes])
        #expect(MacIdleDisconnect.padsAtRisk(pads: [bare], driverSerials: [measured], engineSeizes: true) == [bare])
        #expect(MacIdleDisconnect.padsAtRisk(pads: [pad()], driverSerials: ["50EE32C48EF2"],
                                             engineSeizes: true) == [pad()])
        #expect(MacIdleDisconnect.padsAtRisk(pads: [pad()], driverSerials: ["50:ee:32:c4:8e:f2"],
                                             engineSeizes: true) == [pad()])
    }

    @Test func aPadWithNoSerialNeverMatches() {
        #expect(MacIdleDisconnect.padsAtRisk(pads: [pad(serial: nil)], driverSerials: [measured, ""],
                                             engineSeizes: true) == [])
        // Nothing left once the separators go is not a serial either.
        #expect(MacIdleDisconnect.padsAtRisk(pads: [pad(serial: "::")], driverSerials: ["--"],
                                             engineSeizes: true) == [])
    }

    /// An engine without mgvf-0006 opens the pad shared: no line.
    @Test func anEngineThatDoesNotSeizeAsksNothing() {
        #expect(MacIdleDisconnect.padsAtRisk(pads: [pad()], driverSerials: [measured], engineSeizes: false) == [])
    }

    @Test func twoPadsOnlyTheHeldOneIsAtRisk() {
        let edge = pad(SonyPads.dualSenseEdge, serial: measured)
        let plain = pad(SonyPads.dualSense, serial: "A0:AB:51:00:00:01")
        #expect(MacIdleDisconnect.padsAtRisk(pads: [plain, edge], driverSerials: [measured],
                                             engineSeizes: true) == [edge])
    }

    /// A Sony pad that is not a DualSense is not what was measured.
    @Test func anotherSonyPadIsNotAtRisk() {
        #expect(MacIdleDisconnect.padsAtRisk(pads: [pad(0x09CC)], driverSerials: [measured], engineSeizes: true) == [])
    }

    @Test func theConsoleLineCarriesModelAndSerialAndNoAdvice() {
        let edge = MacIdleDisconnect.consoleLine(for: pad())
        #expect(edge == "controller: macOS's gamepad driver is attached to the DualSense Edge on Bluetooth "
                + "(50:EE:32:C4:8E:F2); macOS disconnects such a pad about 900 s after the last input it sees, "
                + "and while this bottle holds the pad it sees none")
        #expect(MacIdleDisconnect.consoleLine(for: pad(SonyPads.dualSense)).contains("the DualSense on Bluetooth"))
        #expect(!edge.lowercased().contains("off and on"))
        #expect(!edge.lowercased().contains("turn"))
    }

    /// A pad at risk never stops a launch: the outcome is decided without it,
    /// and the launch that goes ahead still writes the line.
    @Test func anAtRiskPadNeverChangesTheOutcomeAndIsStillLogged() {
        let p = pad()
        let atRisk = MacIdleDisconnect.padsAtRisk(pads: [p], driverSerials: [measured], engineSeizes: true)
        #expect(atRisk == [p])
        let outcome = GameLauncher.outcome(for: game(), isPlaying: false, needsFix: false)
        #expect(outcome == .started)
        #expect(GameLauncher.padLines(for: game(), outcome: outcome, padsAtRisk: { atRisk })
                == [MacIdleDisconnect.consoleLine(for: p)])
        // A native title is not held by a bottle: nothing to say.
        #expect(GameLauncher.padLines(for: game(native: true), outcome: .started, padsAtRisk: { atRisk }) == [])
    }

    /// The lines are held until the title is seen running, and written once:
    /// a tracker's second onLoad, for a title that came back after a gap, is
    /// the same session.
    @MainActor @Test func theLinesAreWrittenOnceOnLoadOnly() {
        let line = MacIdleDisconnect.consoleLine(for: pad())
        let pending = PendingPadLines([line])
        #expect(pending.take() == [line])
        #expect(pending.take() == [])
        #expect(PendingPadLines([]).take() == [])
    }

    /// The pads are looked at only for a Windows title whose launch goes
    /// ahead: IOKit and the engine binary are not read on any other press.
    @Test func thePadsAreNotLookedAtUnlessTheTitleStarts() {
        let epic = Game.epic(EpicInstalled(id: "epic:ns1:item1:app1", appName: "app1", catalogNamespace: "ns1",
                                           catalogItemId: "item1", title: "A Game",
                                           folder: URL(fileURLWithPath: "/tmp/x"),
                                           executable: URL(fileURLWithPath: "/tmp/x/AGame.exe"),
                                           version: "1", presence: .installed))
        #expect(epic.isEpic)
        let p = pad()
        // Counted per press, so a call is pinned to the press that made it.
        func press(_ g: Game, isPlaying: Bool = false, needsFix: Bool = false,
                   hasEpicLauncher: Bool = true) -> (LaunchOutcome, Int, Int) {
            var asked = 0
            let outcome = GameLauncher.outcome(for: g, isPlaying: isPlaying, needsFix: needsFix,
                                               hasEpicLauncher: hasEpicLauncher)
            let lines = GameLauncher.padLines(for: g, outcome: outcome) { asked += 1; return [p] }
            return (outcome, asked, lines.count)
        }
        let presses = [
            press(game(), isPlaying: true),
            press(game(native: true)),
            press(game(custom: true, exe: nil)),
            press(epic, hasEpicLauncher: false),
            press(game(), needsFix: true),
            press(epic, hasEpicLauncher: true),
            press(game()),
        ]
        #expect(presses.map(\.0) == [.alreadyPlaying, .started, .noExecutable, .noExecutable, .needsFix,
                                     .started, .started])
        #expect(presses.map(\.1) == [0, 0, 0, 0, 0, 1, 1])
        #expect(presses.map(\.2) == [0, 0, 0, 0, 0, 1, 1])
    }
}
