//
//  IdlePadPowerOff.swift
//  RaccoonBot
//
//  Turning off a DualSense nobody is using: the setting, the request, and the
//  rule for what counts as somebody using it. No IOKit here; IdlePadWatcher is
//  the part that touches the pad.
//
//  WHY. A DualSense on Bluetooth that connects while wine holds it gets no
//  macOS gamepad driver, so neither macOS's 900 s idle cut nor the pad's own
//  power-off happened. Measured on 2026-09-12/13: left alone after the game
//  and Steam had exited, it ran from 00:07 to 03:21 and came back at 0%
//  battery; on 2026-09-13 it stayed up another 27 minutes after wine exited.
//
//  THE REQUEST, measured twice on 2026-09-14 on a DualSense Edge (054c:0df2)
//  over Bluetooth with no wine running: feature report 0x08, 48 bytes,
//  [0x08, 0x02, 42 zero bytes, CRC-32 LE] with the CRC over the seed byte 0x53
//  followed by the first 44 bytes. IOHIDDeviceSetReport returned 0 on a shared
//  open and on a seized one, and the pad disconnected itself 63 and 64 ms
//  later (bluetoothd: reason 431, ACL 10719), its light went off, and it did
//  not come back until PS was pressed. A plain DualSense (054c:0ce6), opened
//  shared, did the same 62 ms later.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated enum IdlePadPowerOff {

    // MARK: - The setting

    /// Where the choice is kept, in the application's suite beside the
    /// controller-bus switch.
    static let settingKey = "idlePadPowerOffMinutes"

    /// What the menu offers. 0 is Off.
    static let choices = [0, 10, 20, 30, 60]

    /// A reasoned default, not a measurement: above the pad's own power-off
    /// (measured once at 686 s) and macOS's 900 s cut, so a pad here is never
    /// turned off sooner than one macOS looks after would be.
    static let byDefault = 20

    /// A stored number the menu cannot show is a leftover, not a choice.
    static func pickable(_ raw: Int?) -> Int {
        guard let raw, choices.contains(raw) else { return byDefault }
        return raw
    }

    /// The saved choice, or the default where nothing is saved.
    static func storedMinutes() -> Int {
        pickable(readUsrDefOptionInt(key: settingKey))
    }

    static func label(_ minutes: Int) -> String {
        let m = pickable(minutes)
        return m == 0 ? "Off" : "\(m) minutes"
    }

    static var dropdownOptions: [(id: Int, label: String)] {
        choices.map { (id: $0, label: label($0)) }
    }

    /// What goes into "IdlePowerOffMinutes" under both DualSense keys: the
    /// chosen minutes, 0 for Off -- and 0 on an engine whose winebus does not
    /// read the value, the neutral-value rule every other pad value follows.
    static func registryValue(minutes: Int, engineCanPowerOffIdle: Bool) -> UInt32 {
        engineCanPowerOffIdle ? UInt32(pickable(minutes)) : 0
    }

    // MARK: - The request

    static let featureReportID: UInt8 = 0x08
    static let reportLength = 48
    /// The byte the pad's feature-report CRC is seeded with.
    static let crcSeed: UInt8 = 0x53

    /// The report that was measured to turn the pad off, CRC included. For
    /// this content the last four bytes are e0 ef a2 23, the same tail
    /// mgvf-0005 appended to libScePad's own write on 2026-09-08.
    static func powerOffReport() -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportLength)
        report[0] = featureReportID
        report[1] = 0x02
        let crc = DualSenseRumble.crc32([crcSeed] + report[0..<44])
        report[44] = UInt8(crc & 0xff)
        report[45] = UInt8((crc >> 8) & 0xff)
        report[46] = UInt8((crc >> 16) & 0xff)
        report[47] = UInt8((crc >> 24) & 0xff)
        return report
    }

    // MARK: - What counts as somebody using the pad

    /// Sticks and triggers have to move more than this from the reference to
    /// count. The traces' idle stretches never moved more than 2 from theirs
    /// (hid-175158 minutes 19-25, hid-114844 minutes 4-10 and 15-17), and play
    /// in hid-203611 counts 400 to 1700 times a minute at this band.
    static let deadband = 4

    /// Only the parts of a report a person moves. Gyro, accelerometer,
    /// timestamps, battery, and the touchpad's contact and coordinates are
    /// left out, so touchpad-only or motion-only use does not count.
    ///
    /// Fixed-size vectors, not arrays: one is built for every report, about
    /// 64 a second per pad, and a vector costs no allocation.
    struct Snapshot: Equatable {
        enum Layout: Equatable { case simple, full }
        let layout: Layout
        /// Left X, left Y, right X, right Y, L2, R2 -- one order for both
        /// layouts. The last two lanes are always 0.
        let axes: SIMD8<UInt8>
        /// The button bytes, in the order wine's own fixup maps them; the
        /// fourth is 0 in the simple layout.
        let buttons: SIMD4<UInt8>
    }

    /// Reads a Bluetooth input report as IOKit hands it over, report id first.
    /// The same rule as mgvf-0033's dualsense_activity_snapshot, byte for byte.
    ///
    /// 0x31, 78 bytes (wine main.c: "Prefix X Y Z Rz TriggerLeft TriggerRight
    /// Counter Buttons[3]"): sticks at 2..5, triggers at 6..7, the counter at 8,
    /// buttons at 9, 10, 11 and 12. Bytes 11 and 12 count whole: bits 0..2 of
    /// 11 are PS, touchpad click and mute, and where an Edge reports Fn and
    /// the back paddles is not measured yet, so a mask could drop real
    /// buttons. None of byte 11's bits changed in an untouched minute of four
    /// traces, both models (hid-114844, hid-175158, hid-203611, hid-090147);
    /// only bits 0 and 1 ever changed, in minutes with other input. Byte 12
    /// never changed in any of the 33 Desktop traces that carry the raw 0x31.
    ///
    /// 0x01, 10 bytes, before a client asks for full reports: sticks at 1..4,
    /// buttons at 5, 6 and 7, triggers at 8..9. The upper six bits of byte 7 are
    /// a counter -- unmasked, 1572 false changes in one minute of hid-090147 --
    /// so only its low two bits count.
    ///
    /// Anything else is not read, and a report that is not read does not show
    /// the pad as being watched either.
    static func snapshot(of report: UnsafeBufferPointer<UInt8>) -> Snapshot? {
        guard let id = report.first else { return nil }
        if id == 0x31 && report.count >= 13 {
            return Snapshot(layout: .full,
                            axes: SIMD8(report[2], report[3], report[4], report[5], report[6], report[7], 0, 0),
                            buttons: SIMD4(report[9], report[10], report[11], report[12]))
        }
        if id == 0x01 && report.count == 10 {
            return Snapshot(layout: .simple,
                            axes: SIMD8(report[1], report[2], report[3], report[4], report[8], report[9], 0, 0),
                            buttons: SIMD4(report[5], report[6], report[7] & 0x03, 0))
        }
        return nil
    }

    static func snapshot(of report: [UInt8]) -> Snapshot? {
        report.withUnsafeBufferPointer { snapshot(of: $0) }
    }

    /// Whether `snapshot` is somebody using the pad, measured against the last
    /// snapshot that counted -- never against the previous report, or jitter a
    /// count at a time would add up to a moved stick.
    static func counts(_ snapshot: Snapshot, against reference: Snapshot) -> Bool {
        if snapshot.buttons != reference.buttons { return true }
        let distance = pointwiseMax(snapshot.axes, reference.axes) &- pointwiseMin(snapshot.axes, reference.axes)
        return any(distance .> SIMD8(repeating: UInt8(deadband)))
    }

    /// How long a pad may go without a readable report before it is no longer
    /// being watched. A Bluetooth pad sends about 64 a second; a pad wine has
    /// seized sends RaccoonBot none at all, and silence is never idleness.
    static let reportGap: TimeInterval = 10

    /// One pad's idle clock.
    struct Clock: Equatable {
        /// The last snapshot that counted, or the first one seen after a gap.
        private(set) var reference: Snapshot?
        private(set) var lastActivity: TimeInterval?
        private(set) var lastReport: TimeInterval?

        init() {}

        /// Takes one report. Returns true only when it counted as somebody
        /// using the pad. The first readable report after a gap starts the clock
        /// from that moment and is not activity; nor is a change of layout, which
        /// only replaces the reference.
        @discardableResult
        mutating func observe(_ report: [UInt8], at now: TimeInterval) -> Bool {
            guard let snapshot = IdlePadPowerOff.snapshot(of: report) else { return false }
            return observe(snapshot, at: now)
        }

        /// The same, for a report already read.
        @discardableResult
        mutating func observe(_ snapshot: Snapshot, at now: TimeInterval) -> Bool {
            let fresh = lastReport.map { now - $0 > IdlePadPowerOff.reportGap } ?? true
            lastReport = now
            if fresh || lastActivity == nil {
                reference = snapshot
                lastActivity = now
                return false
            }
            guard let reference, reference.layout == snapshot.layout else {
                self.reference = snapshot
                return false
            }
            guard IdlePadPowerOff.counts(snapshot, against: reference) else { return false }
            self.reference = snapshot
            lastActivity = now
            return true
        }

        /// Forget everything: the clock starts again with the next report.
        mutating func reset() { self = Clock() }
    }

    // MARK: - The decision

    enum Decision: Equatable {
        /// The setting is Off.
        case off
        /// A game RaccoonBot launched is running; the engine looks after the pad.
        case gameRunning
        /// No readable report lately: somebody else holds the pad, or it is
        /// asleep. Never idle.
        case unseen
        /// The request already went out and nothing has counted since.
        case alreadyAsked
        /// Watched and idle for less than the setting; this much is left.
        case waiting(remaining: TimeInterval)
        case powerOff
    }

    static func decide(minutes: Int, gameRunning: Bool, clock: Clock, now: TimeInterval,
                       alreadyAsked: Bool) -> Decision {
        let m = pickable(minutes)
        if m == 0 { return .off }
        if gameRunning { return .gameRunning }
        guard let lastReport = clock.lastReport, now - lastReport <= reportGap,
              let lastActivity = clock.lastActivity else { return .unseen }
        if alreadyAsked { return .alreadyAsked }
        let idle = now - lastActivity
        let limit = TimeInterval(m * 60)
        return idle >= limit ? .powerOff : .waiting(remaining: limit - idle)
    }

    // MARK: - One pad, without IOKit

    /// How long to wait before opening a pad again that RaccoonBot has heard
    /// nothing from, after `attempts` opens in a row that brought no report:
    /// 30 s, doubling, at most 10 minutes. A pad a wine process holds sends
    /// nothing for as long as it is held -- Steam idling after a game can hold
    /// it all day -- and it should not be closed and opened once a minute for
    /// all of that.
    static func reopenInterval(afterSilentAttempts attempts: Int) -> TimeInterval {
        min(30 * pow(2, TimeInterval(max(0, min(attempts, 10)))), 600)
    }

    /// What IOKit answered, reduced to what the watcher decides on.
    enum Answer: Equatable {
        case success
        /// kIOReturnExclusiveAccess: another process holds the pad.
        case exclusiveAccess
        case other(Int32)
    }

    /// Everything the watcher keeps about one pad, and every decision it takes
    /// about it. IdlePadWatcher only carries out the actions this returns, so
    /// the rules a held pad depends on are tested here, not on a live pad.
    struct PadState: Equatable {
        enum Action: Equatable { case none, open, close, reopen, powerOff }
        enum Heard: Equatable {
            case ignored, counted, nothing
            /// Still sending input this many seconds after the request.
            case stillUp(seconds: Int)
        }
        enum Requested: Equatable { case heldElsewhere, asked, failed(Int32) }

        private(set) var clock = Clock()
        private(set) var isOpen = false
        /// When the power-off request went out, until something counts again.
        private(set) var askedAt: TimeInterval?
        private(set) var saidStillUp = false
        private(set) var lastRefusal: Answer?
        private(set) var lastAttempt: TimeInterval?
        private(set) var silentAttempts = 0

        init() {}

        /// Whether an open may be tried now.
        func mayAttemptOpen(at now: TimeInterval) -> Bool {
            guard let lastAttempt else { return true }
            return now - lastAttempt >= IdlePadPowerOff.reopenInterval(afterSilentAttempts: silentAttempts)
        }

        /// A pad arrived: open it, unless a game is running.
        mutating func arrived(gameRunning: Bool, at now: TimeInterval) -> Action {
            guard !gameRunning else { return .none }
            noteAttempt(at: now)
            return .open
        }

        /// The answer to an open. Returns the refusal to log, once per kind.
        mutating func opened(_ answer: Answer, at now: TimeInterval) -> Answer? {
            clock.reset()
            guard answer == .success else {
                isOpen = false
                guard lastRefusal != answer else { return nil }
                lastRefusal = answer
                return answer
            }
            lastRefusal = nil
            isOpen = true
            return nil
        }

        mutating func closed() { isOpen = false }

        /// A launch is starting, or a game is running: nothing that came
        /// before counts, and RaccoonBot lets go of the pad so the engine is
        /// the only one opening it. Whether a shared open here would stop
        /// winebus seizing it is not measured, so it is not left to chance.
        mutating func standAside() -> Action {
            clock.reset()
            askedAt = nil
            saidStillUp = false
            lastAttempt = nil
            silentAttempts = 0
            return isOpen ? .close : .none
        }

        /// One input report.
        mutating func heard(_ snapshot: Snapshot?, at now: TimeInterval) -> Heard {
            guard isOpen, let snapshot else { return .ignored }
            silentAttempts = 0
            if clock.observe(snapshot, at: now) {
                askedAt = nil
                saidStillUp = false
                return .counted
            }
            if let askedAt, !saidStillUp, now - askedAt > IdlePadPowerOff.reportGap {
                saidStillUp = true
                return .stillUp(seconds: Int(now - askedAt))
            }
            return .nothing
        }

        /// The minute's look at the pad.
        mutating func tick(minutes: Int, gameRunning: Bool, at now: TimeInterval) -> Action {
            switch IdlePadPowerOff.decide(minutes: minutes, gameRunning: gameRunning, clock: clock, now: now,
                                          alreadyAsked: askedAt != nil) {
            case .off, .alreadyAsked, .waiting:
                return .none
            case .gameRunning:
                return standAside()
            case .unseen:
                // A pad that was held and let go may need opening again to be
                // heard: closed, or open with nothing arriving.
                clock.reset()
                guard mayAttemptOpen(at: now) else { return .none }
                noteAttempt(at: now)
                return isOpen ? .reopen : .open
            case .powerOff:
                return .powerOff
            }
        }

        /// The answer to the power-off request.
        mutating func requested(_ answer: Answer, at now: TimeInterval) -> Requested {
            switch answer {
            case .exclusiveAccess:
                clock.reset()
                return .heldElsewhere
            case .success:
                askedAt = now
                saidStillUp = false
                return .asked
            case .other(let code):
                askedAt = now
                saidStillUp = false
                return .failed(code)
            }
        }

        private mutating func noteAttempt(at now: TimeInterval) {
            if lastAttempt != nil { silentAttempts += 1 }
            lastAttempt = now
        }
    }
}
