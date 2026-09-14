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

/// What a title asks of a DualSense's motors.
///
/// One control and not two, because mode and percentage are one idea: which
/// way the pad is asked to buzz, and how hard. MacGameVideoFix's mgvf-0009
/// winebus reads them as two REG_DWORDs under the same key the presentation
/// uses -- `VibrationMode` and `VibrationGain` -- and they are orthogonal
/// there, but nobody chooses a vibration path and a percentage as separate
/// questions. The picker says what the pad should do; the percentage is the
/// detail two of the three answers need.
///
/// A PREFERENCE, NOT A REPAIR, and the only option here that is. Everything
/// else this application writes for a pad repairs something measured to be
/// wrong. This changes what a game asked for into something the person
/// holding the pad likes better, so the default is the pad as the game drives
/// it, byte for byte.
///
/// Where `stronger` comes from. A title measured here on 2026-09-08 asks for
/// the full 255 and still feels soft: of 6493 output reports in a two-hour
/// Bluetooth session, 335 carry a motor byte, and all 335 select the haptic
/// path -- not most of them, all of them -- so there is no louder request for
/// the game to make. On a six-pulse ladder, sending the same value down the
/// legacy motors instead felt clearly stronger to the owner. That is one
/// person's hand on one pad, not a measurement of anything: no meter was put
/// on the motors, and the pad's firmware version was never read. It is
/// offered because it was preferred, and it is off unless asked for.
///
/// Where the percentage stops. The gain multiplies the two motor bytes and
/// saturates at 255, so a game already asking for everything cannot be made
/// to ask for more: it helps the middle of the range and not the peaks. And
/// 0 is not absence -- an absent value reads as 100 and changes nothing,
/// while a 0 written on purpose forces every motor byte to zero. That is
/// `off`: how somebody who does not want the pad to buzz turns it off for
/// every game at once, including the ones with no setting of their own.
nonisolated enum DualSenseVibration: String, CaseIterable {

    /// The pad buzzes the way the game drives it: the two values that mean
    /// "nothing asked for" are written and the driver leaves every packet
    /// alone.
    case asAsked = "as-asked"
    /// The legacy compatible motors: the pad imitates a pair of
    /// rotating-mass motors. Coarser than the haptic path and measurably
    /// harder at the same command -- 2026-09-10, both paths driven to
    /// 252/255 over Bluetooth with only the two selecting bits different.
    case stronger = "stronger"
    // `custom` was the third entry and is gone, because it was never a third
    // PATH -- it was `stronger` with a number attached, from a time when that
    // rewrite WAS how a pad was made to hit harder. Measured on 2026-09-10
    // with identical bytes on the wire, the two paths differ in character and
    // in ceiling: the haptic one is finer and saturates around x6, the legacy
    // one is harder. So the path is one question and the strength is another,
    // and each path keeps its own strength -- switching between them should
    // land where you left it, not at a number that meant something else.
    // A record that still says "custom" reads as the haptic path, which is
    // what it selected on the day it was removed.

    /// What a title gets when nobody has said: the pad as the game drives it.
    static let byDefault = DualSenseVibration.asAsked

    /// The percentage that means "leave the motor bytes alone". Written
    /// rather than left out, because every value under this key is written
    /// explicitly -- see `overrides(for:)` for why.
    static let neutralGain: UInt32 = 100

    /// What the bar offers.
    ///
    /// BACK TO 400, and this time with the measurement that settles it. It was
    /// raised to 1000 on 2026-09-10 because the rumble felt thin and the
    /// ceiling looked like the slider's fault. It was not. Two things were
    /// wrong underneath and both are fixed: the deadband was comparing the
    /// movement a game ASKED for against a band that applies at the pad, so a
    /// high setting made the rumble coarser rather than stronger (mgvf-0026),
    /// and the driver was sending the legacy motors for both menu entries, so
    /// the finer path was never actually being heard (mgvf-0024).
    ///
    /// With those fixed, the top of a 1000 bar is a lie. Measured on Beast of
    /// Reincarnation over Bluetooth: its loudest request in a session is 143 of
    /// 255, so 175% is where that reaches the ceiling and nothing clips at all.
    /// Past about 600% every request the game makes saturates, and from there
    /// to 1000 the identical byte reaches the motors -- a stretch of bar that
    /// moves and changes nothing, which is exactly what a control must never
    /// do. 400 leaves room above the point where any title measured here
    /// saturates and stops promising what the pad cannot give.
    ///
    /// A stored value above the new ceiling is folded by `pickableGain` rather
    /// than left pinned off its own scale.
    ///
    /// It starts at 0, which is silence and not a quiet pad: the driver reads
    /// 0 as a request and every other value as a multiplier.
    static let gainRange: ClosedRange<Double> = 0...400

    /// Both paths carry a strength now, and each carries its OWN. A single
    /// shared number would make switching paths a shock: the haptic path is
    /// useful to about x6 before it saturates and the legacy one is harder at
    /// every value, so the same multiplier means very different things on the
    /// two. Kept as a property rather than deleted because the panel still
    /// asks the question, and a path that ever stops taking a strength has a
    /// place to say so.
    var usesGain: Bool { true }

    /// What goes into "VibrationMode": 1 only where the path is rewritten,
    /// which is `stronger` alone. The haptic choice leaves the path to the
    /// game and carries only its strength.
    ///
    /// Since mgvf-0024 an engine on Bluetooth stamps the haptic path by
    /// default, so `asAsked` now delivers the path its name has always
    /// promised, and `stronger` is the same pair it always was: the stamp
    /// takes the haptic path and this rewrite, which runs after it, turns the
    /// packet back into the legacy motors. Nothing here changed; what changed
    /// is that the driver no longer quietly sent legacy for both.
    var modeValue: UInt32 { self == .stronger ? 1 : 0 }

    /// What goes into "VibrationGain": the strength this path was given,
    /// clamped to the range the menu can show so a record from another build
    /// cannot write a number this one would not offer. Both paths carry one;
    /// which of the two stored strengths arrives here is the panel's business,
    /// not this type's.
    func gainValue(percent: Double) -> UInt32 {
        UInt32(Self.pickableGain(percent).rounded())
    }

    /// The slider's number, as a multiplier of what the game asks.
    ///
    /// The driver's value is a percentage and stays one -- it is what goes into
    /// the registry and what every trace prints. This is the label only: "x4"
    /// where the stored value is 400. A percentage that reaches 1000 reads as a
    /// mistake, and the neutral point is what matters most here: x1 is the game
    /// untouched, which no reader has to be told.
    ///
    /// One decimal only where it is not whole, so x1.5 is reachable and x4 does
    /// not become "x4.0".
    /// Where the bar is sitting, in words, because the number was worse than
    /// nothing.
    ///
    /// It used to read "x4". A multiplier invites arithmetic that does not
    /// survive contact with the pad: the two paths saturate at different
    /// points, a title already asking for everything cannot be multiplied
    /// higher, and past the middle of the old bar the identical byte reached
    /// the motors either way. A number that is right about the request and
    /// wrong about what is felt is worse than no number at all, so nothing the
    /// person reads carries one now -- not the bar, not the console line.
    /// This is a bar of intensity and nothing else.
    static func strengthWord(_ percent: Double) -> String {
        let g = pickableGain(percent)
        if g == 0 { return "silenced" }
        if g < Double(neutralGain) { return "below what the game asks" }
        if g == Double(neutralGain) { return "at what the game asks" }
        if g <= 200 { return "a little above what the game asks" }
        return "well above what the game asks"
    }

    /// Whether this asks the driver for anything at all. `asAsked` at 100 does
    /// not, and that is the case that has to stay silent everywhere.
    func changesAnything(percent: Double) -> Bool {
        modeValue != 0 || gainValue(percent: percent) != Self.neutralGain
    }

    /// Which stored strength this path uses. Two paths, two numbers, so that
    /// switching lands where it was left.
    var gainKeyPath: ReferenceWritableKeyPath<GameOptions, Double> {
        self == .stronger ? \GameOptions.dualSenseStrongGain : \GameOptions.dualSenseVibrationGain
    }

    /// The two names in the menu, and they name the PATH rather than describe
    /// an outcome.
    ///
    /// "As the game asks" and "Stronger motors" were both true and both
    /// unhelpful. The first described where the choice came from, which stopped
    /// meaning anything once the driver had a default of its own; the second
    /// promised a result, and a promise about how hard a pad feels is a thing a
    /// menu cannot keep. "Modern" and "Legacy" are what the two are: the pad's
    /// own haptic path, and the rotating-mass motors it imitates for software
    /// that predates it. Somebody who tries both knows within a second which
    /// one they want, and neither name has told them what to expect.
    ///
    /// THE RAW VALUES DO NOT MOVE. "as-asked" and "stronger" are in every saved
    /// record on every machine, and a rename that silently reset those would
    /// turn somebody's chosen path back to the default behind their back --
    /// which is the whole reason `pickable` folds the two dead entries instead
    /// of dropping them. The case names follow the raw values for the same
    /// reason, so what is stored and what is written here stay legible as one
    /// thing.
    var label: String {
        switch self {
        case .asAsked: return "Modern"
        case .stronger: return "Legacy"
        }
    }

    /// The list the menu shows, in the order it is declared.
    static var dropdownOptions: DropdownOptions {
        allCases.map { (id: $0.rawValue, label: $0.label) }
    }

    /// A stored value the menu cannot show is not a choice, it is a leftover
    /// -- `DualSensePresentation.pickable`'s rule, for the same reason.
    static func pickable(_ raw: String?) -> String {
        // Two entries have been folded away rather than dropped, because a
        // record that names one must not read as the default and turn a
        // person's setting back on behind their back. "off" was a fourth
        // entry for one afternoon and became a strength of zero; "custom" was
        // the haptic path with a strength, and the strength moved out of the
        // choice on 2026-09-10.
        if raw == "off" || raw == "custom" { return DualSenseVibration.asAsked.rawValue }
        guard let raw, let known = DualSenseVibration(rawValue: raw) else { return byDefault.rawValue }
        return known.rawValue
    }

    /// The same for the percentage: a number the slider cannot reach is folded
    /// into the range rather than shown as a slider pinned off its own scale
    /// while the launch writes something else.
    static func pickableGain(_ raw: Double?) -> Double {
        guard let raw, raw.isFinite else { return Double(neutralGain) }
        return min(max(raw, gainRange.lowerBound), gainRange.upperBound)
    }
}

