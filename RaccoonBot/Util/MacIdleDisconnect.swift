//
//  MacIdleDisconnect.swift
//  RaccoonBot
//
//  Which DualSense macOS's own gamepad driver holds while a bottle seizes
//  it, written to the console when a Windows title starts. Measurement only:
//  nothing here changes a launch or speaks to the player.
//
//  macOS's own gamepad driver (AppleGCHIDUserEventDriver, with Sony's
//  DualSense plugin) disconnects a Bluetooth DualSense when it has seen no
//  input for 900 s. A winebus that seizes the pad (mgvf-0006) takes every
//  report for itself, so on a connection that driver is attached to, macOS's
//  clock runs out in the middle of a game: measured four times, reason 10722
//  each time. A connection that came up while the bottle already held the pad
//  gets no driver at all, and that connection was never cut -- 6,751 s
//  through two titles on 2026-09-13, 6,429 s on 2026-09-12. The console line
//  is there so a later cut can be matched to the launch that preceded it.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import IOKit

nonisolated enum MacIdleDisconnect {

    /// One spelling for a serial, whichever side it was read from.
    ///
    /// Measured on 2026-09-14 both the driver's entry and the pad's
    /// IOHIDUserDevice carried "50:EE:32:C4:8E:F2" -- uppercase hex with
    /// colons -- but only one machine and one pad have been read, and a format
    /// mismatch here is a console line that silently never appears. So both sides go
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
    /// bottle set to SeizeDevice=0 still gets the line: whether a shared open
    /// lets macOS's clock reset has not been measured, and a line that may be
    /// unneeded costs less than a cut the log cannot explain.
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

    static func model(of pad: SonyPads.Pad) -> String {
        pad.productID == SonyPads.dualSenseEdge ? "DualSense Edge" : "DualSense"
    }

    /// The console's line for one pad at risk, for the log and not for the
    /// player. It states what was detected and what macOS was measured to do
    /// with it, and nothing about what anyone should do.
    static func consoleLine(for pad: SonyPads.Pad) -> String {
        "controller: macOS's gamepad driver is attached to the \(model(of: pad)) on Bluetooth "
        + "(\(pad.serialNumber ?? "no serial")); macOS disconnects such a pad about 900 s after the last input "
        + "it sees, and while this bottle holds the pad it sees none"
    }

    /// The serials of every Sony pad macOS's gamepad driver sits on over
    /// Bluetooth. Not tested: it is IOKit, and the filter above is.
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
