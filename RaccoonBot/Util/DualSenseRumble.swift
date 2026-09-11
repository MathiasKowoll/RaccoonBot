//
//  DualSenseRumble.swift
//  RaccoonBot
//
//  Making the pad buzz from here, so a percentage can be felt while it is
//  chosen.
//
//  The vibration option is a preference and not a repair -- see
//  `DualSenseVibration` -- and a preference is chosen by feel. Until now the
//  only way to feel it was to write the registry, boot a bottle, start a title
//  and wait for something in the game to rumble; a percentage picked that way
//  costs a launch per guess. Nothing about the pad's own protocol needs wine,
//  though: this Mac can write the report itself.
//
//  WHAT IS SENT, AND WHY IT IS THIS
//
//  The same two paths mgvf-0009 chooses between, with the bits that patch
//  names, so that pressing the button and playing a game ask the pad for the
//  same thing:
//
//      the haptic path   flag0 0x02, byte 38 of the common block 0x04
//                        -- what the measured title asks for, and what SDL
//                        sends on firmware 2.24 and newer
//      legacy motors     flag0 0x01|0x02, byte 38 0x00
//                        -- what "Stronger motors" rewrites that into
//
//  Over Bluetooth this rides in output report 0x31, 78 bytes: report id, a
//  4-bit sequence in the high nibble of byte 1, the 0x10 tag, the 47-byte
//  common block, 24 reserved bytes, and a CRC-32 over 0xA2 followed by the
//  first 74 bytes. The pad drops a 0x31 whose CRC does not cover the report,
//  so the signature is not decoration. Over USB the same common block goes out
//  as report 0x02, 48 bytes, with no CRC at all.
//
//  Proven outside this application first: dsrumble.c, in C against IOKit, made
//  this pad rumble with exactly these bytes. This is that program, said in
//  Swift, with the mode and the percentage from the panel.
//
//  WHAT IT CANNOT CLAIM
//
//  The percentage the driver applies multiplies what the GAME asks for. There
//  is no game here, so the pulse multiplies `referenceRequest` instead -- a
//  quarter-scale request, chosen so the whole slider is audible in the hand.
//  A test at 255 would feel identical at every percentage above 100, because
//  the gain saturates, which is exactly the thing the option's own help text
//  has to explain. So this is a taste of the choice, not a rehearsal of a
//  particular game.
//
//  TWO HONEST LIMITS
//
//  A running bottle holds the pad: wine opens it and IOKit then refuses
//  everyone else, which comes back as an IOReturn and is said in words rather
//  than as a button that appears to do nothing. And no pad attached is its own
//  sentence -- the option is still worth setting for a pad that is not here,
//  since winebus reads it as the pad arrives, but nothing can be felt.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import IOKit.hid