/// The colour of a DualSense's lightbar for one title, as MacGameVideoFix's
/// mgvf-0031 winebus reads it.
///
/// A namespace and not an enum, because the stored value is a colour rather
/// than a list: "as-asked", or exactly six lowercase hex digits. The menu
/// offers presets, since a colour panel is a window a gamepad cannot reach,
/// but a record holding any other valid colour -- written by hand, or by a
/// later build with a picker -- is shown and kept rather than folded away.
///
/// WHAT THE ENGINE DOES WITH IT, and nothing more is claimed here. The driver
/// replaces the colour inside a light change the game or Steam Input writes to
/// the pad itself, only where that writer set the lightbar's enable bit. Its
/// one packet of its own is on Bluetooth, with a colour set: a release-only
/// report just before the first client lightbar packet after the pad arrives
/// (LightbarRelease, whose default this application never changes). Nothing
/// else of its own is sent while the game runs. A title and a Steam setup
/// that never write a light change get nothing from this in this phase.
/// Whether a paired pad needs that release is not measured yet.
nonisolated enum DualSenseLightbar {

    /// The pad's lights as the game or Steam asks. Written as 0, which the
    /// driver reads as "change nothing".
    static let asAsked = "as-asked"

    /// What the menu offers, in the order it offers them. "Off" is a colour
    /// like any other -- black -- and that is why the registry value carries a
    /// marker byte: 000000 has to stay distinguishable from nothing asked.
    static let presets: [(id: String, label: String)] = [
        ("000000", "Off"),
        ("ffffff", "White"),
        ("ff0000", "Red"),
        ("ff8000", "Orange"),
        ("ffff00", "Yellow"),
        ("00ff00", "Green"),
        ("00ffff", "Cyan"),
        ("0000ff", "Blue"),
        ("8000ff", "Purple"),
        ("ff40a0", "Pink"),
    ]

    /// Six hex digits, trimmed, lowercased, with an optional leading '#', or
    /// the default. Anything else is a leftover, not a choice -- the rule every
    /// other pad option here follows.
    static func pickable(_ raw: String?) -> String {
        guard let raw else { return asAsked }
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return asAsked }
        return hex
    }

    /// The list the menu shows: the default, the presets, and every colour no
    /// preset names among the one the panel opened on and the one on screen,
    /// each as one more entry at the end. The opened one stays listed after
    /// the form moves off it, so a step or a pick away from a hand-written
    /// colour is not a step it cannot come back from for the rest of the visit.
    static func dropdownOptions(current: String, opened: String? = nil) -> DropdownOptions {
        var options: DropdownOptions = [(id: asAsked, label: "As the game asks")] + presets
        for raw in [opened, current].compactMap({ $0 }) {
            let folded = pickable(raw)
            if folded != asAsked, !options.contains(where: { $0.id == folded }) {
                options.append((id: folded, label: "Custom #\(folded)"))
            }
        }
        return options
    }

    /// What a pad press sideways does. Cycles over the list the menu shows,
    /// so a custom colour is a stop of its own rather than something
    /// `OptionAdjust.cycle` does not find and replaces with the first entry.
    static func cycle(_ current: String, opened: String? = nil, forward: Bool) -> String {
        OptionAdjust.cycle(pickable(current), in: dropdownOptions(current: current, opened: opened).map(\.id),
                           forward: forward)
    }

    /// What goes into "LightbarColour": 0 for the default, 0x01RRGGBB for a
    /// colour. The driver acts only on the 0x01 marker, so 0 and every other
    /// shape leave the pad's lights as the client writes them.
    static func registryValue(_ raw: String) -> UInt32 {
        let folded = pickable(raw)
        guard folded != asAsked, let rgb = UInt32(folded, radix: 16) else { return 0 }
        return 0x0100_0000 | rgb
    }

    /// The colour as the console names it.
    static func label(_ raw: String) -> String {
        let folded = pickable(raw)
        if folded == asAsked { return "as the game asks" }
        if let preset = presets.first(where: { $0.id == folded }) { return "\(preset.label.lowercased()) (#\(folded))" }
        return "#\(folded)"
    }
}

