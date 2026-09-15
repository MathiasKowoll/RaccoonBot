//
//  IdlePadPowerOffTests.swift
//  RaccoonBotTests
//
//  What counts as somebody using a DualSense, the request that turns it off,
//  when it is sent, and the value written for the engine.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct IdlePadPowerOffTests {

    // MARK: reports, as IOKit hands them over

    /// A 78-byte 0x31 with the given sticks, triggers and buttons, and noise in
    /// every byte a person does not move.
    private func full(axes: [UInt8] = [128, 128, 128, 128, 0, 0], buttons: [UInt8] = [0x08, 0x00, 0x00, 0x00],
                      counter: UInt8 = 0, noise: UInt8 = 0) -> [UInt8] {
        var r = [UInt8](repeating: noise, count: 78)
        r[0] = 0x31
        r[1] = noise
        r.replaceSubrange(2...7, with: axes)
        r[8] = counter
        r.replaceSubrange(9...12, with: buttons)
        return r
    }

    /// A 10-byte 0x01: sticks at 1..4, buttons at 5..7, triggers at 8..9.
    private func simple(sticks: [UInt8] = [128, 128, 128, 128], buttons: [UInt8] = [0x08, 0x00, 0x00],
                        triggers: [UInt8] = [0, 0]) -> [UInt8] {
        [0x01] + sticks + buttons + triggers
    }

    // MARK: the request

    /// The measured buffer, and the CRC tail mgvf-0005 appended to libScePad's
    /// own write on 2026-09-08.
    @Test func thePowerOffReportIsTheMeasuredOne() {
        let r = IdlePadPowerOff.powerOffReport()
        #expect(r.count == 48)
        #expect(Array(r[0...1]) == [0x08, 0x02])
        #expect(Array(r[2..<44]) == [UInt8](repeating: 0, count: 42))
        #expect(Array(r[44...]) == [0xe0, 0xef, 0xa2, 0x23])
        #expect(IdlePadPowerOff.featureReportID == 0x08)
        #expect(IdlePadPowerOff.crcSeed == 0x53)
    }

    // MARK: the activity rule

    /// Offsets from wine's own fixup comment: X Y Z Rz at 2..5, triggers at
    /// 6..7, counter at 8, buttons at 9..12 -- mgvf-0033's rule.
    @Test func aFullReportIsReadAtWinesOffsets() {
        let s = IdlePadPowerOff.snapshot(of: full(axes: [1, 2, 3, 4, 5, 6], buttons: [7, 8, 9, 10], counter: 99,
                                                  noise: 0xAA))
        #expect(s == .init(layout: .full, axes: [1, 2, 3, 4, 5, 6, 0, 0], buttons: [7, 8, 9, 10]))
    }

    /// The simple report puts the triggers after the buttons, and byte 7's
    /// upper six bits are a counter.
    @Test func aSimpleReportIsReadWithTheCounterMasked() {
        let s = IdlePadPowerOff.snapshot(of: simple(sticks: [1, 2, 3, 4], buttons: [5, 6, 0xFF], triggers: [8, 9]))
        #expect(s == .init(layout: .simple, axes: [1, 2, 3, 4, 8, 9, 0, 0], buttons: [5, 6, 0x03, 0]))
        #expect(IdlePadPowerOff.snapshot(of: simple(buttons: [0x08, 0, 0x04]))
                == IdlePadPowerOff.snapshot(of: simple(buttons: [0x08, 0, 0xFC])),
                "the counter bits alone are the same snapshot")
    }

    @Test func anythingElseIsNotRead() {
        #expect(IdlePadPowerOff.snapshot(of: []) == nil)
        #expect(IdlePadPowerOff.snapshot(of: [0x31, 0, 0, 0]) == nil, "a 0x31 too short to hold the buttons")
        #expect(IdlePadPowerOff.snapshot(of: Array(full()[0..<12])) == nil, "12 bytes stop short of byte 12")
        #expect(IdlePadPowerOff.snapshot(of: Array(full()[0..<13])) != nil, "13 is the engine's own minimum")
        #expect(IdlePadPowerOff.snapshot(of: [UInt8](repeating: 0, count: 11) + [0x01]) == nil)
        #expect(IdlePadPowerOff.snapshot(of: simple() + [0]) == nil, "a 0x01 that is not 10 bytes")
        var other = full(); other[0] = 0x32
        #expect(IdlePadPowerOff.snapshot(of: other) == nil)
    }

    /// More than 4 counts on any axis, or any change in a button byte.
    @Test func theThresholdIsMoreThanFour() {
        let ref = IdlePadPowerOff.snapshot(of: full())!
        for index in 0..<6 {
            var four = [UInt8](arrayLiteral: 128, 128, 128, 128, 0, 0)
            var five = four
            four[index] = four[index] &+ 4
            five[index] = five[index] &+ 5
            #expect(!IdlePadPowerOff.counts(IdlePadPowerOff.snapshot(of: full(axes: four))!, against: ref), "axis \(index)")
            #expect(IdlePadPowerOff.counts(IdlePadPowerOff.snapshot(of: full(axes: five))!, against: ref), "axis \(index)")
        }
        let down = IdlePadPowerOff.snapshot(of: full(axes: [123, 128, 128, 128, 0, 0]))!
        #expect(IdlePadPowerOff.counts(down, against: ref), "downwards as well")
    }

    /// Every bit of bytes 11 and 12 is a button: wherever the Edge reports Fn
    /// and the paddles, they must not be masked away.
    @Test func everyButtonBitCounts() {
        let ref = IdlePadPowerOff.snapshot(of: full())!
        for byte in 0..<4 {
            for bit in 0..<8 {
                var buttons: [UInt8] = [0x08, 0x00, 0x00, 0x00]
                buttons[byte] ^= UInt8(1 << bit)
                #expect(IdlePadPowerOff.counts(IdlePadPowerOff.snapshot(of: full(buttons: buttons))!, against: ref),
                        "byte \(9 + byte) bit \(bit)")
            }
        }
    }

    /// Gyro, accelerometer, timestamps, battery, touch and the counter are all
    /// in the noise, and none of it counts.
    @Test func whatAPersonDoesNotMoveNeverCounts() {
        var clock = IdlePadPowerOff.Clock()
        clock.observe(full(), at: 0)
        for t in 1...200 {
            let counted1 = clock.observe(full(counter: UInt8(t % 256), noise: UInt8((t * 37) % 256)), at: Double(t) / 64)
            #expect(!counted1)
        }
        #expect(clock.lastActivity == 0)
    }

    /// The reference moves only on counted activity, so jitter that creeps a
    /// count at a time never adds up to a moved stick -- and a real move does.
    @Test func theReferenceUpdatesOnlyOnCountedActivity() {
        var clock = IdlePadPowerOff.Clock()
        let counted2 = clock.observe(full(axes: [128, 128, 128, 128, 0, 0]), at: 0)
        #expect(!counted2, "the first report starts the clock")
        let counted3 = clock.observe(full(axes: [131, 128, 128, 128, 0, 0]), at: 1)
        #expect(!counted3)
        let counted4 = clock.observe(full(axes: [132, 128, 128, 128, 0, 0]), at: 2)
        #expect(!counted4)
        let counted5 = clock.observe(full(axes: [125, 128, 128, 128, 0, 0]), at: 3)
        #expect(!counted5)
        #expect(clock.reference?.axes[0] == 128, "nothing counted, so the reference did not move")
        #expect(clock.lastActivity == 0)
        let counted6 = clock.observe(full(axes: [133, 128, 128, 128, 0, 0]), at: 4)
        #expect(counted6)
        #expect(clock.reference?.axes[0] == 133)
        #expect(clock.lastActivity == 4)
        let counted7 = clock.observe(full(axes: [129, 128, 128, 128, 0, 0]), at: 5)
        #expect(!counted7, "four from the new reference")
        #expect(clock.lastActivity == 4)
    }

    /// In the simple layout too, with the counter running in byte 7.
    @Test func theSimpleCounterNeverCounts() {
        var clock = IdlePadPowerOff.Clock()
        clock.observe(simple(buttons: [0x08, 0, 0]), at: 0)
        for n in 1...63 {
            let counted8 = clock.observe(simple(buttons: [0x08, 0, UInt8(n << 2)]), at: Double(n) / 64)
            #expect(!counted8)
        }
        let counted9 = clock.observe(simple(buttons: [0x08, 0, UInt8(5 << 2) | 0x01]), at: 1)
        #expect(counted9, "PS in the low bits counts")
        let counted10 = clock.observe(simple(triggers: [0, 40]), at: 2)
        #expect(counted10, "and a trigger, at 8..9")
    }

    /// A switch from the simple report to the full one replaces the reference
    /// and is not activity.
    @Test func aChangeOfLayoutIsNotActivity() {
        var clock = IdlePadPowerOff.Clock()
        clock.observe(simple(), at: 0)
        let counted11 = clock.observe(full(), at: 1)
        #expect(!counted11)
        #expect(clock.reference?.layout == .full)
        #expect(clock.lastActivity == 0)
    }

    /// Reports after a silence start the clock again from that moment: a pad
    /// that was held somewhere else was not idle while it was.
    @Test func reportsAfterAGapStartTheClockAgain() {
        var clock = IdlePadPowerOff.Clock()
        clock.observe(full(), at: 0)
        let counted12 = clock.observe(full(), at: 5000)
        #expect(!counted12)
        #expect(clock.lastActivity == 5000)
        let counted13 = clock.observe(full(), at: 5000 + IdlePadPowerOff.reportGap)
        #expect(!counted13)
        #expect(clock.lastActivity == 5000, "a report within the gap keeps the clock")
    }

    @Test func aReportThatIsNotReadIsNotSeen() {
        var clock = IdlePadPowerOff.Clock()
        let counted14 = clock.observe([0x05, 1, 2, 3], at: 0)
        #expect(!counted14)
        #expect(clock.lastReport == nil)
    }

    // MARK: the decision

    private func watched(since start: TimeInterval, until end: TimeInterval) -> IdlePadPowerOff.Clock {
        var clock = IdlePadPowerOff.Clock()
        var t = start
        while t <= end { clock.observe(full(), at: t); t += 1 }
        return clock
    }

    @Test func aWatchedPadIsTurnedOffAtTheChosenTime() {
        let clock = watched(since: 0, until: 1200)
        #expect(IdlePadPowerOff.decide(minutes: 20, gameRunning: false, clock: clock, now: 1200, alreadyAsked: false)
                == .powerOff)
        #expect(IdlePadPowerOff.decide(minutes: 30, gameRunning: false, clock: clock, now: 1200, alreadyAsked: false)
                == .waiting(remaining: 600))
        #expect(IdlePadPowerOff.decide(minutes: 10, gameRunning: false, clock: watched(since: 0, until: 599),
                                       now: 599, alreadyAsked: false) == .waiting(remaining: 1))
    }

    @Test func offDecidesNothing() {
        #expect(IdlePadPowerOff.decide(minutes: 0, gameRunning: false, clock: watched(since: 0, until: 7200),
                                       now: 7200, alreadyAsked: false) == .off)
    }

    @Test func aRunningGameIsNeverIdle() {
        #expect(IdlePadPowerOff.decide(minutes: 10, gameRunning: true, clock: watched(since: 0, until: 7200),
                                       now: 7200, alreadyAsked: false) == .gameRunning)
    }

    /// The case this must never get wrong: a pad wine seized sends RaccoonBot
    /// nothing, however long, and that silence is not idleness.
    @Test func aHeldPadIsNeverCountedIdle() {
        let clock = watched(since: 0, until: 60)
        for later in [71.0, 600, 1200, 3600, 86400] {
            #expect(IdlePadPowerOff.decide(minutes: 10, gameRunning: false, clock: clock, now: later,
                                           alreadyAsked: false) == .unseen, "at \(later)")
        }
        #expect(IdlePadPowerOff.decide(minutes: 10, gameRunning: false, clock: IdlePadPowerOff.Clock(), now: 86400,
                                       alreadyAsked: false) == .unseen, "never seen at all")
        // And when it is let go, the clock starts from its first report back.
        var back = clock
        back.observe(full(), at: 86400)
        #expect(IdlePadPowerOff.decide(minutes: 10, gameRunning: false, clock: back, now: 86400,
                                       alreadyAsked: false) == .waiting(remaining: 600))
    }

    @Test func aRequestIsSentOnce() {
        #expect(IdlePadPowerOff.decide(minutes: 20, gameRunning: false, clock: watched(since: 0, until: 1300),
                                       now: 1300, alreadyAsked: true) == .alreadyAsked)
    }

    /// Off before a running game, a running game before anything the clock
    /// says, silence before a stale request.
    @Test func theOrderOfTheAnswers() {
        let idle = watched(since: 0, until: 7200)
        let stale = watched(since: 0, until: 60)
        #expect(IdlePadPowerOff.decide(minutes: 0, gameRunning: true, clock: idle, now: 7200, alreadyAsked: true) == .off)
        #expect(IdlePadPowerOff.decide(minutes: 10, gameRunning: true, clock: idle, now: 7200, alreadyAsked: false)
                == .gameRunning, "a clock long past the limit does not win over a running game")
        #expect(IdlePadPowerOff.decide(minutes: 10, gameRunning: true, clock: stale, now: 7200, alreadyAsked: true)
                == .gameRunning)
        #expect(IdlePadPowerOff.decide(minutes: 10, gameRunning: false, clock: stale, now: 7200, alreadyAsked: true)
                == .unseen)
    }

    // MARK: one pad's state, as the watcher carries it out

    private func snap(_ report: [UInt8]) -> IdlePadPowerOff.Snapshot? { IdlePadPowerOff.snapshot(of: report) }

    /// An open pad that has been heard until `until`, a report a second.
    private func heardPad(until end: TimeInterval) -> IdlePadPowerOff.PadState {
        var s = IdlePadPowerOff.PadState()
        #expect(s.arrived(gameRunning: false, at: 0) == .open)
        _ = s.opened(.success, at: 0)
        var t: TimeInterval = 0
        while t <= end { _ = s.heard(snap(full()), at: t); t += 1 }
        return s
    }

    @Test func aPadThatArrivesDuringAGameIsNotOpened() {
        var s = IdlePadPowerOff.PadState()
        #expect(s.arrived(gameRunning: true, at: 0) == .none)
        #expect(!s.isOpen)
    }

    /// An open refused because another process holds the pad: not open, no
    /// clock, logged once, and never idle however long it stays that way.
    @Test func anExclusiveOpenIsNeverIdle() {
        var s = IdlePadPowerOff.PadState()
        _ = s.arrived(gameRunning: false, at: 0)
        #expect(s.opened(.exclusiveAccess, at: 0) == .exclusiveAccess)
        #expect(!s.isOpen)
        #expect(s.clock.lastActivity == nil)
        var t: TimeInterval = 60
        while t < 86400 {
            let action = s.tick(minutes: 10, gameRunning: false, at: t)
            #expect(action == .none || action == .open, "at \(t)")
            if action == .open { #expect(s.opened(.exclusiveAccess, at: t) == nil, "logged once") }
            t += 60
        }
        #expect(s.askedAt == nil)
        #expect(s.heard(snap(full()), at: t) == .ignored, "a pad that is not open is not heard")
    }

    /// A request refused because another process holds the pad resets the
    /// clock and is not a request: the next idle stretch asks again.
    @Test func anExclusiveRequestIsNotARequest() {
        var s = heardPad(until: 600)
        #expect(s.tick(minutes: 10, gameRunning: false, at: 600) == .powerOff)
        #expect(s.requested(.exclusiveAccess, at: 600) == .heldElsewhere)
        #expect(s.askedAt == nil)
        #expect(s.clock.lastActivity == nil)
        #expect(s.tick(minutes: 10, gameRunning: false, at: 605) != .powerOff)
    }

    @Test func aSentRequestIsNotRepeatedAndInputAfterItIsReported() {
        var s = heardPad(until: 600)
        #expect(s.tick(minutes: 10, gameRunning: false, at: 600) == .powerOff)
        #expect(s.requested(.success, at: 600) == .asked)
        _ = s.heard(snap(full()), at: 601)
        #expect(s.tick(minutes: 10, gameRunning: false, at: 601) == .none)
        #expect(s.heard(snap(full()), at: 615) == .stillUp(seconds: 15))
        #expect(s.heard(snap(full()), at: 616) == .nothing, "said once")
        #expect(s.heard(snap(full(buttons: [0x28, 0, 0, 0])), at: 617) == .counted)
        #expect(s.askedAt == nil, "used again, so it may be asked again")
        #expect(s.requested(.other(-536870212), at: 2000) == .failed(-536870212))
        #expect(s.askedAt == 2000, "a failed request is not repeated either")
    }

    /// A running game, or Play being pressed, lets go of the pad and forgets
    /// the request and the clock.
    @Test func aRunningGameClosesThePadAndForgetsTheRequest() {
        var s = heardPad(until: 600)
        _ = s.requested(.success, at: 600)
        #expect(s.tick(minutes: 10, gameRunning: true, at: 660) == .close)
        #expect(s.askedAt == nil)
        #expect(s.clock.lastActivity == nil)
        s.closed()
        #expect(s.tick(minutes: 10, gameRunning: true, at: 720) == .none, "already closed")
        #expect(s.tick(minutes: 10, gameRunning: false, at: 780) == .open, "opened again once the game is over")

        var launch = heardPad(until: 100)
        _ = launch.requested(.success, at: 100)
        #expect(launch.standAside() == .close)
        #expect(launch.askedAt == nil)
        #expect(launch.clock.lastActivity == nil)
    }

    /// A pad nobody hears is opened again after 30 s, then less and less
    /// often, never more than every 10 minutes; a report ends the backoff.
    @Test func aSilentPadIsReopenedLessAndLessOften() {
        #expect((0...7).map { IdlePadPowerOff.reopenInterval(afterSilentAttempts: $0) }
                == [30, 60, 120, 240, 480, 600, 600, 600])
        var s = heardPad(until: 100)
        var reopens: [TimeInterval] = []
        var t: TimeInterval = 120
        while t <= 3600 {
            if s.tick(minutes: 10, gameRunning: false, at: t) == .reopen { reopens.append(t) }
            t += 60
        }
        #expect(reopens == [120, 180, 300, 540, 1020, 1620, 2220, 2820, 3420])
        _ = s.heard(snap(full()), at: 3430)
        #expect(s.silentAttempts == 0)
    }

    @Test @MainActor func offSetsUpNothing() {
        let watcher = IdlePadWatcher()
        watcher.apply(minutes: 0)
        #expect(!watcher.isWatching)
    }

    // MARK: the setting

    @Test func theChoicesAndTheDefault() {
        #expect(IdlePadPowerOff.choices == [0, 10, 20, 30, 60])
        #expect(IdlePadPowerOff.byDefault == 20)
        #expect(IdlePadPowerOff.pickable(nil) == 20)
        #expect(IdlePadPowerOff.pickable(7) == 20)
        #expect(IdlePadPowerOff.pickable(0) == 0)
        #expect(IdlePadPowerOff.dropdownOptions.map(\.label) == ["Off", "10 minutes", "20 minutes", "30 minutes", "60 minutes"])
    }

    // MARK: the value written for the engine

    private func pad(_ pid: Int, _ transport: String) -> SonyPads.Pad { .init(productID: pid, transport: transport) }

    @Test func theChosenMinutesAreWrittenForBothModels() {
        let pads = [pad(SonyPads.dualSenseEdge, "Bluetooth")]
        for minutes in IdlePadPowerOff.choices {
            let o = DualSenseRoute.overrides(for: pads, sdlEnabled: true, engineTellsTheBus: true,
                                             idlePowerOffMinutes: minutes, engineCanPowerOffIdle: true)
            #expect(o.map(\.path) == SonyPads.models.map { DualSenseRoute.sectionPath(productID: $0) })
            #expect(o.map(\.idlePowerOffMinutes) == [UInt32(minutes), UInt32(minutes)], "for \(minutes)")
            #expect(o.allSatisfy { $0.values.last! == (DualSenseRoute.idlePowerOffMinutesValue, UInt32(minutes)) })
        }
    }

    @Test func anEngineThatDoesNotReadItGetsZero() {
        for minutes in IdlePadPowerOff.choices {
            let o = DualSenseRoute.overrides(for: [], sdlEnabled: true, engineTellsTheBus: true,
                                             idlePowerOffMinutes: minutes, engineCanPowerOffIdle: false)
            #expect(o.map(\.idlePowerOffMinutes) == [0, 0], "for \(minutes)")
        }
        #expect(IdlePadPowerOff.registryValue(minutes: 45, engineCanPowerOffIdle: true) == 20,
                "a number the menu cannot show is written as the default")
    }

    @Test @MainActor func theLaunchPlanCarriesTheSetting() {
        let plan = DualSenseRoute.launchPlan(options: GameOptions(), pads: [],
                                             engine: .init(tellsTheBus: true, canPowerOffIdle: true),
                                             idlePowerOffMinutes: 30)
        #expect(plan.overrides.map(\.idlePowerOffMinutes) == [30, 30])
        let without = DualSenseRoute.launchPlan(options: GameOptions(), pads: [],
                                                engine: .init(tellsTheBus: true, canPowerOffIdle: false),
                                                idlePowerOffMinutes: 30)
        #expect(without.overrides.map(\.idlePowerOffMinutes) == [0, 0])
    }

    /// Every value on disk after the launch writes, not only the new one.
    @Test func theRegistryHoldsEveryValueUnderBothKeys() throws {
        let fixture = """
        WINE REGISTRY Version 2
        ;; All keys relative to \\\\Machine

        [System\\\\CurrentControlSet\\\\Services\\\\winebus] 1787673440
        #time=1dc0000000000001
        "Enable SDL"=dword:00000001

        """
        let f = FileManager.default
        let url = f.temporaryDirectory.appendingPathComponent("idle-\(UUID().uuidString).reg")
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        defer {
            try? f.removeItem(at: url)
            try? f.removeItem(at: url.appendingPathExtension("orig"))
            try? f.removeItem(at: url.appendingPathExtension("procyon-backup"))
        }
        let registry = WineRegistryFile(fileURL: url)
        try registry.load()
        let o = DualSenseRoute.overrides(for: [], sdlEnabled: true, engineTellsTheBus: true,
                                         idlePowerOffMinutes: 60, engineCanPowerOffIdle: true)
        for override in o { DualSenseRoute.write(override, into: registry, timestamp: 1_800_000_000) }
        try registry.save()

        let reread = WineRegistryFile(fileURL: url)
        try reread.load()
        var sections: [String: [String]] = [:]
        for section in reread.sections { sections[section.path] = section.values.map(\.value.rawLine) }
        let each = ["\"Hidraw\"=dword:00000001", "\"UsbEmulation\"=dword:00000000", "\"ProductId\"=dword:00000000",
                    "\"VibrationMode\"=dword:00000000", "\"VibrationGain\"=dword:00000064",
                    "\"XInputRumble\"=dword:00000000", "\"LightbarColour\"=dword:00000000",
                    "\"PlayerLights\"=dword:00000000", "\"IdlePowerOffMinutes\"=dword:0000003c"]
        #expect(sections == [
            "System\\\\CurrentControlSet\\\\Services\\\\winebus": ["\"Enable SDL\"=dword:00000001"],
            DualSenseRoute.sectionPath(productID: SonyPads.dualSense): each,
            DualSenseRoute.sectionPath(productID: SonyPads.dualSenseEdge): each,
        ])
        let off = DualSenseRoute.overrides(for: [], sdlEnabled: true, engineTellsTheBus: true,
                                           idlePowerOffMinutes: 0, engineCanPowerOffIdle: true)
        #expect(off.map { DualSenseRoute.write($0, into: reread, timestamp: 1_800_000_001).map(\.key) }
                == [[DualSenseRoute.idlePowerOffMinutesValue], [DualSenseRoute.idlePowerOffMinutesValue]],
                "turning it off changes that one value and nothing else")
    }

    // MARK: the engine, from its own binary

    private func engine(winebus bytes: Data) throws -> URL {
        let f = FileManager.default
        let app = f.temporaryDirectory.appendingPathComponent("idle-\(UUID().uuidString).app", isDirectory: true)
        let dir = app.appendingPathComponent("Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows")
        try f.createDirectory(at: dir, withIntermediateDirectories: true)
        try bytes.write(to: dir.appendingPathComponent("winebus.sys"))
        return app
    }

    @Test func theCapabilityIsReadFromTheBinary() throws {
        #expect(DualSenseRoute.engineCanPowerOffIdle(cxAppPath: nil) == false)
        #expect(DualSenseRoute.engineCanPowerOffIdle(cxAppPath: "/nonexistent.app") == false)
        let f = FileManager.default
        let utf16 = Data("IdlePowerOffMinutes".utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] })
        let with = try engine(winebus: Data("MZ".utf8) + utf16 + Data([0, 0]))
        defer { try? f.removeItem(at: with) }
        #expect(DualSenseRoute.engineCanPowerOffIdle(cxAppPath: with.path(percentEncoded: false)))
        let ascii = try engine(winebus: Data("MZ IdlePowerOffMinutes in ASCII only".utf8))
        defer { try? f.removeItem(at: ascii) }
        #expect(DualSenseRoute.engineCanPowerOffIdle(cxAppPath: ascii.path(percentEncoded: false)) == false)
    }

    /// The probe asked of the winebus.sys this application actually carries,
    /// placed where an engine keeps it. The fakes above prove how the probe
    /// reads; this proves the payload answers yes, so a refresh from a build
    /// without mgvf-0033 fails here rather than writing 0 into every bottle.
    @Test func theWinebusWeCarryCanPowerOffIdle() throws {
        let carried = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RaccoonBot/Libs/mgvf/MacGameVideoFix.app/Contents/Resources/engine-controller-winebus.sys")
        let bytes = try Data(contentsOf: carried)
        let app = try engine(winebus: bytes)
        defer { try? FileManager.default.removeItem(at: app) }
        #expect(DualSenseRoute.engineCanPowerOffIdle(cxAppPath: app.path(percentEncoded: false)))
    }

    /// The name is the patch's, read from mgvf-0033 in the sibling
    /// MacGameVideoFix checkout. A missing patch is a failure, not a pass:
    /// the payload this application carries is built from it.
    @Test func thePatchItselfNamesTheValue() throws {
        let patches = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MacGameVideoFix/source-patches")
        let names = try FileManager.default.contentsOfDirectory(atPath: patches.path(percentEncoded: false))
        guard let file = names.first(where: { $0.hasPrefix("mgvf-0033-") && $0.hasSuffix(".patch") }) else {
            Issue.record("mgvf-0033 is not in \(patches.path(percentEncoded: false))")
            return
        }
        let text = try String(contentsOf: patches.appendingPathComponent(file), encoding: .utf8)
        #expect(text.contains("L\"\(DualSenseRoute.idlePowerOffMinutesValue)\""))
    }
}
