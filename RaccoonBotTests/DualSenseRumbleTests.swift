//
//  DualSenseRumbleTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// The report the rumble test sends, byte for byte.
///
/// Every expectation here is written from the field offsets by hand -- the
/// same rule mgvf-0009's own host test follows -- rather than by calling the
/// thing under test and agreeing with whatever it produced. The pad is the one
/// party that decides whether these bytes are right, and it is not here, so
/// the only honest test is one that states the layout independently.
///
/// The device half is not tested and cannot be: it needs a pad on the desk.
/// What is testable is everything that decides what would go out.
struct DualSenseRumbleTests {

    // MARK: - the CRC, computed the other way round

    /// CRC-32 the long way: bit by bit, no table, so a mistake in the table
    /// the application builds cannot be copied into its own check. Same
    /// polynomial, same reflection, same start and end.
    private func referenceCRC(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// The one published number for this algorithm: "123456789" is 0xCBF43926.
    @Test func theCRCIsTheOneEverybodyElseComputes() {
        let digits = Array("123456789".utf8)
        #expect(referenceCRC(digits) == 0xCBF4_3926)
        #expect(DualSenseRumble.crc32(digits) == 0xCBF4_3926)
    }

    /// And the seed rule the driver uses: the 0xA2 Bluetooth header byte the
    /// pad signs but never carries, then the report's first 74 bytes, little
    /// endian in the last four.
    @Test func theReportIsSignedOverA2AndTheFirst74Bytes() {
        let report = DualSenseRumble.bluetoothReport(vibration: .stronger, percent: 100, sequence: 1)
        let expected = referenceCRC([0xA2] + report[0..<74])
        let carried = UInt32(report[74]) | UInt32(report[75]) << 8
                    | UInt32(report[76]) << 16 | UInt32(report[77]) << 24
        #expect(carried == expected)
        #expect(DualSenseRumble.bluetoothCRCSeed == 0xA2)
    }

    /// A report signed without the seed byte would be dropped by the pad, so
    /// the seed has to be doing something: this states that it is.
    @Test func theSeedByteIsNotDecoration() {
        let report = DualSenseRumble.bluetoothReport(vibration: .stronger, percent: 100, sequence: 1)
        let carried = UInt32(report[74]) | UInt32(report[75]) << 8
                    | UInt32(report[76]) << 16 | UInt32(report[77]) << 24
        #expect(carried != referenceCRC(Array(report[0..<74])), "unseeded is a different signature")
    }

    // MARK: - the report itself

    /// "Stronger motors" at 100%: the legacy path, and the mid-scale request
    /// untouched. Written out field by field.
    @Test func theStrongerChoiceSendsTheLegacyMotors() {
        let report = DualSenseRumble.bluetoothReport(vibration: .stronger, percent: 100, sequence: 1)
        #expect(report.count == 78)
        #expect(report[0] == 0x31, "the Bluetooth output report")
        #expect(report[1] == 0x10, "sequence 1 in the high nibble")
        #expect(report[2] == 0x10, "the tag")
        #expect(report[3] == 0x03, "flag0: compatible vibration | disable audio haptics")
        #expect(report[4] == 0x00, "the second flag byte is left alone")
        #expect(report[5] == 25, "right motor: the reference request at x1")
        #expect(report[6] == 25, "left motor")
        #expect(report[41] == 0x00, "byte 38 of the common block: the haptic path is NOT selected")
        // Nothing else is asked for: no lightbar, no triggers, no microphone.
        let untouched = Array(report[7..<41]) + Array(report[42..<74])
        #expect(untouched.allSatisfy { $0 == 0 })
    }

    /// "As the game asks" keeps the path the measured title uses, so the test
    /// feels what the game feels rather than what the option would change it
    /// into.
    @Test func theDefaultChoiceSendsTheHapticPath() {
        let report = DualSenseRumble.bluetoothReport(vibration: .asAsked, percent: 100, sequence: 1)
        #expect(report[3] == 0x02, "flag0: disable audio haptics only")
        #expect(report[41] == 0x04, "byte 38: the improved emulation on 2.24 firmware and newer")
        #expect(report[5] == 25)
    }

    /// The percentage, and where it stops. 64 is what the pulse asks for before
    /// the gain, so the slider spends its whole range doing something: at half
    /// scale it used to reach 255 at 200% and every step above that felt the
    /// same, which is what the first person to use it reported.
    @Test func thePercentageScalesTheRequestAndSaturates() {
        // The percentage belongs to `custom` alone, in the panel and here.
        // The other two buzz at the reference whatever the slider says, so a
        // person switching between them feels the PATH change and nothing
        // else -- which is the comparison the button exists to make.
        // Both paths scale now, so the comparison the button exists to make --
        // the same request through the two paths -- is made by leaving the two
        // strengths equal and switching the path, not by the type ignoring one.
        #expect(DualSenseRumble.motor(vibration: .asAsked, percent: 100) == 25)
        #expect(DualSenseRumble.motor(vibration: .stronger, percent: 100) == 25,
                "same strength, two paths: what changes in the hand is the path")
        #expect(DualSenseRumble.motor(vibration: .stronger, percent: 400) == 100)
        #expect(DualSenseRumble.motor(vibration: .asAsked, percent: 25) == 6)
        #expect(DualSenseRumble.motor(vibration: .asAsked, percent: 100) == 25)
        #expect(DualSenseRumble.motor(vibration: .asAsked, percent: 150) == 38)
        #expect(DualSenseRumble.motor(vibration: .asAsked, percent: 200) == 50)
        // The reference is 25 so that the WHOLE slider is a range in the hand:
        // at the x10 ceiling it reaches 250, just short of saturating, where 64
        // saturated at x4 and left the top three fifths unpreviewable.
        #expect(DualSenseRumble.motor(vibration: .asAsked, percent: 1000) == 250)
        #expect(DualSenseRumble.motor(vibration: .asAsked, percent: 300) == 75)
        #expect(DualSenseRumble.motor(vibration: .asAsked, percent: 400) == 100)
        // A percentage from a record this build would not offer is folded into
        // the range first, exactly as the launch folds it -- and the fold is
        // now x10, so the pulse tops out at the reference times ten and never
        // at the byte. The byte is still the driver's own ceiling for a GAME:
        // Beast asking 42 reaches 255 at x6, measured 2026-09-10.
        #expect(DualSenseRumble.motor(vibration: .asAsked, percent: 100000) == 250)
        #expect(DualSenseRumble.motor(vibration: .asAsked, percent: 0) == 0, "0 is silence, and the slider reaches it")
    }

