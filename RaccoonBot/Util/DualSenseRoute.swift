//
//  DualSenseRoute.swift
//  RaccoonBot
//
//  Which way through winebus a DualSense takes, decided by how it is attached.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import IOKit.hid

/// The Sony pads attached to this Mac right now, and by what.
///
/// Asked of IOKit, which is the one party that knows the transport: winebus
/// reads the same `Transport` property (bus_iohid.c) and nobody on the Windows
/// side of it ever learns the answer -- see `DualSenseRoute` for what that
/// costs.
nonisolated enum SonyPads {

    struct Pad: Equatable {
        let productID: Int
        /// IOKit's word: "USB", "Bluetooth", "BluetoothLowEnergy".
        let transport: String
        var isBluetooth: Bool { transport.hasPrefix("Bluetooth") }
    }

    static let vendorID = 0x054C
    static let dualSense = 0x0CE6
    static let dualSenseEdge = 0x0DF2
    static let models = [dualSense, dualSenseEdge]

    /// Non-seizing, read-only: the manager is opened only to enumerate, and
    /// properties are read without opening any device.
    static func attached() -> [Pad] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return [] }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return devices.compactMap { device in
            guard let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
                  let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
            else { return nil }
            return Pad(productID: pid, transport: transport)
        }
    }
}

/// A DualSense on Bluetooth has to go through winebus's SDL backend; on USB it
/// must not.
///
/// Measured on 2026-09-08, on this machine, with the launcher's own logs and a
/// relay trace of Steam: over Bluetooth a DualSense rumbles when a correct
/// report 0x31 (78 bytes, CRC-32) reaches it through IOKit -- proven outside
/// wine with exactly that call -- and never does through wine's raw (hidraw)
/// path, because nothing on the Windows side ever learns it is on Bluetooth.
/// hidapi decides the bus by asking the HID device's parent devnode for a
/// `BTHENUM` compatible id, and under wine `CM_Get_Parent` is a stub
/// (setupapi/stubs.c) and winebus's compatible ids carry no `BTHENUM` at all
/// (winebus/main.c get_compatible_ids). Steam's own log says it plainly:
/// "Added HIDAPI device 'DualSense Edge Wireless Controller' ... bluetooth 0".
/// So Steam's PS5 driver, fed the 10-byte simple report winebus fabricates
/// for a Bluetooth pad, stays in simple mode and writes nothing -- three
/// sessions, zero output reports -- while over USB the same driver writes
/// its 0x02 reports and everything works.
///
/// winebus's SDL backend does not have the problem: SDL's PS5 driver reads
/// the transport from IOKit and builds the 0x31 with its CRC itself, and
/// bus_sdl.c forces enhanced mode on Apple. Measured the same day, it is a
/// partial answer, not a whole one: Mortal Shell II rumbles over Bluetooth
/// this way, weakly; Onimusha rumbled once and then not at all, which fits
/// wine's own xinput sending only on change and winebus cutting every rumble
/// at 1000ms (hid.c cutoff_time_ms); and the guest sees a wine gamepad rather
/// than a DualSense -- no touchpad, gyro, adaptive triggers, lightbar or PS
/// button, the last two lost by construction in winexinput.sys's ten-button
/// PDO and bus_sdl.c's mapping. Rebuilding SDL 2.30.12 with upstream's
/// Bluetooth report-format fix (129627068) changed nothing here and was
/// reverted. Over USB the raw path works and keeps everything, so the route
/// is chosen per transport, and only for these pads. The real repair is in
/// wine, and is where the work goes next: let hidapi learn the transport.
///
/// winebus honours it through
/// `HKLM\System\CurrentControlSet\Services\winebus\Devices\<vid>/<pid>`,
/// value `Hidraw` (DWORD; 0 = never raw, 1 = raw), consulted before its own
/// preference for Sony pads (main.c is_hidraw_enabled) and read when the
/// driver starts -- the same moment `DisableHidraw` is read. A pad paired
/// after the bottle is up keeps whatever route the bottle booted with.
nonisolated enum DualSenseRoute {

    static let devicesPath = "System\\\\CurrentControlSet\\\\Services\\\\winebus\\\\Devices"

    struct Override: Equatable {
        /// The registry section, in the doubled-backslash form the .reg file uses.
        let path: String
        /// 0 sends the pad through SDL; 1 keeps it raw.
        let hidraw: UInt32
    }

    static func sectionPath(productID: Int) -> String {
        devicesPath + "\\\\" + String(format: "%04x/%04x", SonyPads.vendorID, productID)
    }

    /// One override per DualSense model, always: explicit state rather than a
    /// stale one. A model on Bluetooth -- even if another of the same model is
    /// also on USB, since the override cannot tell two apart -- goes through
    /// SDL; otherwise it stays raw, which is what winebus would do unasked.
    ///
    /// Only with SDL enabled: the override does not create the SDL copy, it
    /// only stops the raw one, and with "Enable SDL" off a Bluetooth pad would
    /// simply vanish. Then raw is the lesser evil, and the console says why.
    ///
    /// And only on an engine that cannot tell the guest the transport. With
    /// MacGameVideoFix's controller-bus set installed (mgvf-0002/3/4), Steam
    /// learns "bluetooth 1" on the raw route and speaks the pad's own protocol
    /// -- measured 2026-09-08 -- so the raw route keeps every feature there and
    /// the SDL detour would only take them away.
    static func overrides(for pads: [SonyPads.Pad], sdlEnabled: Bool, engineTellsTheBus: Bool) -> [Override] {
        SonyPads.models.map { model in
            let onBluetooth = pads.contains { $0.productID == model && $0.isBluetooth }
            let viaSDL = onBluetooth && sdlEnabled && !engineTellsTheBus
            return Override(path: sectionPath(productID: model), hidraw: viaSDL ? 0 : 1)
        }
    }

    /// Whether the engine carries mgvf-0002: winebus that names the bus in its
    /// compatible ids. Read from the binary rather than from a version, the way
    /// this project reads everything: the literal is a UTF-16 string in the PE.
    static func engineTellsTheBus(cxAppPath: String?) -> Bool {
        guard let cxAppPath, !cxAppPath.isEmpty else { return false }
        let sys = cxAppPath + "/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows/winebus.sys"
        guard let data = FileManager.default.contents(atPath: sys) else { return false }
        let marker = Data("BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb}".utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] })
        return data.range(of: marker) != nil
    }

    /// What the console says about it, or nil when no DualSense is attached.
    static func summary(for pads: [SonyPads.Pad], sdlEnabled: Bool, engineTellsTheBus: Bool) -> String? {
        let mine = pads.filter { SonyPads.models.contains($0.productID) }
        guard !mine.isEmpty else { return nil }
        return mine.map { pad in
            let name = pad.productID == SonyPads.dualSenseEdge ? "DualSense Edge" : "DualSense"
            let route = !pad.isBluetooth ? "raw, with all its features"
                      : engineTellsTheBus ? "raw, and the engine tells Steam it is on Bluetooth"
                      : sdlEnabled ? "through SDL: an Xbox-class pad, some rumble, no touchpad, gyro or PS button"
                      : "raw, and it will not rumble: turn Enable SDL on for this title"
            return "\(name) on \(pad.transport): \(route)"
        }.joined(separator: "; ")
    }
}
