//
//  MacIdleDisconnect.swift
//  RaccoonBot
//
//  Which DualSense macOS will cut about fifteen minutes into play, asked
//  before Play and not after.
//
//  macOS's own gamepad driver (AppleGCHIDUserEventDriver, with Sony's
//  DualSense plugin) disconnects a Bluetooth DualSense when it has seen no
//  input for 900 s. A winebus that seizes the pad (mgvf-0006) takes every
//  report for itself, so on a connection that driver is attached to, macOS's
//  clock runs out in the middle of a game: measured four times, reason 10722
//  each time. A connection that came up while the bottle already held the pad
//  gets no driver at all, and that connection was never cut -- 6,751 s
//  through two titles on 2026-09-13, 6,429 s on 2026-09-12. So the one thing a
//  player can do is turn the pad off and on once the game is up, and the one
//  moment this application can say so is before the launch: afterwards the
//  game is in front and an alert would sit behind it.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import IOKit

nonisolated enum MacIdleDisconnect {

    /// Set by "Start, and don't show this again"; removed from Tools.
    static let suppressionKey = "raccoonbot.notice.dualSenseIdleDisconnect"

    /// One spelling for a serial, whichever side it was read from.
    ///
    /// Measured on 2026-09-14 both the driver's entry and the pad's
    /// IOHIDUserDevice carried "50:EE:32:C4:8E:F2" -- uppercase hex with
    /// colons -- but only one machine and one pad have been read, and a format
    /// mismatch here is a notice that silently never shows. So both sides go
    /// through this, and only the hex digits are compared: case, colons,
    /// dashes, spaces or no separators at all are the same serial.
    static func normalized(_ serial: String) -> String {
        String(serial.uppercased().filter(\.isHexDigit))
    }

    /// The pads macOS's driver holds on Bluetooth, while the engine will seize
    /// them.
    ///
    /// "Bluetooth" exactly, not `isBluetooth`: the plugin's idle disconnect
    /// asks for Bluetooth Classic, and a DualSense on BluetoothLowEnergy is not
    /// what was measured. A pad whose serial IOKit did not give us is never at
    /// risk -- no guess about which driver entry is its.
    ///
    /// The bottle's own SeizeDevice value is not read in this version, so a
    /// bottle set to SeizeDevice=0 still gets the notice: whether a shared open
    /// lets macOS's clock reset has not been measured, and a warning that may
    /// be unneeded costs less than a cut that was not warned about.
    static func padsAtRisk(pads: [SonyPads.Pad], driverSerials: Set<String>,
                           engineSeizes: Bool) -> [SonyPads.Pad] {
        guard engineSeizes else { return [] }
        let held = Set(driverSerials.map(normalized)).subtracting([""])
        return pads.filter { pad in
            guard SonyPads.models.contains(pad.productID), pad.transport == "Bluetooth",
                  let serial = pad.serialNumber else { return false }
            return held.contains(normalized(serial))
        }
    }

    /// Whether Play stops to say so.
    static func shouldAsk(atRisk: [SonyPads.Pad], isNative: Bool,
                          suppressed: Bool, acknowledged: Bool) -> Bool {
        !atRisk.isEmpty && !isNative && !suppressed && !acknowledged
    }

    /// What one Play press does with the pads at risk: the ones to ask about,
    /// or, when the launch goes ahead, the console's lines for each. Never
    /// both, so one launch leaves one set of lines -- and a launch after
    /// "Start" asks nothing, or the notice would come back on every Start.
    static func launchDecision(atRisk: [SonyPads.Pad], isNative: Bool, suppressed: Bool,
                               acknowledged: Bool) -> (ask: [SonyPads.Pad], log: [String]) {
        if shouldAsk(atRisk: atRisk, isNative: isNative, suppressed: suppressed, acknowledged: acknowledged) {
            return (atRisk, [])
        }
        return ([], atRisk.map { consoleLine(for: $0, suppressed: suppressed) })
    }

    static func model(of pad: SonyPads.Pad) -> String {
        pad.productID == SonyPads.dualSenseEdge ? "DualSense Edge" : "DualSense"
    }

    /// The alert. Every clause in the body is measured: the cut about fifteen
    /// minutes in, on a pad connected before the game, and that a connection
    /// made after the window appeared was left alone every time it happened.
    /// It does not promise that it will keep happening, and it says nothing
    /// about this application's own pad navigation on such a connection, which
    /// has not been tried.
    static func message(for pads: [SonyPads.Pad]) -> (title: String, body: String) {
        let subject = pads.count == 1 ? "your \(model(of: pads[0]))" : "your controllers"
        return ("Turn \(subject) off and on once the game is up",
                "macOS disconnects a DualSense on Bluetooth about 15 minutes into play when it was connected "
                + "before the game started. Turning it off and on after the game's window appears has stopped "
                + "that every time so far: macOS then leaves that connection alone.")
    }

    /// The console's line for one pad at risk, for the log and not for the
    /// player: a later cut can be explained from it, including when the notice
    /// was turned off.
    static func consoleLine(for pad: SonyPads.Pad, suppressed: Bool) -> String {
        "controller: macOS's gamepad driver is attached to the \(model(of: pad)) on Bluetooth "
        + "(\(pad.serialNumber ?? "no serial")); while this bottle holds the pad macOS sees none of its input, "
        + "and it disconnects the pad about 15 minutes after the last input it saw"
        + (suppressed ? "; the notice about this is turned off (Tools brings it back)" : "")
    }

    /// The serials of every Sony pad macOS's gamepad driver sits on over
    /// Bluetooth. Not tested: it is IOKit, and the decision above is.
    ///
    /// Filtered strictly on all four properties. IOKitDiagnostics listed
    /// sixteen AppleGCHIDUserEventDriver instances on this machine while the
    /// pad had none, so a match on the class alone means nothing.
    /// `GameControllerSupportedHIDDevice` is not used: it read No while the
    /// driver was attached. The parents are searched as well, because only
    /// the attached state was read and a key may sit on the IOHIDInterface or
    /// IOHIDUserDevice above the driver rather than on the driver itself.
    static func driverSerials() -> Set<String> {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleGCHIDUserEventDriver"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var serials: Set<String> = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            func property(_ key: String) -> Any? {
                IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
            }
            guard (property("VendorID") as? NSNumber)?.intValue == SonyPads.vendorID,
                  let pid = (property("ProductID") as? NSNumber)?.intValue, SonyPads.models.contains(pid),
                  property("Transport") as? String == "Bluetooth",
                  let serial = property("SerialNumber") as? String, !serial.isEmpty
            else { continue }
            serials.insert(serial)
        }
        return serials
    }
}