    /// Custom at 0 is silence, and the report says so with the motors and not
    /// by staying home: the enable bits are still set, because a block with no
    /// enable bit asks the pad to change nothing at all.
    @Test func silenceSendsZeroMotorsWithTheEnableBitsStillSet() {
        let report = DualSenseRumble.bluetoothReport(vibration: .asAsked, percent: 0, sequence: 1)
        #expect(report[5] == 0)
        #expect(report[6] == 0)
        #expect(report[3] == 0x02, "still a valid request, for nothing -- the haptic path custom now takes")
        #expect(DualSenseRumble.motor(vibration: .asAsked, percent: 0) == 0)
    }

    /// The release that stops the pulse is the same report with the motors at
    /// zero, and a different sequence so two identical packets do not go out
    /// back to back.
    @Test func theReleaseIsTheSameReportWithoutTheMotors() {
        let path = DualSenseRumble.path(for: .stronger)
        let on = DualSenseRumble.bluetoothReport(path: path, motor: 200, sequence: 1)
        let off = DualSenseRumble.bluetoothReport(path: path, motor: 0, sequence: 2)
        #expect(off[1] == 0x20)
        #expect(off[3] == on[3], "the same path")
        #expect(off[5] == 0 && off[6] == 0)
        #expect(off[74...] != on[74...], "and signed again, because the bytes changed")
    }

