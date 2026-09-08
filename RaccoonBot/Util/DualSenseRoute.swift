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

/// How a DualSense is presented to one title, chosen per game.
///
/// The default is everything this application did until now: winebus creates
/// the pad as it finds it. The other two ask MacGameVideoFix's mgvf-0005
/// winebus to create a DualSense that arrived over Bluetooth with bus type USB
/// and the pad's USB report descriptor, translating every report at the
/// boundary -- because two consumers refuse a pad they can tell is paired.
/// Sony's libScePad (1.0.4.1) reads the bus off the HidP capabilities and then
/// writes output report 0x02, which the Bluetooth descriptor does not have, so
/// hidclass refuses the write and the library drops the pad. Steam puts up
/// "plug in your controller" for a title whose store categories claim PS5
/// support but not PS5-over-Bluetooth. Both are content with a pad that looks
/// wired.
///
/// Per game and not per bottle because this is a lie told to one title, and
/// the owner has to be able to try it title by title: installing the patched
/// winebus is still one switch for the whole engine, but which pad a game sees
/// is this. Steam Input has to be off for the title as well, or Steam hands
/// the game its own Xbox pad and none of this is even reached.
///
/// Not offered, deliberately: presenting a DualSense as a DualShock 4. That is
/// not an identity swap. The DS4 has its own report descriptor, its own input
/// reports and its own output reports with the motors in other places, so it
/// would be a second translation layer between two different pads -- and
/// nothing measured needs it. Every title here that accepts a DS4 accepts a
/// DualSense once Steam Input is off for it or the pad looks wired.
nonisolated enum DualSensePresentation: String, CaseIterable {

    /// Whatever the pad is. Nothing is written into the bottle but zeros.
    case asItIs = "as-is"
    /// Wired, as the model that is actually attached.
    case wired = "wired"
    /// Wired, and as a plain DualSense whatever the model is: for a title
    /// whose Sony library was built before the Edge existed and knows only
    /// 054c:0ce6. An Edge asked for this is genuinely created as 054c:0ce6,
    /// with the plain pad's own descriptor and not with the Edge's.
    case wiredStandard = "wired-standard"

    /// What a title gets when nobody has said: the pad as it is.
    static let byDefault = DualSensePresentation.asItIs

    /// The product id this asks the driver for.
    ///
    /// Every id this can name is one the driver can serve. mgvf-0005 compiles
    /// in the USB report descriptor of both DualSense models, each read from
    /// that pad itself on a cable -- the Edge's 405 bytes and the plain pad's
    /// 289, which differ in three items and no others: output 0x02 carries 47
    /// data bytes rather than 63, feature 0xf2 is 16 rather than 53, and the
    /// Edge's profile reports 0x60..0x7b are absent. Input 0x01 is 64 on both,
    /// and the feature reports libScePad gates on are on both, which is why one
    /// set of translations serves the two.
    func askedProductID(for model: Int) -> Int {
        self == .wiredStandard ? SonyPads.dualSense : model
    }

    /// Whether this asks for the pad to be created as wired at all.
    var presentsAsWired: Bool { self != .asItIs }

    /// What goes into "ProductId". 0 means "keep the pad's own", which is also
    /// what asking a plain DualSense to look like a plain DualSense means.
    func productIDValue(for model: Int) -> UInt32 {
        let asked = askedProductID(for: model)
        return asked == model ? 0 : UInt32(asked)
    }

    var label: String {
        switch self {
        case .asItIs: return "As it is"
        case .wired: return "Wired DualSense"
        case .wiredStandard: return "Wired standard DualSense"
        }
    }

    /// The list the menu shows, in the order it is declared.
    static var dropdownOptions: DropdownOptions {
        allCases.map { (id: $0.rawValue, label: $0.label) }
    }

    /// A stored value the menu cannot show is not a choice, it is a leftover
    /// -- the same rule `pickableBackend` applies to the graphics backend, and
    /// for the same reason: the panel, the launch and the file have to give one
    /// answer to one question.
    static func pickable(_ raw: String?) -> String {
        guard let raw, let known = DualSensePresentation(rawValue: raw) else { return byDefault.rawValue }
        return known.rawValue
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
///
/// The same key carries the two values mgvf-0005 added, `UsbEmulation` and
/// `ProductId`, which say what the pad should look like rather than which way
/// it goes -- see `DualSensePresentation` above for why a title would want
/// that. Those two are read later than `Hidraw`: as the device arrives, on the
/// bus thread, rather than at driver start. It comes to the same thing for
/// anyone waiting for them to take effect, since a bottle booting is when both
/// happen, but it is why the honest answer to "when does this apply" is the
/// pad's next arrival and not the next launch.
nonisolated enum DualSenseRoute {

    static let devicesPath = "System\\\\CurrentControlSet\\\\Services\\\\winebus\\\\Devices"

    /// The three value names winebus reads under a device's key, spelled once.
    /// Spelling one of them differently writes a value nothing ever reads, and
    /// the bottle looks configured.
    static let hidrawValue = "Hidraw"
    static let usbEmulationValue = "UsbEmulation"
    static let productIDValue = "ProductId"

    struct Override: Equatable {
        /// The registry section, in the doubled-backslash form the .reg file uses.
        let path: String
        /// 0 sends the pad through SDL; 1 keeps it raw.
        let hidraw: UInt32
        /// 0 leaves the pad as winebus finds it; 1 asks mgvf-0005 to create a
        /// Bluetooth DualSense as if it were on USB.
        let usbEmulation: UInt32
        /// What goes into "ProductId": 0 keeps the pad's own id, otherwise the
        /// id this title asks to be given in its place.
        ///
        /// A request and not an outcome. Every id this application can name is
        /// one this engine's driver serves, but the driver is still the one
        /// that decides: it ignores both values for a device that is not a
        /// hidraw DualSense on Bluetooth, and refuses an id it has no
        /// descriptor for with a WARN in its own log rather than inventing one.
        let askedProductID: UInt32

        /// Defaulted so that a caller who only cares about the route -- which
        /// is what this type meant before mgvf-0005 -- still reads the same.
        init(path: String, hidraw: UInt32, usbEmulation: UInt32 = 0, askedProductID: UInt32 = 0) {
            self.path = path
            self.hidraw = hidraw
            self.usbEmulation = usbEmulation
            self.askedProductID = askedProductID
        }
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
    ///
    /// The presentation rides in the same two-entry list, and is asked for on
    /// both models whatever is attached at this moment -- which is the whole
    /// point. winebus re-reads these two values as a device arrives, so the pad
    /// that is off or on a cable when the game starts is exactly the pad the
    /// console tells its owner to reconnect; writing a 0 for it because it was
    /// not there at launch is what would make that advice impossible to follow.
    /// Nor did asking only for an attached Bluetooth pad buy any safety: the
    /// driver refuses these values by itself for anything that is not a hidraw
    /// device on BUS_TYPE_BLUETOOTH (mgvf-0005 dualsense_usb_emulation_fixups),
    /// so a value written for a pad on a cable is read and dropped there.
    ///
    /// Two gates stay. The engine has to hold mgvf-0005, or the values sit in
    /// the bottle unread. And the raw route has to be the one this same list
    /// writes -- expressed as the route, not as the transport, because
    /// `Hidraw` 0 beside `UsbEmulation` 1 under one key is a pair that
    /// contradicts itself: a pad handed to SDL is a wine gamepad long before
    /// winebus could present it as anything. With nothing attached the route
    /// written is the raw one, so the pair stays consistent and the pad that
    /// arrives later is presented.
    ///
    /// Everywhere else both values are written as zero rather than left alone,
    /// which is what makes this per game: the title that does not want the
    /// emulation clears what the last title set.
    static func overrides(for pads: [SonyPads.Pad], sdlEnabled: Bool, engineTellsTheBus: Bool,
                          presentation: DualSensePresentation = .byDefault,
                          engineCanEmulateUSB: Bool = false) -> [Override] {
        SonyPads.models.map { model in
            let onBluetooth = pads.contains { $0.productID == model && $0.isBluetooth }
            let viaSDL = onBluetooth && sdlEnabled && !engineTellsTheBus
            let emulating = presentation.presentsAsWired && engineCanEmulateUSB && !viaSDL
            return Override(path: sectionPath(productID: model),
                            hidraw: viaSDL ? 0 : 1,
                            usbEmulation: emulating ? 1 : 0,
                            askedProductID: emulating ? presentation.productIDValue(for: model) : 0)
        }
    }

    /// Whether the engine carries mgvf-0002: winebus that names the bus in its
    /// compatible ids. Read from the binary rather than from a version, the way
    /// this project reads everything: the literal is a UTF-16 string in the PE.
    static func engineTellsTheBus(cxAppPath: String?) -> Bool {
        contains(literal: "BTHENUM\\{00001124-0000-1000-8000-00805f9b34fb}", inWinebusOf: cxAppPath)
    }

    /// Whether the engine carries mgvf-0005: the winebus that can create a
    /// Bluetooth DualSense as a wired one. Read the same way, from the same
    /// binary -- the name of the registry value it reads is in it as a UTF-16
    /// literal, and an engine without the patch has no reason to contain that
    /// word. A build that carries mgvf-0005 carries mgvf-0002 as well, but the
    /// two are asked separately rather than inferred from each other: one
    /// question, one measurement.
    ///
    /// And it is the only question asked about the emulation -- there is no
    /// second one about which pads a given winebus can present. The engine set
    /// this application installs carries the USB report descriptor of both
    /// DualSense models, so an engine that answers yes here serves everything
    /// this menu can ask for. An older winebus somebody installed by hand might
    /// hold only the Edge's, and it refuses what it cannot serve in its own
    /// log, where the launcher cannot see it; a list kept here of what we
    /// believe some engine holds would be this application reading its own
    /// assumption back and calling it a measurement.
    static func engineCanEmulateUSB(cxAppPath: String?) -> Bool {
        contains(literal: usbEmulationValue, inWinebusOf: cxAppPath)
    }

    /// The engine's own winebus.sys, searched for a UTF-16 literal. A missing
    /// engine, or one that cannot be read, answers no -- never a guess.
    private static func contains(literal: String, inWinebusOf cxAppPath: String?) -> Bool {
        guard let cxAppPath, !cxAppPath.isEmpty else { return false }
        let sys = cxAppPath + "/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows/winebus.sys"
        guard let data = FileManager.default.contents(atPath: sys) else { return false }
        let marker = Data(literal.utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] })
        return data.range(of: marker) != nil
    }

    /// What the console says about it, or nil when there is nothing to say.
    ///
    /// One sentence per attached pad: the route it takes, what it will look
    /// like to the game, and -- when anything is being presented -- when that
    /// starts being true. Never "now": winebus reads both values as the device
    /// arrives, so a value written at launch is answered by the bottle booting
    /// or by the pad being reconnected, and a game started into a Steam that
    /// was already up inherits whatever the bottle booted with.
    ///
    /// With no DualSense attached there is still something to say, because
    /// there is still something written: the choice goes into the bottle for
    /// both models whatever is here, and the pad that arrives afterwards is
    /// the one it was written for. Silence there would read as "nothing was
    /// done", which is the opposite of what happened.
    static func summary(for pads: [SonyPads.Pad], sdlEnabled: Bool, engineTellsTheBus: Bool,
                        presentation: DualSensePresentation = .byDefault,
                        engineCanEmulateUSB: Bool = false) -> String? {
        let mine = pads.filter { SonyPads.models.contains($0.productID) }
        guard !mine.isEmpty else {
            // Nothing attached and nothing asked for is the case this stayed
            // quiet about before the option existed, and it stays quiet.
            guard presentation.presentsAsWired else { return nil }
            return engineCanEmulateUSB
                ? "no DualSense attached: the choice is written for both models all the same, so a pad that arrives over Bluetooth afterwards is presented as wired -- winebus reads it as the pad arrives"
                : "no DualSense attached, and this engine's winebus has no USB emulation: install the controller set in Options"
        }
        var anythingPresented = false
        var anythingCleared = false
        let sentences = mine.map { pad -> String in
            let name = pad.productID == SonyPads.dualSenseEdge ? "DualSense Edge" : "DualSense"
            let viaSDL = pad.isBluetooth && sdlEnabled && !engineTellsTheBus
            // Only where the driver will actually do it. The value is written
            // for this model either way -- see overrides(for:) -- but a pad on
            // a cable is a pad the driver reads it for and drops, and then
            // mgvf-0002's own sentence below is still the true one.
            let emulating = presentation.presentsAsWired && engineCanEmulateUSB && pad.isBluetooth && !viaSDL
            let route = !pad.isBluetooth ? "raw, with all its features"
                      // The emulation changes the bus type itself, so what the
                      // engine tells Steam changes with it: mgvf-0005 creates
                      // the device as USB and mgvf-0002's compatible ids and
                      // hidapi's flag follow it. Saying Bluetooth here while
                      // the next clause says wired was a sentence contradicting
                      // itself.
                      : emulating ? "raw, and the engine tells Steam it is on USB"
                      : engineTellsTheBus ? "raw, and the engine tells Steam it is on Bluetooth"
                      : sdlEnabled ? "through SDL: an Xbox-class pad, some rumble, no touchpad, gyro or PS button"
                      : "raw, and it will not rumble: turn Enable SDL on for this title"
            guard presentation.presentsAsWired else {
                // Asking for the pad as it is is a request too: it writes the
                // zeros that clear what the last title asked for, and those are
                // read at the same moment the other values are. Said here so a
                // title switched back to the default does not look immediate
                // when the pad the running bottle already created is still the
                // one the last title asked for.
                if engineCanEmulateUSB && !viaSDL { anythingCleared = true }
                return "\(name) on \(pad.transport): \(route)"
            }
            let presented: String
            if !engineCanEmulateUSB {
                presented = "not presented as wired: this engine's winebus has no USB emulation, install the controller set"
            } else if !pad.isBluetooth {
                presented = "already wired, so there is nothing to present -- the choice is written for it all the same, for when it comes back over Bluetooth"
            } else if viaSDL {
                presented = "not presented as wired: a pad handed to SDL is a wine gamepad first"
            } else if presentation.askedProductID(for: pad.productID) != pad.productID {
                // The only pair that differ: an Edge asked to be a plain one.
                // It is created as 054c:0ce6 with that pad's own descriptor,
                // so the sentence names what the game sees, not what is here.
                presented = "presented as a plain wired DualSense rather than as an Edge"
                anythingPresented = true
            } else {
                presented = "presented as a wired \(name)"
                anythingPresented = true
            }
            return "\(name) on \(pad.transport): \(route), \(presented)"
        }
        let when = anythingPresented
            ? "; it takes effect when the pad next arrives, so start with Steam closed or reconnect the pad"
            : anythingCleared
            ? "; asking for the pad as it is clears what the last title asked for, and that is read when the pad next arrives as well: a game started into a running Steam keeps whatever the bottle booted with"
            : ""
        return sentences.joined(separator: "; ") + when
    }
}