/// The small white lights under a DualSense's touchpad, for one title.
///
/// A Windows game using XInput never tells the pad which player it is -- the
/// slot stays inside xinput, below which nothing can see it -- so the number
/// here is the person's choice and not the game's. The driver replaces the
/// pattern only in a light change a client writes with the player-lights
/// enable bit set, and keeps that client's own "instant" bit.
nonisolated enum DualSensePlayerLights: String, CaseIterable {

    case asAsked = "as-asked"
    case off = "off"
    case player1 = "player-1"
    case player2 = "player-2"
    case player3 = "player-3"
    case player4 = "player-4"

    static let byDefault = DualSensePlayerLights.asAsked

    /// What goes into "PlayerLights": 0 for the default, 0x100 | pattern
    /// otherwise. The patterns are the ones Sony's own layout uses: the centre
    /// light alone for player 1, then two, three and four lights.
    var registryValue: UInt32 {
        switch self {
        case .asAsked: return 0
        case .off: return 0x100
        case .player1: return 0x104
        case .player2: return 0x10A
        case .player3: return 0x115
        case .player4: return 0x11B
        }
    }

    /// Raw values never move when these do -- `DualSenseVibration.label`'s rule.
    var label: String {
        switch self {
        case .asAsked: return "As the game asks"
        case .off: return "Off"
        case .player1: return "Player 1"
        case .player2: return "Player 2"
        case .player3: return "Player 3"
        case .player4: return "Player 4"
        }
    }

    static var dropdownOptions: DropdownOptions {
        allCases.map { (id: $0.rawValue, label: $0.label) }
    }

    static func pickable(_ raw: String?) -> String {
        guard let raw, let known = DualSensePlayerLights(rawValue: raw) else { return byDefault.rawValue }
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
/// that -- and the two mgvf-0009 added, `VibrationMode` and `VibrationGain`,
/// which say what its motors should do; see `DualSenseVibration`. Those four
/// are read later than `Hidraw`: as the device arrives, on the bus thread,
/// rather than at driver start. It comes to the same thing for anyone waiting
/// for them to take effect, since a bottle booting is when both happen, but it
/// is why the honest answer to "when does this apply" is the pad's next
/// arrival and not the next launch.
nonisolated enum DualSenseRoute {

    static let devicesPath = "System\\\\CurrentControlSet\\\\Services\\\\winebus\\\\Devices"

    /// The eight value names winebus reads under a device's key, spelled once.
    /// Spelling one of them differently writes a value nothing ever reads, and
    /// the bottle looks configured.
    static let hidrawValue = "Hidraw"
    static let usbEmulationValue = "UsbEmulation"
    static let productIDValue = "ProductId"
    static let vibrationModeValue = "VibrationMode"
    static let vibrationGainValue = "VibrationGain"
    static let xinputRumbleValue = "XInputRumble"
    /// mgvf-0031's two, read under the pad's real product id.
    static let lightbarColourValue = "LightbarColour"
    static let playerLightsValue = "PlayerLights"

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
        /// What goes into "VibrationMode": 1 asks mgvf-0009 to rewrite a
        /// packet that chose the haptic path so that it chooses the legacy
        /// motors, 0 leaves every packet as the game wrote it.
        let vibrationMode: UInt32
        /// What goes into "VibrationGain": a percentage over the two motor
        /// bytes. 100 is the value that changes nothing, which is why it and
        /// not 0 is the default here -- 0 is silence, and the driver reads
        /// the two differently on purpose.
        let vibrationGain: UInt32
        /// What goes into "XInputRumble": 1 asks mgvf-0010 to offer the pad's
        /// motors to XInput, as a small device of their own beside the pad. 0
        /// leaves the pad exactly as it was, which is what every title gets
        /// unless it asks otherwise.
        let xinputRumble: UInt32
        /// What goes into "LightbarColour": 0 leaves the lights to the client,
        /// 0x01RRGGBB asks mgvf-0031 to put that colour in the client's own
        /// light changes. Written as 0 rather than removed, like the six above.
        let lightbarColour: UInt32
        /// What goes into "PlayerLights": 0 leaves them to the client,
        /// 0x100 | pattern asks for that pattern.
        let playerLights: UInt32

        /// Defaulted so that a caller who only cares about the route -- which
        /// is what this type meant before mgvf-0005 -- still reads the same.
        init(path: String, hidraw: UInt32, usbEmulation: UInt32 = 0, askedProductID: UInt32 = 0,
             vibrationMode: UInt32 = 0, vibrationGain: UInt32 = DualSenseVibration.neutralGain,
             xinputRumble: UInt32 = 0, lightbarColour: UInt32 = 0, playerLights: UInt32 = 0) {
            self.path = path
            self.xinputRumble = xinputRumble
            self.hidraw = hidraw
            self.usbEmulation = usbEmulation
            self.askedProductID = askedProductID
            self.vibrationMode = vibrationMode
            self.vibrationGain = vibrationGain
            self.lightbarColour = lightbarColour
            self.playerLights = playerLights
        }

        /// Every value this override writes, in the order it writes them.
        var values: [(key: String, value: UInt32)] {
            [(DualSenseRoute.hidrawValue, hidraw),
             (DualSenseRoute.usbEmulationValue, usbEmulation),
             (DualSenseRoute.productIDValue, askedProductID),
             (DualSenseRoute.vibrationModeValue, vibrationMode),
             (DualSenseRoute.vibrationGainValue, vibrationGain),
             (DualSenseRoute.xinputRumbleValue, xinputRumble),
             (DualSenseRoute.lightbarColourValue, lightbarColour),
             (DualSenseRoute.playerLightsValue, playerLights)]
        }
    }

    static func sectionPath(productID: Int) -> String {
        devicesPath + "\\\\" + String(format: "%04x/%04x", SonyPads.vendorID, productID)
    }

    /// Puts one override into a loaded registry: finds or creates its section
    /// and sets every value it carries. Returns the values that changed, in
    /// order, so the caller logs them and saves only when the list is not
    /// empty. No file is touched here -- the launch saves -- which is what
    /// lets a test apply it to a fixture and list every value that results.
    @discardableResult
    static func write(_ override: Override, into registry: WineRegistryFile,
                      timestamp: Int = Int(Date().timeIntervalSince1970)) -> [(key: String, value: UInt32)] {
        let section: WineRegSection
        if let existing = registry.section(forPath: override.path) {
            section = existing
        } else {
            section = WineRegSection(header: "[\(override.path)] \(timestamp)")
            registry.sections.append(section)
        }
        var changed: [(key: String, value: UInt32)] = []
        for (key, value) in override.values {
            // The call is the write; kept out of a `where` clause so that what
            // changes the bottle is on a line of its own.
            if section.addOrSetDword(forKey: key, value: value) {
                changed.append((key, value))
            }
        }
        return changed
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
    /// driver refuses the PRESENTATION by itself for anything that is not a
    /// hidraw device on BUS_TYPE_BLUETOOTH (mgvf-0005
    /// dualsense_usb_emulation_fixups), so a presentation written for a pad on
    /// a cable is read and dropped there.
    ///
    /// That used to be true of the two vibration values as well, and mgvf-0016
    /// is why it no longer is: they are read on either transport now, and a pad
    /// on a cable is rewritten like any other. It changes nothing here -- the
    /// values were always written for both models -- but the reason above is
    /// only half a reason now, and half a reason in a comment is how the next
    /// person gets it wrong.
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
    ///
    /// The two vibration values ride in the same entries and under the same
    /// rules, with one difference worth saying out loud: their "nothing asked
    /// for" pair is 0 and 100, not 0 and 0. A `VibrationGain` of 0 is a
    /// request -- silence -- and writing it where the title asked for nothing
    /// would quietly take the rumble away from every game. They are gated on
    /// the raw route for the reason the emulation is: the rewrite happens on
    /// output reports winebus itself sends to the pad, and a pad handed to SDL
    /// is a wine gamepad whose reports winebus never sees.
    static func overrides(for pads: [SonyPads.Pad], sdlEnabled: Bool, engineTellsTheBus: Bool,
                          presentation: DualSensePresentation = .byDefault,
                          engineCanEmulateUSB: Bool = false,
                          vibration: DualSenseVibration = .byDefault,
                          vibrationPercent: Double = Double(DualSenseVibration.neutralGain),
                          engineCanRewriteVibration: Bool = false,
                          xinputRumble: Bool = false,
                          engineCanXInputRumble: Bool = false,
                          lightbar: String = DualSenseLightbar.asAsked,
                          playerLights: DualSensePlayerLights = .byDefault,
                          engineCanSetLights: Bool = false) -> [Override] {
        SonyPads.models.map { model in
            let onBluetooth = pads.contains { $0.productID == model && $0.isBluetooth }
            let viaSDL = onBluetooth && sdlEnabled && !engineTellsTheBus
            let emulating = presentation.presentsAsWired && engineCanEmulateUSB && !viaSDL
            let rewriting = vibration.changesAnything(percent: vibrationPercent)
                && engineCanRewriteVibration && !viaSDL
            // Asked for, the engine can do it, and the pad is not being sent
            // through SDL -- where the pad's own descriptor is thrown away and
            // there is nothing for mgvf-0010 to add a collection to.
            let rumblingThroughXInput = xinputRumble && engineCanXInputRumble && !viaSDL
            // The lights, under the motors' rule: the rewrite is of packets
            // winebus itself sends to the pad, and a pad handed to SDL is one
            // it never sends any to. Neutral is 0 for both.
            let lighting = engineCanSetLights && !viaSDL
            return Override(path: sectionPath(productID: model),
                            hidraw: viaSDL ? 0 : 1,
                            usbEmulation: emulating ? 1 : 0,
                            askedProductID: emulating ? presentation.productIDValue(for: model) : 0,
                            vibrationMode: rewriting ? vibration.modeValue : 0,
                            vibrationGain: rewriting ? vibration.gainValue(percent: vibrationPercent)
                                                     : DualSenseVibration.neutralGain,
                            xinputRumble: rumblingThroughXInput ? 1 : 0,
                            lightbarColour: lighting ? DualSenseLightbar.registryValue(lightbar) : 0,
                            playerLights: lighting ? playerLights.registryValue : 0)
        }
    }

    /// What the engine's winebus answers to every question the launch asks of
    /// it, read once per launch from the binary.
    struct EngineAnswers: Equatable {
        var tellsTheBus = false
        var canEmulateUSB = false
        var canRewriteVibration = false
        var canXInputRumble = false
        var canSetLights = false

        static func of(cxAppPath: String?) -> EngineAnswers {
            EngineAnswers(tellsTheBus: engineTellsTheBus(cxAppPath: cxAppPath),
                          canEmulateUSB: engineCanEmulateUSB(cxAppPath: cxAppPath),
                          canRewriteVibration: engineCanRewriteVibration(cxAppPath: cxAppPath),
                          canXInputRumble: engineCanXInputRumble(cxAppPath: cxAppPath),
                          canSetLights: engineCanSetLights(cxAppPath: cxAppPath))
        }
    }

    /// What a launch says and writes for a title's saved options, the pads
    /// attached and the engine's answers. One place builds both, from one
    /// reading of the options, so the console can never describe a choice the
    /// registry does not get or the other way round.
    @MainActor
    static func launchPlan(options: GameOptions, pads: [SonyPads.Pad],
                           engine: EngineAnswers) -> (summary: String?, overrides: [Override]) {
        let presentation = DualSensePresentation(rawValue: options.dualSensePresentation) ?? .byDefault
        let vibration = DualSenseVibration(rawValue: options.dualSenseVibration) ?? .byDefault
        // Each path keeps its own strength; the launch writes the one the
        // chosen path uses.
        let vibrationPercent = options[keyPath: vibration.gainKeyPath]
        let lightbar = DualSenseLightbar.pickable(options.dualSenseLightbar)
        let playerLights = DualSensePlayerLights(rawValue: options.dualSensePlayerLights) ?? .byDefault
        let summary = summary(for: pads, sdlEnabled: options.enableSDL, engineTellsTheBus: engine.tellsTheBus,
                              presentation: presentation, engineCanEmulateUSB: engine.canEmulateUSB,
                              vibration: vibration, vibrationPercent: vibrationPercent,
                              engineCanRewriteVibration: engine.canRewriteVibration,
                              lightbar: lightbar, playerLights: playerLights,
                              engineCanSetLights: engine.canSetLights)
        let overrides = overrides(for: pads, sdlEnabled: options.enableSDL, engineTellsTheBus: engine.tellsTheBus,
                                  presentation: presentation, engineCanEmulateUSB: engine.canEmulateUSB,
                                  vibration: vibration, vibrationPercent: vibrationPercent,
                                  engineCanRewriteVibration: engine.canRewriteVibration,
                                  xinputRumble: options.xinputRumble,
                                  engineCanXInputRumble: engine.canXInputRumble,
                                  lightbar: lightbar, playerLights: playerLights,
                                  engineCanSetLights: engine.canSetLights)
        return (summary, overrides)
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

    /// Whether the engine carries mgvf-0009: the winebus that can rewrite a
    /// DualSense's output reports. Asked exactly as mgvf-0005 is asked, of the
    /// same binary, for the same reason -- the names of the two values it
    /// reads are UTF-16 literals in the PE, and a winebus without the patch has
    /// no reason to contain either word.
    ///
    /// Both names are required and not one. They arrive together in one patch
    /// and a build with only one of them is not a build this project makes,
    /// but the question asked here is "can this engine do what the option
    /// promises", and the option promises both halves.
    ///
    /// It is the .sys that is read, and that is where the rewrite is: mgvf-0009
    /// puts both names and both entry points in winebus.sys, not in the unix
    /// half. The two halves are built from one source tree and installed
    /// together anyway, so reading the .sys keeps every one of these questions
    /// asked of one file.
    ///
    /// IT CANNOT TELL mgvf-0009 FROM mgvf-0009 PLUS mgvf-0016, and that is a
    /// choice rather than an oversight. mgvf-0016 gave the rewrite a pad on a
    /// cable and reuses the same two registry names, so the two builds are
    /// identical to this question; a third probe would need a marker of its
    /// own. It is not worth one. On every wired output report this project has
    /// captured -- 10,684 of them -- not one asks the motors for anything, so
    /// an engine that lacks mgvf-0016 and one that has it behave the same on
    /// every title measured so far. The day a wired title is found that does
    /// ask, the marker to look for is the ASCII name
    /// `dualsense_usb_native_set_output_report`, which mgvf-0016 puts in the
    /// binary as a debug string and which survives the strip.
    static func engineCanRewriteVibration(cxAppPath: String?) -> Bool {
        contains(literal: vibrationModeValue, inWinebusOf: cxAppPath)
            && contains(literal: vibrationGainValue, inWinebusOf: cxAppPath)
    }

    /// Whether the engine carries mgvf-0010: the winebus that can offer a pad's
    /// motors to XInput. Asked of the binary by the name of the registry value
    /// it reads, exactly as the two questions above are, and asked separately
    /// rather than inferred: one question, one measurement.
    ///
    /// It does not ask about hidclass.sys or the xinput DLLs that the same
    /// switch needs. They travel with this winebus and are installed by the
    /// same script; an engine with one and not the others is an engine somebody
    /// assembled by hand, and this application does not try to guess at that.
    static func engineCanXInputRumble(cxAppPath: String?) -> Bool {
        contains(literal: xinputRumbleValue, inWinebusOf: cxAppPath)
    }

    /// Whether the engine carries mgvf-0031: the winebus that can set the
    /// lights a title asks for. Both names are required, as both vibration
    /// names are: the option promises both rows.
    static func engineCanSetLights(cxAppPath: String?) -> Bool {
        contains(literal: lightbarColourValue, inWinebusOf: cxAppPath)
            && contains(literal: playerLightsValue, inWinebusOf: cxAppPath)
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
    ///
    /// The motors get one clause at the end rather than a word inside each
    /// pad's sentence: the choice is one per title, not one per pad, and it
    /// is written for both models the way everything else here is.
    static func summary(for pads: [SonyPads.Pad], sdlEnabled: Bool, engineTellsTheBus: Bool,
                        presentation: DualSensePresentation = .byDefault,
                        engineCanEmulateUSB: Bool = false,
                        vibration: DualSenseVibration = .byDefault,
                        vibrationPercent: Double = Double(DualSenseVibration.neutralGain),
                        engineCanRewriteVibration: Bool = false,
                        lightbar: String = DualSenseLightbar.asAsked,
                        playerLights: DualSensePlayerLights = .byDefault,
                        engineCanSetLights: Bool = false) -> String? {
        let mine = pads.filter { SonyPads.models.contains($0.productID) }
        // Written the way overrides(for:) writes it: a pad that this same
        // list hands to SDL is one winebus never sends an output report to,
        // so the rewrite is neither asked for nor claimed for it. With nothing
        // attached the route written is the raw one, so there is nothing in
        // the way.
        let allOnSDL = !mine.isEmpty && mine.allSatisfy { $0.isBluetooth && sdlEnabled && !engineTellsTheBus }
        let motors = motorClause(vibration: vibration, percent: vibrationPercent,
                                 engineCanRewriteVibration: engineCanRewriteVibration,
                                 everyPadOnSDL: allOnSDL)
        let lights = lightsClause(lightbar: lightbar, playerLights: playerLights,
                                  engineCanSetLights: engineCanSetLights, everyPadOnSDL: allOnSDL)
        // The lights are read at the same moment as everything else here, so
        // a title that asks only for them earns the same warning.
        let rewriting = (motors != nil && engineCanRewriteVibration && !allOnSDL)
            || (lights != nil && engineCanSetLights && !allOnSDL)
        guard !mine.isEmpty else {
            // Nothing attached and nothing asked for is the case this stayed
            // quiet about before the option existed, and it stays quiet.
            guard presentation.presentsAsWired || motors != nil || lights != nil else { return nil }
            let head = !presentation.presentsAsWired
                ? "no DualSense attached: the choice is written for both models all the same, and winebus reads it as the pad arrives"
                : engineCanEmulateUSB
                ? "no DualSense attached: the choice is written for both models all the same, so a pad that arrives over Bluetooth afterwards is presented as wired -- winebus reads it as the pad arrives"
                : "no DualSense attached, and this engine's winebus has no USB emulation: install the controller set in Options"
            return [head, motors, lights].compactMap { $0 }.joined(separator: "; ")
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
        // The vibration values are read at the same moment as the other three,
        // so a title that only asks for the motors earns the same warning.
        let when = anythingPresented || rewriting
            ? "; it takes effect when the pad next arrives, so start with Steam closed or reconnect the pad"
            : anythingCleared
            ? "; asking for the pad as it is clears what the last title asked for, and that is read when the pad next arrives as well: a game started into a running Steam keeps whatever the bottle booted with"
            : ""
        return ([sentences.joined(separator: "; ")] + [motors, lights].compactMap { $0 }).joined(separator: "; ") + when
    }

    /// What the console says about the lights, or nil when the title asked for
    /// nothing. Like `motorClause` it never claims a change happened: the
    /// values are asked of winebus and read as the pad connects, and the
    /// driver only rewrites light changes a client sends.
    private static func lightsClause(lightbar: String, playerLights: DualSensePlayerLights,
                                     engineCanSetLights: Bool, everyPadOnSDL: Bool) -> String? {
        let bar = DualSenseLightbar.pickable(lightbar)
        guard bar != DualSenseLightbar.asAsked || playerLights != .asAsked else { return nil }
        guard engineCanSetLights else {
            return "the lights are not set: this engine's winebus has no lights option, install the controller set in Options"
        }
        guard !everyPadOnSDL else {
            return "the lights are not set: the pad goes through SDL, and winebus never sees the light changes it would rewrite"
        }
        let player = playerLights == .asAsked ? "as the game asks" : playerLights.label.lowercased()
        return "the lights: lightbar \(DualSenseLightbar.label(bar)), player lights \(player) -- asked of winebus, read as the pad connects"
    }

    /// What the console says about the motors, or nil when the title asked for
    /// nothing -- which is the default and has to stay silent.
    ///
    /// It never claims the rewrite happens. An engine whose winebus has no
    /// mgvf-0009 reads neither value, and this application writes the neutral
    /// pair there rather than a request, so the sentence says what is missing
    /// and where to get it instead of describing an effect nobody will feel.
    private static func motorClause(vibration: DualSenseVibration, percent: Double,
                                    engineCanRewriteVibration: Bool, everyPadOnSDL: Bool) -> String? {
        guard vibration.changesAnything(percent: percent) else { return nil }
        guard engineCanRewriteVibration else {
            return "the vibration setting is not applied: this engine's winebus has no vibration rewrite, install the controller set in Options"
        }
        guard !everyPadOnSDL else {
            return "the vibration setting is not applied: a pad handed to SDL is a wine gamepad, and winebus never sees the output reports it would rewrite"
        }
        let gain = vibration.gainValue(percent: percent)
        if gain == 0 { return "the motors are silenced for this title, whatever the game asks for" }
        let strength = DualSenseVibration.strengthWord(percent)
        switch vibration {
        case .stronger:
            // The comparison behind this sentence: both paths driven to 252 of
            // 255 over Bluetooth on 2026-09-10 with only the two selecting bits
            // different, and the legacy one was clearly harder to the hand
            // holding it. That is still one hand -- but it is one hand on two
            // packets that differ in two bits, which the six-pulse ladder this
            // sentence used to cite was not.
            return "the motors: the legacy compatible motors, \(strength) -- coarser than the pad's own path and harder at the same command"
        case .asAsked:
            // The saturation is still worth a clause: somebody at the top of
            // the bar who feels nothing new should read why here rather than
            // conclude the option is broken. Measured on the title traced here,
            // whose loudest request is 143 of 255: everything it asks saturates
            // past about six times, and the bar now stops at four for that
            // reason.
            return gain == DualSenseVibration.neutralGain
                ? "the motors: whatever the game asks for, on the path it chose, untouched"
                : "the motors: the pad's own haptic path, \(strength) -- finer than the legacy motors, and it saturates, so near the top of the bar nothing more reaches them"
        }
    }
}