    /// On a cable the pad takes the short report and checks no signature.
    @Test func aPadOnACableTakesReport0x02() {
        let report = DualSenseRumble.usbReport(vibration: .asAsked, percent: 200)
        #expect(report.count == 48)
        #expect(report[0] == 0x02)
        #expect(report[1] == 0x02, "flag0, one byte after the id this time -- custom takes the haptic path")
        #expect(report[3] == 50, "right motor")
        #expect(report[4] == 50, "left motor")
        #expect(report[39] == 0x04, "byte 38 of the common block: the haptic path's own bit")
        #expect(report[40...].allSatisfy { $0 == 0 }, "and nothing after it -- no CRC on USB")
    }

    /// The two transports carry the same 47 bytes; only where they sit and
    /// what follows them differs.
    @Test func bothTransportsCarryTheSameCommonBlock() {
        for vibration in DualSenseVibration.allCases {
            let bt = DualSenseRumble.bluetoothReport(vibration: vibration, percent: 150, sequence: 1)
            let usb = DualSenseRumble.usbReport(vibration: vibration, percent: 150)
            #expect(Array(bt[3..<50]) == Array(usb[1..<48]), "for \(vibration)")
        }
    }

    /// Which path each choice asks for, said once so the mapping cannot drift
    /// away from the driver's: only the rewrite is the legacy one.
    @Test func onlyTheRewriteAsksForTheLegacyMotors() {
        #expect(DualSenseRumble.path(for: .stronger) == .legacyMotors)
        #expect(DualSenseRumble.path(for: .asAsked) == .haptic)
        #expect(DualSenseRumble.path(for: .asAsked) == .haptic,
                "the path is the choice and the strength is separate, so the button has to feel like the game will")
        #expect(DualSenseRumble.Path.legacyMotors.flag0 == 0x03)
        #expect(DualSenseRumble.Path.legacyMotors.flag2 == 0x00)
        #expect(DualSenseRumble.Path.haptic.flag0 == 0x02)
        #expect(DualSenseRumble.Path.haptic.flag2 == 0x04)
    }

    // MARK: - what it says afterwards

    /// Every outcome says something, and the two that are failures are marked
    /// as failures. A button that can end in silence is the defect this whole
    /// control exists to avoid.
    @Test func everyOutcomeSpeaks() {
        let outcomes: [DualSenseRumble.Outcome] = [
            .buzzed("something"), .silent, .noPad,
            .refused(transport: "Bluetooth", code: -536870203), .noAccess(code: -1),
        ]
        for outcome in outcomes {
            #expect(!outcome.message.isEmpty, "for \(outcome)")
        }
        #expect(DualSenseRumble.Outcome.noPad.isProblem)
        #expect(DualSenseRumble.Outcome.refused(transport: "USB", code: -1).isProblem)
        #expect(DualSenseRumble.Outcome.noAccess(code: -1).isProblem)
        #expect(!DualSenseRumble.Outcome.silent.isProblem, "a silenced pad answered; it did not fail")
        #expect(!DualSenseRumble.Outcome.buzzed("x").isProblem)
    }

    /// The two limits the owner has to be able to read off the panel: a pad
    /// nobody can open is a running bottle, and no pad at all is not a fault.
    @Test func theRefusalNamesTheRunningBottle() {
        let refused = DualSenseRumble.Outcome.refused(transport: "Bluetooth", code: -536870203)
        #expect(refused.message.contains("running bottle"))
        #expect(refused.message.contains("Bluetooth"))
        #expect(DualSenseRumble.Outcome.noPad.message.contains("No DualSense is attached"))
        #expect(DualSenseRumble.Outcome.noPad.message.contains("as the pad arrives"),
                "the setting is still worth having for a pad that is not here")
    }
}
