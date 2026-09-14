//
//  MacIdleDisconnectTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Which DualSense Play warns about, and when it stops to do so.
///
/// The IOKit read is not here; the decision it feeds is. Every expectation is
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

    /// An engine without mgvf-0006 opens the pad shared: no notice.
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

    @Test func shouldAskOnlyWhenNothingSaysOtherwise() {
        let atRisk = [pad()]
        #expect(MacIdleDisconnect.shouldAsk(atRisk: atRisk, isNative: false, suppressed: false, acknowledged: false))
        #expect(!MacIdleDisconnect.shouldAsk(atRisk: atRisk, isNative: true, suppressed: false, acknowledged: false))
        #expect(!MacIdleDisconnect.shouldAsk(atRisk: atRisk, isNative: false, suppressed: true, acknowledged: false))
        #expect(!MacIdleDisconnect.shouldAsk(atRisk: atRisk, isNative: false, suppressed: false, acknowledged: true))
        #expect(!MacIdleDisconnect.shouldAsk(atRisk: [], isNative: false, suppressed: false, acknowledged: false))
    }

    @Test func theMessageNamesTheModel() {
        #expect(MacIdleDisconnect.message(for: [pad()]).title == "Turn your DualSense Edge off and on once the game is up")
        #expect(MacIdleDisconnect.message(for: [pad(SonyPads.dualSense)]).title
                == "Turn your DualSense off and on once the game is up")
        #expect(MacIdleDisconnect.message(for: [pad(), pad(SonyPads.dualSense)]).title
                == "Turn your controllers off and on once the game is up")
    }

    /// Word for word: every clause of it is measured, and a clause that is not
    /// must not slip in unnoticed.
    @Test func theBodyIsTheMeasuredWording() {
        let body = "macOS disconnects a DualSense on Bluetooth about 15 minutes into play when it was connected "
            + "before the game started. Turning it off and on after the game's window appears has stopped "
            + "that every time so far: macOS then leaves that connection alone."
        #expect([[pad()], [pad(SonyPads.dualSense)], [pad(), pad(SonyPads.dualSense)], []]
                    .map { MacIdleDisconnect.message(for: $0).body } == [body, body, body, body])
    }

    /// The step between the pads at risk and what Play does with them.
    @Test func theLaunchDecisionAsksOrLogsNeverBoth() {
        let p = pad()
        let quiet = MacIdleDisconnect.consoleLine(for: p, suppressed: false)
        let off = MacIdleDisconnect.consoleLine(for: p, suppressed: true)
        let cases: [(native: Bool, suppressed: Bool, acknowledged: Bool)] =
            [(false, false, false), (false, false, true), (false, true, false), (true, false, false)]
        let decisions = cases.map {
            MacIdleDisconnect.launchDecision(atRisk: [p], isNative: $0.native, suppressed: $0.suppressed,
                                             acknowledged: $0.acknowledged)
        }
        #expect(decisions.map(\.ask) == [[p], [], [], []])
        #expect(decisions.map(\.log) == [[], [quiet], [off], [quiet]])
        let none = MacIdleDisconnect.launchDecision(atRisk: [], isNative: false, suppressed: false, acknowledged: false)
        #expect(none.ask == [] && none.log == [])
    }

    @Test func theConsoleLineCarriesModelAndSerial() {
        let line = MacIdleDisconnect.consoleLine(for: pad(), suppressed: true)
        #expect(line.contains("DualSense Edge"))
        #expect(line.contains(measured))
        #expect(line.contains("turned off"))
        #expect(!MacIdleDisconnect.consoleLine(for: pad(), suppressed: false).contains("turned off"))
    }

    /// alreadyPlaying > native > noExecutable > needsFix > padWillDisconnect > started.
    @Test func theNoticeComesAfterEveryOtherGate() {
        let pads = [pad()]
        #expect(GameLauncher.outcome(for: game(), isPlaying: true, needsFix: true,
                                     padsToAskAbout: { pads }) == .alreadyPlaying)
        #expect(GameLauncher.outcome(for: game(native: true), isPlaying: false, needsFix: false,
                                     padsToAskAbout: { pads }) == .started)
        #expect(GameLauncher.outcome(for: game(custom: true, exe: nil), isPlaying: false, needsFix: true,
                                     padsToAskAbout: { pads }) == .noExecutable)
        #expect(GameLauncher.outcome(for: game(), isPlaying: false, needsFix: true,
                                     padsToAskAbout: { pads }) == .needsFix)
        #expect(GameLauncher.outcome(for: game(), isPlaying: false, needsFix: false,
                                     padsToAskAbout: { pads }) == .padWillDisconnect(pads))
        #expect(GameLauncher.outcome(for: game(), isPlaying: false, needsFix: false,
                                     padsToAskAbout: { [] }) == .started)
    }

    /// The pads are asked about only for a launch that would otherwise start:
    /// IOKit and the engine binary are not read on any other press.
    @Test func thePadsAreNotLookedAtUnlessTheTitleWouldStart() {
        let epic = Game.epic(EpicInstalled(id: "epic:ns1:item1:app1", appName: "app1", catalogNamespace: "ns1",
                                           catalogItemId: "item1", title: "A Game",
                                           folder: URL(fileURLWithPath: "/tmp/x"),
                                           executable: URL(fileURLWithPath: "/tmp/x/AGame.exe"),
                                           version: "1", presence: .installed))
        #expect(epic.isEpic)
        // Counted per press, so a call is pinned to the press that made it.
        func asks(_ press: (() -> [SonyPads.Pad]) -> LaunchOutcome) -> (LaunchOutcome, Int) {
            var asked = 0
            let outcome = press { asked += 1; return [] }
            return (outcome, asked)
        }
        let presses = [
            asks { GameLauncher.outcome(for: game(), isPlaying: true, needsFix: false, padsToAskAbout: $0) },
            asks { GameLauncher.outcome(for: game(native: true), isPlaying: false, needsFix: false, padsToAskAbout: $0) },
            asks { GameLauncher.outcome(for: game(custom: true, exe: nil), isPlaying: false, needsFix: false,
                                        padsToAskAbout: $0) },
            asks { GameLauncher.outcome(for: epic, isPlaying: false, needsFix: false, hasEpicLauncher: false,
                                        padsToAskAbout: $0) },
            asks { GameLauncher.outcome(for: game(), isPlaying: false, needsFix: true, padsToAskAbout: $0) },
            asks { GameLauncher.outcome(for: epic, isPlaying: false, needsFix: false, hasEpicLauncher: true,
                                        padsToAskAbout: $0) },
            asks { GameLauncher.outcome(for: game(), isPlaying: false, needsFix: false, padsToAskAbout: $0) },
        ]
        #expect(presses.map(\.0) == [.alreadyPlaying, .started, .noExecutable, .noExecutable, .needsFix,
                                     .started, .started])
        #expect(presses.map(\.1) == [0, 0, 0, 0, 0, 1, 1])
    }
}