nonisolated enum DualSenseRumble {

    // MARK: - The report

    /// Which way the motors are driven. The two mgvf-0009 chooses between, and
    /// nothing else: asking for both at once is a third thing that neither the
    /// game nor the option ever asks for.
    enum Path: Equatable {
        /// flag0 0x01|0x02: the older compatible motors, what "Stronger
        /// motors" asks the driver to select.
        case legacyMotors
        /// flag0 0x02 with byte 38 0x04: the improved emulation on 2.24
        /// firmware and newer, which is what the measured title asks for.
        case haptic

        /// The first flag byte. Bit 0x02 -- SDL's "disable audio haptics" --
        /// is on both, because it is not the choice between them.
        var flag0: UInt8 { self == .legacyMotors ? 0x01 | 0x02 : 0x02 }
        /// Byte 38 of the common block, SDL's third enable byte.
        var flag2: UInt8 { self == .legacyMotors ? 0x00 : 0x04 }
    }

    /// The path a choice asks for: the same one the driver takes, which is
    /// what makes the pulse worth feeling. `as asked` keeps the game's own
    /// path; `stronger` and `custom` are both the rewrite, because custom is
    /// stronger with the strength chosen by hand.
    static func path(for vibration: DualSenseVibration) -> Path {
        vibration.modeValue == 1 ? .legacyMotors : .haptic
    }

    /// What the pulse asks for before the percentage is applied.
    ///
    /// A quarter of full scale, so that the whole slider can be felt.
    ///
    /// A gain multiplies what a game asks for and saturates at 255, so the
    /// reference this test scales decides how much of the slider does anything
    /// at all. It has been lowered twice for the same reason, and the second
    /// time is worth writing down.
    ///
    /// At half scale, 200% already reached 255 and every step above it felt
    /// identical -- which is exactly what the first person to try it reported.
    /// A quarter, 64, fixed that for a slider that stopped at 400%.
    ///
    /// Then the ceiling became x10, and 64 saturated at x4 again: the top
    /// three fifths of the slider could not be previewed. 25 reaches 250 at
    /// x10, so the whole range is a range in the hand -- and it is far closer
    /// to what a game actually asks. Measured over Bluetooth on 2026-09-10,
    /// Beast of Reincarnation asked for 1, 7, 9, 22 and 42 of 255 across a
    /// session. At 64 this pulse was some nine times whatever that title was
    /// asking, which is why the button always felt strong while the game felt
    /// thin, and why the button was a poor preview of it.
    ///
    /// It stays a reference and not a promise: a game that already asks for
    /// 255 cannot be made louder by any of this, and no test pulse can show
    /// that. What the pulse shows is the shape of the multiplier.
    static let referenceRequest: Double = 25

    /// Both motor bytes, saturated at 255 the way the driver saturates.
    ///
    /// `asAsked` and `stronger` both buzz at the reference and are not
    /// scaled -- the slider does not apply to them in the panel either --
    /// because the pulse is there to be COMPARED: the same request through
    /// the two paths, so the difference you feel is the path and nothing
    /// else. `custom` carries the percentage, and at 0 it is silence.
    static func motor(vibration: DualSenseVibration, percent: Double) -> UInt8 {
        switch vibration {
        case .asAsked, .stronger:
            return UInt8(min(255, referenceRequest.rounded()))
        case .custom:
            let gain = Double(vibration.gainValue(percent: percent))
            return UInt8(min(255, (referenceRequest * gain / 100).rounded()))
        }
    }

    /// The 47-byte block both transports carry, the one field layout SDL's
    /// PS5 driver lays out: enable bits at 0, the two motors at 2 and 3, the
    /// third enable byte at 38. Everything else is left at zero, which asks
    /// for nothing -- the lightbar, the triggers and the microphone are not
    /// this button's business.
    static let commonLength = 47
    static func commonBlock(path: Path, motor: UInt8) -> [UInt8] {
        var block = [UInt8](repeating: 0, count: commonLength)
        block[0] = path.flag0
        block[2] = motor    // right
        block[3] = motor    // left
        block[38] = path.flag2
        return block
    }

    // MARK: - Bluetooth, report 0x31

    static let bluetoothReportID: UInt8 = 0x31
    static let bluetoothLength = 78
    /// The byte the pad's CRC is seeded with before the report itself. It is
    /// the Bluetooth HID output-report header the pad signs but never carries.
    static let bluetoothCRCSeed: UInt8 = 0xA2

    /// The report as the pad checks it, CRC and all.
    ///
    /// `sequence` is the 4-bit counter in the high nibble of byte 1. The pad
    /// does not require it to be right, but two reports in a row that carry
    /// the same one are two reports a listener cannot tell apart, so the pulse
    /// and the release that stops it do not share a value.
    static func bluetoothReport(path: Path, motor: UInt8, sequence: UInt8) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: bluetoothLength)
        report[0] = bluetoothReportID
        report[1] = (sequence & 0x0f) << 4
        report[2] = 0x10
        report.replaceSubrange(3..<(3 + commonLength), with: commonBlock(path: path, motor: motor))
        let crc = crc32([bluetoothCRCSeed] + report[0..<74])
        report[74] = UInt8(crc & 0xff)
        report[75] = UInt8((crc >> 8) & 0xff)
        report[76] = UInt8((crc >> 16) & 0xff)
        report[77] = UInt8((crc >> 24) & 0xff)
        return report
    }

    /// The report this panel's choice and percentage would send.
    static func bluetoothReport(vibration: DualSenseVibration, percent: Double, sequence: UInt8) -> [UInt8] {
        bluetoothReport(path: path(for: vibration),
                        motor: motor(vibration: vibration, percent: percent),
                        sequence: sequence)
    }

    // MARK: - USB, report 0x02

    static let usbReportID: UInt8 = 0x02
    static let usbLength = 48

    /// The same block on a cable: report id, common block, nothing else. No
    /// CRC -- the pad only asks for one over Bluetooth.
    static func usbReport(path: Path, motor: UInt8) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: usbLength)
        report[0] = usbReportID
        report.replaceSubrange(1..<(1 + commonLength), with: commonBlock(path: path, motor: motor))
        return report
    }

    static func usbReport(vibration: DualSenseVibration, percent: Double) -> [UInt8] {
        usbReport(path: path(for: vibration),
                  motor: motor(vibration: vibration, percent: percent))
    }

    // MARK: - The signature

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    /// CRC-32 as zlib computes it -- the IEEE polynomial, reflected, starting
    /// from all ones and inverted at the end. Written here rather than linked
    /// from zlib so the rule is one this project can state in a test.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - The pad itself

    /// What pressing the button did, in words the panel can show.
    ///
    /// Every case says something. A button that silently does nothing is the
    /// failure this application has spent measurement time chasing elsewhere:
    /// there is no outcome here that leaves the person guessing whether the
    /// press was heard.
    enum Outcome: Equatable {
        /// It went out, and this is what was asked for.
        case buzzed(String)
        /// The choice is `off`, so the report that went out is silence. The
        /// pad was still reached, which is worth saying.
        case silent
        /// Nothing of ours is attached.
        case noPad
        /// IOKit refused the device to us. The usual reason by far is a
        /// running bottle: wine has it open.
        case refused(transport: String, code: Int32)
        /// IOKit refused before any device was even looked at.
        case noAccess(code: Int32)

        var message: String {
            switch self {
            case .buzzed(let what):
                return what
            case .silent:
                return "The pad answered, and stayed quiet: a strength of 0% silences it, so there is nothing to feel. Pick another choice to test one."
            case .noPad:
                return "No DualSense is attached, so there is nothing to buzz. The choice is still written for both models, and winebus reads it as the pad arrives."
            case .refused(let transport, let code):
                return "The DualSense on \(transport) is there, but macOS would not open it (IOReturn 0x\(String(format: "%08x", UInt32(bitPattern: code)))). A running bottle holds the pad: close the game and the launcher, and press this again."
            case .noAccess(let code):
                return "macOS would not let this application look at the HID devices at all (IOReturn 0x\(String(format: "%08x", UInt32(bitPattern: code)))). Nothing was sent."
            }
        }

        /// Whether this is a failure, so the panel can colour it as one. A
        /// silent pad is not a failure; a pad nobody can open is.
        var isProblem: Bool {
            switch self {
            case .buzzed, .silent: return false
            case .noPad, .refused, .noAccess: return true
            }
        }
    }

    /// Buzz the first DualSense attached, then stop it.
    ///
    /// Blocking, on purpose: it sends, waits the length of the pulse and sends
    /// the release, so the caller gets one answer describing the whole thing.
    /// Called off the main thread.
    ///
    /// The device is opened non-seizing, the way `SonyPads.attached` reads
    /// properties without opening anything: this borrows the pad for under a
    /// second and gives it straight back. It is never called while a bottle
    /// is being written -- there is nothing to coordinate, since the failure a
    /// running bottle causes is reported rather than avoided.
    static func pulse(vibration: DualSenseVibration, percent: Double,
                      milliseconds: UInt32 = 600) -> Outcome {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: SonyPads.vendorID] as CFDictionary)
        let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard opened == kIOReturnSuccess else { return .noAccess(code: opened) }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return .noPad }
        // The first of ours, whichever it is. Two pads on one desk is a case
        // nobody here has, and buzzing both would say less than buzzing one.
        let mine = devices.compactMap { device -> (device: IOHIDDevice, productID: Int, transport: String)? in
            guard let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
                  SonyPads.models.contains(pid),
                  let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
            else { return nil }
            return (device, pid, transport)
        }.sorted { $0.productID < $1.productID }
        guard let pad = mine.first else { return .noPad }

        let open = IOHIDDeviceOpen(pad.device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard open == kIOReturnSuccess else { return .refused(transport: pad.transport, code: open) }
        defer { IOHIDDeviceClose(pad.device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let bluetooth = pad.transport.hasPrefix("Bluetooth")
        let chosen = path(for: vibration)
        let strength = motor(vibration: vibration, percent: percent)
        let on = bluetooth ? bluetoothReport(path: chosen, motor: strength, sequence: 1)
                           : usbReport(path: chosen, motor: strength)
        // The release carries the same flags with the motors at zero. An
        // all-zero block would not stop anything: with no enable bit set the
        // pad is being told to change nothing.
        let off = bluetooth ? bluetoothReport(path: chosen, motor: 0, sequence: 2)
                            : usbReport(path: chosen, motor: 0)
        let reportID = CFIndex(bluetooth ? bluetoothReportID : usbReportID)

        let sent = on.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(pad.device, kIOHIDReportTypeOutput, reportID, $0.baseAddress!, $0.count)
        }
        guard sent == kIOReturnSuccess else { return .refused(transport: pad.transport, code: sent) }
        usleep(milliseconds * 1000)
        _ = off.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(pad.device, kIOHIDReportTypeOutput, reportID, $0.baseAddress!, $0.count)
        }
        guard !(vibration == .custom && vibration.gainValue(percent: percent) == 0) else { return .silent }
        let name = pad.productID == SonyPads.dualSenseEdge ? "DualSense Edge" : "DualSense"
        let way = chosen == .legacyMotors ? "the legacy motors" : "the game's own haptic path"
        let gain = vibration.gainValue(percent: percent)
        return .buzzed("Buzzed the \(name) on \(pad.transport) through \(way), at \(gain)% of a quarter-scale request -- motors \(strength) of 255. A game's own request is what the setting scales; this one is \(Int(referenceRequest)).")
    }
}
