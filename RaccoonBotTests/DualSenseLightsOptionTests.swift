//
//  DualSenseLightsOptionTests.swift
//  RaccoonBotTests
//
//  The lightbar colour and player lights asked of mgvf-0031, per title.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct DualSenseLightsOptionTests {

    private func pad(_ pid: Int, _ transport: String) -> SonyPads.Pad { .init(productID: pid, transport: transport) }

    private func overrides(_ pads: [SonyPads.Pad] = [], lightbar: String = DualSenseLightbar.asAsked,
                           player: DualSensePlayerLights = .byDefault, canSetLights: Bool = true,
                           sdl: Bool = true, tells: Bool = true) -> [DualSenseRoute.Override] {
        DualSenseRoute.overrides(for: pads, sdlEnabled: sdl, engineTellsTheBus: tells,
                                 lightbar: lightbar, playerLights: player, engineCanSetLights: canSetLights)
    }

    private func said(_ pads: [SonyPads.Pad], lightbar: String = DualSenseLightbar.asAsked,
                      player: DualSensePlayerLights = .byDefault, canSetLights: Bool = true,
                      sdl: Bool = true, tells: Bool = true) -> String? {
        DualSenseRoute.summary(for: pads, sdlEnabled: sdl, engineTellsTheBus: tells,
                               lightbar: lightbar, playerLights: player, engineCanSetLights: canSetLights)
    }

    // MARK: the values

    /// The decoding mgvf-0031 applies, from this side: 0 is nothing asked, a
    /// colour carries the 0x01 marker so black stays a choice, and the player
    /// lights carry 0x100 so "off" stays one.
    @Test func theValuesAreTheOnesTheDriverDecodes() {
        #expect(DualSenseLightbar.registryValue(DualSenseLightbar.asAsked) == 0)
        #expect(DualSenseLightbar.registryValue("ff0000") == 0x01FF_0000)
        #expect(DualSenseLightbar.registryValue("000000") == 0x0100_0000, "Off is black, and black is a colour")
        #expect(DualSenseLightbar.registryValue("not a colour") == 0)
        #expect(DualSensePlayerLights.asAsked.registryValue == 0)
        #expect(DualSensePlayerLights.off.registryValue == 0x100)
        #expect(DualSensePlayerLights.player1.registryValue == 0x104)
        #expect(DualSensePlayerLights.player2.registryValue == 0x10A)
        #expect(DualSensePlayerLights.player3.registryValue == 0x115)
        #expect(DualSensePlayerLights.player4.registryValue == 0x11B)
        // Every non-default value has the marker the driver requires and a
        // pattern inside the five bits it keeps.
        for choice in DualSensePlayerLights.allCases where choice != .asAsked {
            #expect(choice.registryValue & 0xFFFF_FF00 == 0x100 && choice.registryValue & 0xE0 == 0, "\(choice)")
        }
        for preset in DualSenseLightbar.presets {
            #expect(DualSenseLightbar.registryValue(preset.id) & 0xFF00_0000 == 0x0100_0000, "\(preset.label)")
        }
    }

    @Test func thePresetsAreTheDecidedOnes() {
        #expect(DualSenseLightbar.presets.map(\.id)
                == ["000000", "ffffff", "ff0000", "ff8000", "ffff00", "00ff00", "00ffff", "0000ff", "8000ff", "ff40a0"])
        #expect(DualSenseLightbar.presets.map(\.label)
                == ["Off", "White", "Red", "Orange", "Yellow", "Green", "Cyan", "Blue", "Purple", "Pink"])
        #expect(DualSensePlayerLights.allCases.map(\.rawValue)
                == ["as-asked", "off", "player-1", "player-2", "player-3", "player-4"])
    }

    @Test func pickableFoldsWhatIsNotAColour() {
        #expect(DualSenseLightbar.pickable("FF0000") == "ff0000")
        #expect(DualSenseLightbar.pickable("#ff0000") == "ff0000")
        #expect(DualSenseLightbar.pickable(" 12ab9f ") == "12ab9f")
        for leftover in ["zz0000", "", "ff00", "ff00000", "as-asked", "red"] {
            #expect(DualSenseLightbar.pickable(leftover) == DualSenseLightbar.asAsked, "\(leftover)")
        }
        #expect(DualSenseLightbar.pickable(nil) == DualSenseLightbar.asAsked)
        #expect(DualSensePlayerLights.pickable("player-9") == "as-asked")
        #expect(DualSensePlayerLights.pickable(nil) == "as-asked")
        #expect(DualSensePlayerLights.pickable("off") == "off")
    }

    // MARK: what is written

    @Test func theDefaultWritesTheNeutralZeroOnBothModels() {
        let o = overrides()
        #expect(o.count == SonyPads.models.count)
        #expect(o.allSatisfy { $0.lightbarColour == 0 && $0.playerLights == 0 })
    }

    @Test func aChoiceIsWrittenForBothModels() {
        #expect(overrides(lightbar: "ff0000").allSatisfy { $0.lightbarColour == 0x01FF_0000 && $0.playerLights == 0 })
        #expect(overrides(lightbar: "000000").allSatisfy { $0.lightbarColour == 0x0100_0000 })
        #expect(overrides(player: .player1).allSatisfy { $0.playerLights == 0x104 && $0.lightbarColour == 0 })
        #expect(overrides(player: .off).allSatisfy { $0.playerLights == 0x100 })
        #expect(overrides(player: .player4).allSatisfy { $0.playerLights == 0x11B })
        #expect(overrides([pad(SonyPads.dualSenseEdge, "USB")], lightbar: "ff0000").count == 2)
    }

    @Test func anEngineWithoutThePatchIsNeverAsked() {
        #expect(overrides(lightbar: "ff0000", player: .player2, canSetLights: false)
                    .allSatisfy { $0.lightbarColour == 0 && $0.playerLights == 0 })
    }

    /// The route is a fact about an attached pad: only the model on SDL is
    /// written neutral, and the other keeps the choice for when it arrives.
    @Test func theModelOnTheSDLRouteGetsZero() {
        let o = overrides([pad(SonyPads.dualSense, "Bluetooth")], lightbar: "ff0000", player: .player2,
                          sdl: true, tells: false)
        let onSDL = o.first { $0.path == DualSenseRoute.sectionPath(productID: SonyPads.dualSense) }
        let absent = o.first { $0.path == DualSenseRoute.sectionPath(productID: SonyPads.dualSenseEdge) }
        #expect(onSDL?.hidraw == 0)
        #expect(onSDL?.lightbarColour == 0 && onSDL?.playerLights == 0)
        #expect(absent?.lightbarColour == 0x01FF_0000 && absent?.playerLights == 0x10A)
    }

    /// Over everything that can be true at once: a value is only ever written
    /// under a raw route on an engine that reads it, and only in the shapes the
    /// driver decodes.
    @Test func noCombinationWritesALightTheDriverCannotHonour() {
        let arrangements: [[SonyPads.Pad]] = [[], [pad(SonyPads.dualSense, "Bluetooth")],
                                              [pad(SonyPads.dualSenseEdge, "Bluetooth")],
                                              [pad(SonyPads.dualSenseEdge, "USB")],
                                              [pad(SonyPads.dualSense, "Bluetooth"), pad(SonyPads.dualSenseEdge, "USB")]]
        let bars = [DualSenseLightbar.asAsked, "000000", "ff0000", "123456", "garbage"]
        for pads in arrangements {
            for bar in bars {
                for player in DualSensePlayerLights.allCases {
                    for sdl in [true, false] {
                        for tells in [true, false] {
                            for can in [true, false] {
                                let o = overrides(pads, lightbar: bar, player: player, canSetLights: can, sdl: sdl, tells: tells)
                                let why: Comment = "\(pads.map(\.transport)) \(bar) \(player) sdl \(sdl) tells \(tells) can \(can)"
                                #expect(o.count == 2, why)
                                #expect(o.allSatisfy { can || ($0.lightbarColour == 0 && $0.playerLights == 0) }, why)
                                #expect(o.allSatisfy { $0.hidraw == 1 || ($0.lightbarColour == 0 && $0.playerLights == 0) }, why)
                                #expect(o.allSatisfy { $0.lightbarColour == 0 || $0.lightbarColour & 0xFF00_0000 == 0x0100_0000 }, why)
                                #expect(o.allSatisfy { $0.playerLights == 0 || $0.playerLights & 0xFFFF_FF00 == 0x100 }, why)
                                #expect(o.allSatisfy { $0.lightbarColour == 0 || DualSenseLightbar.pickable(bar) != DualSenseLightbar.asAsked }, why)
                                #expect(o.allSatisfy { $0.playerLights == 0 || player != .asAsked }, why)
                                // And the positive half: wherever the driver can
                                // honour the choice, exactly the choice is written.
                                // Code that always wrote 0 fails here.
                                for override in o where can && override.hidraw == 1 {
                                    #expect(override.lightbarColour == DualSenseLightbar.registryValue(bar), why)
                                    #expect(override.playerLights == player.registryValue, why)
                                }
                                #expect(o.contains { $0.hidraw == 1 } || pads.contains { $0.isBluetooth }, why)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: the registry, listed from the disk

    private static let winebus = "System\\\\CurrentControlSet\\\\Services\\\\winebus"

    /// A bottle with a hand-set leftover under the plain pad's key and an
    /// unrelated value beside it, and no key at all for the Edge.
    private static let fixture = """
    WINE REGISTRY Version 2
    ;; All keys relative to \\\\Machine

    [System\\\\CurrentControlSet\\\\Services\\\\winebus] 1787673440
    #time=1dc0000000000001
    "DisableHidraw"=dword:00000000
    "Enable SDL"=dword:00000001

    [System\\\\CurrentControlSet\\\\Services\\\\winebus\\\\Devices\\\\054c/0ce6] 1787673441
    #time=1dc0000000000002
    "Hidraw"=dword:00000001
    "LightbarColour"=dword:01ff0000
    "SomethingElse"=dword:00000007

    """

    private func line(_ key: String, _ value: UInt32) -> String {
        "\"\(key)\"=dword:\(String(format: "%08x", value))"
    }

    /// Applies the overrides to a copy of the fixture, saves it, reads it back
    /// from the disk, and returns every value line of every section by path --
    /// not only the two new keys.
    private func disk(after o: [DualSenseRoute.Override]) throws -> (sections: [String: [String]], order: [String],
                                                                    changedOnSecondPass: Int) {
        let f = FileManager.default
        let url = f.temporaryDirectory.appendingPathComponent("lights-\(UUID().uuidString).reg")
        try Self.fixture.write(to: url, atomically: true, encoding: .utf8)
        defer {
            try? f.removeItem(at: url)
            try? f.removeItem(at: url.appendingPathExtension("orig"))
            try? f.removeItem(at: url.appendingPathExtension("procyon-backup"))
        }
        let registry = WineRegistryFile(fileURL: url)
        try registry.load()
        for override in o { DualSenseRoute.write(override, into: registry, timestamp: 1_800_000_000) }
        try registry.save()

        let reread = WineRegistryFile(fileURL: url)
        try reread.load()
        var sections: [String: [String]] = [:]
        for section in reread.sections { sections[section.path] = section.values.map(\.value.rawLine) }
        let again = o.reduce(0) { $0 + DualSenseRoute.write($1, into: reread, timestamp: 1_800_000_001).count }
        return (sections, reread.sections.map(\.path), again)
    }

    /// What both Devices keys must hold, value by value. The plain pad's key
    /// keeps its own order and its unrelated value; the Edge's is created with
    /// the eight in the order the launch writes them.
    private func expected(hidraw: (UInt32, UInt32) = (1, 1), bar: (UInt32, UInt32), player: (UInt32, UInt32))
        -> [String: [String]] {
        [
            Self.winebus: ["\"DisableHidraw\"=dword:00000000", "\"Enable SDL\"=dword:00000001"],
            DualSenseRoute.sectionPath(productID: SonyPads.dualSense): [
                line("Hidraw", hidraw.0), line("LightbarColour", bar.0), "\"SomethingElse\"=dword:00000007",
                line("UsbEmulation", 0), line("ProductId", 0), line("VibrationMode", 0),
                line("VibrationGain", 100), line("XInputRumble", 0), line("PlayerLights", player.0),
                line("IdlePowerOffMinutes", 0),
            ],
            DualSenseRoute.sectionPath(productID: SonyPads.dualSenseEdge): [
                line("Hidraw", hidraw.1), line("UsbEmulation", 0), line("ProductId", 0), line("VibrationMode", 0),
                line("VibrationGain", 100), line("XInputRumble", 0), line("LightbarColour", bar.1),
                line("PlayerLights", player.1), line("IdlePowerOffMinutes", 0),
            ],
        ]
    }

    private var paths: [String] {
        [Self.winebus, DualSenseRoute.sectionPath(productID: SonyPads.dualSense),
         DualSenseRoute.sectionPath(productID: SonyPads.dualSenseEdge)]
    }

    /// The default writes 0 over the hand-set leftover, which is the whole
    /// reason 0 is written rather than the value left alone.
    @Test func theDefaultOverwritesAHandSetLeftoverWithZero() throws {
        let result = try disk(after: overrides())
        #expect(result.order == paths)
        #expect(result.sections == expected(bar: (0, 0), player: (0, 0)))
        #expect(result.changedOnSecondPass == 0, "a second launch at the same choice writes nothing")
    }

    @Test func aColourAndAPlayerAreWrittenUnderBothKeys() throws {
        let result = try disk(after: overrides(lightbar: "ff0000", player: .player2))
        #expect(result.order == paths)
        #expect(result.sections == expected(bar: (0x01FF_0000, 0x01FF_0000), player: (0x10A, 0x10A)))
        #expect(result.changedOnSecondPass == 0)
    }

    @Test func theSDLRouteWritesZeroForTheAttachedModelOnly() throws {
        let result = try disk(after: overrides([pad(SonyPads.dualSense, "Bluetooth")], lightbar: "ff0000",
                                               player: .player2, sdl: true, tells: false))
        #expect(result.order == paths)
        #expect(result.sections == expected(hidraw: (0, 1), bar: (0, 0x01FF_0000), player: (0, 0x10A)))
        #expect(result.changedOnSecondPass == 0)
    }

    @Test func anEngineWithoutLightsGetsZeroUnderBothKeys() throws {
        let result = try disk(after: overrides(lightbar: "ff0000", player: .player2, canSetLights: false))
        #expect(result.order == paths)
        #expect(result.sections == expected(bar: (0, 0), player: (0, 0)))
        #expect(result.changedOnSecondPass == 0)
    }

    // MARK: the console

    @Test func theDefaultSaysNothing() {
        #expect(said([]) == nil)
    }

    /// Lights alone, with no pad attached, still say something -- something is
    /// written -- and never that the change happened.
    @Test func theConsoleAsksAndNeverClaims() {
        let alone = said([], lightbar: "ff0000", player: .player1) ?? ""
        #expect(alone.contains("no DualSense attached"))
        #expect(alone.contains("asked of winebus, read as the pad connects"))
        #expect(alone.contains("red (#ff0000)"))
        #expect(alone.contains("player 1"))
        let attached = said([pad(SonyPads.dualSense, "Bluetooth")], player: .off) ?? ""
        #expect(attached.contains("asked of winebus, read as the pad connects"))
        #expect(attached.contains("when the pad next arrives"), "lights alone earn the arrival warning")
        #expect(attached.contains("lightbar as the game asks"))
        for sentence in [alone, attached] {
            #expect(!sentence.contains("set by the engine"))
        }
    }

    @Test func theConsoleSaysWhyTheLightsAreNotSet() {
        #expect(said([pad(SonyPads.dualSense, "USB")], lightbar: "ff0000", canSetLights: false)?
                    .contains("no lights option") == true)
        #expect(said([pad(SonyPads.dualSense, "Bluetooth")], lightbar: "ff0000", sdl: true, tells: false)?
                    .contains("goes through SDL") == true)
        #expect(said([pad(SonyPads.dualSense, "Bluetooth")], lightbar: "ff0000", sdl: true, tells: false)?
                    .contains("read as the pad connects") == false)
    }

    // MARK: the engine, from its own binary

    private func engine(winebus bytes: Data) throws -> URL {
        let f = FileManager.default
        let app = f.temporaryDirectory.appendingPathComponent("lights-\(UUID().uuidString).app", isDirectory: true)
        let dir = app.appendingPathComponent("Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows")
        try f.createDirectory(at: dir, withIntermediateDirectories: true)
        try bytes.write(to: dir.appendingPathComponent("winebus.sys"))
        return app
    }

    private func utf16(_ s: String) -> Data { Data(s.utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] }) }

    @Test func theLightsAreReadFromTheBinary() throws {
        #expect(DualSenseRoute.engineCanSetLights(cxAppPath: nil) == false)
        #expect(DualSenseRoute.engineCanSetLights(cxAppPath: "") == false)
        #expect(DualSenseRoute.engineCanSetLights(cxAppPath: "/nonexistent.app") == false)
        let f = FileManager.default
        let head = Data("MZ".utf8)
        let both = try engine(winebus: head + utf16("LightbarColour") + Data([0, 0]) + utf16("PlayerLights"))
        let one = try engine(winebus: head + utf16("LightbarColour"))
        let ascii = try engine(winebus: head + Data("LightbarColour PlayerLights".utf8))
        defer { for app in [both, one, ascii] { try? f.removeItem(at: app) } }
        #expect(DualSenseRoute.engineCanSetLights(cxAppPath: both.path(percentEncoded: false)))
        #expect(DualSenseRoute.engineCanSetLights(cxAppPath: one.path(percentEncoded: false)) == false, "both names or no")
        #expect(DualSenseRoute.engineCanSetLights(cxAppPath: ascii.path(percentEncoded: false)) == false,
                "the driver's names are wide literals")
    }

    /// Read only, and skipped where no engine is installed: a stock CrossOver
    /// has none of it, and lights never travel without the vibration rewrite.
    @Test func aRealEngineIsReadForTheLightsToo() {
        let f = FileManager.default
        let stock = "/Applications/CrossOver.app"
        let ours = f.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Crossover_MGVF.app").path(percentEncoded: false)
        let sys = "/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows/winebus.sys"
        if f.fileExists(atPath: stock + sys) {
            #expect(DualSenseRoute.engineCanSetLights(cxAppPath: stock) == false)
        }
        for engine in [stock, ours] where f.fileExists(atPath: engine + sys) {
            if DualSenseRoute.engineCanSetLights(cxAppPath: engine) {
                #expect(DualSenseRoute.engineCanRewriteVibration(cxAppPath: engine), "\(engine)")
            }
        }
    }

    /// The names are the patch's, read from the patch. Skipped only where the
    /// sibling checkout is absent; a checkout without the patch fails, because
    /// then the option writes names nothing reads.
    @Test func thePatchItselfNamesTheseValues() throws {
        let patches = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MacGameVideoFix/source-patches")
        let f = FileManager.default
        guard f.fileExists(atPath: patches.path(percentEncoded: false)) else { return }
        let file = patches.appendingPathComponent("mgvf-0031-winebus-the-lights-a-user-chose.patch")
        let text = try? String(contentsOf: file, encoding: .utf8)
        #expect(text != nil, "mgvf-0031 is not in \(patches.path(percentEncoded: false))")
        guard let text else { return }
        #expect(text.contains("L\"\(DualSenseRoute.lightbarColourValue)\""))
        #expect(text.contains("L\"\(DualSenseRoute.playerLightsValue)\""))
    }

    // MARK: the option on disk

    @Test func theChoiceSurvivesTheSavedRecord() {
        #expect(GameOptions().dualSenseLightbar == DualSenseLightbar.asAsked)
        #expect(GameOptions().dualSensePlayerLights == DualSensePlayerLights.asAsked.rawValue)
        let mine = GameOptions()
        mine.dualSenseLightbar = "ff40a0"
        mine.dualSensePlayerLights = DualSensePlayerLights.player3.rawValue
        let saved = GameOptionsData(data: mine)
        #expect(saved.dualSenseLightbar == "ff40a0")
        #expect(saved.dualSensePlayerLights == "player-3")
        let restored = GameOptions()
        restored.set(data: saved)
        #expect(restored.dualSenseLightbar == "ff40a0")
        #expect(restored.dualSensePlayerLights == "player-3")
    }

    @Test func aRecordFromBeforeTheOptionReadsAsTheDefault() throws {
        let old = try JSONDecoder().decode(GameOptionsData.self, from: Data(#"{"enableSDL": true}"#.utf8))
        #expect(old.dualSenseLightbar == nil)
        #expect(old.dualSensePlayerLights == nil)
        let form = GameOptions()
        form.dualSenseLightbar = "ff0000"
        form.dualSensePlayerLights = "player-1"
        form.set(data: old)
        #expect(form.dualSenseLightbar == DualSenseLightbar.asAsked)
        #expect(form.dualSensePlayerLights == DualSensePlayerLights.asAsked.rawValue)
    }

    /// A remote record that says nothing leaves the person's choice alone, and
    /// one that says something this build cannot show is folded.
    @Test func theMergePathKeepsAndFoldsTheChoice() {
        let form = GameOptions()
        form.dualSenseLightbar = "00ff00"
        form.dualSensePlayerLights = "player-4"
        var silent = GameOptionsData(data: GameOptions())
        silent.dualSenseLightbar = nil
        silent.dualSensePlayerLights = nil
        form.importAutoConfig(data: silent)
        #expect(form.dualSenseLightbar == "00ff00")
        #expect(form.dualSensePlayerLights == "player-4")

        var strange = silent
        strange.dualSenseLightbar = "#ABCDEF"
        strange.dualSensePlayerLights = "player-5"
        form.importAutoConfig(data: strange)
        #expect(form.dualSenseLightbar == "abcdef")
        #expect(form.dualSensePlayerLights == DualSensePlayerLights.asAsked.rawValue)
    }

    // MARK: the menu and the pad

    @Test func aCustomColourIsShownAndKept() {
        let options = DualSenseLightbar.dropdownOptions(current: "123abc")
        #expect(options.first?.id == DualSenseLightbar.asAsked)
        #expect(options.first?.label == "As the game asks")
        #expect(options.last?.id == "123abc")
        #expect(options.last?.label == "Custom #123abc")
        #expect(options.count == DualSenseLightbar.presets.count + 2)
        // A preset is not listed twice, and the default adds no custom entry.
        #expect(DualSenseLightbar.dropdownOptions(current: "ff0000").count == DualSenseLightbar.presets.count + 1)
        #expect(DualSenseLightbar.dropdownOptions(current: DualSenseLightbar.asAsked).count
                == DualSenseLightbar.presets.count + 1)
        #expect(DualSenseLightbar.dropdownOptions(current: "123abc").allSatisfy {
            DualSenseLightbar.pickable($0.id) == $0.id
        }, "every id the menu offers survives the fold the load applies")
        #expect(DualSensePlayerLights.dropdownOptions.allSatisfy { DualSensePlayerLights.pickable($0.id) == $0.id })

        // Survives the save and the load.
        let form = GameOptions()
        form.set(data: { var d = GameOptionsData(data: GameOptions()); d.dualSenseLightbar = "123abc"; return d }())
        #expect(form.dualSenseLightbar == "123abc")
        #expect(GameOptionsData(data: form).dualSenseLightbar == "123abc")

        // A menu opened with a pad and closed with a press on what it opened
        // on changes nothing.
        let menu = MenuFocus(control: .lightbar, options: DualSenseLightbar.dropdownOptions(current: form.dualSenseLightbar),
                             selected: form.dualSenseLightbar)
        #expect(menu.currentID == "123abc")
    }

    /// Sideways on the row cycles over the list the menu shows, so the custom
    /// colour is a stop of its own rather than something replaced by the
    /// first entry the moment the stick moves.
    @Test func cyclingWithAPadDoesNotLoseACustomColourSilently() {
        #expect(DualSenseLightbar.cycle("123abc", forward: false) == "ff40a0", "back from the custom entry lands on the last preset")
        #expect(DualSenseLightbar.cycle("123abc", forward: true) == DualSenseLightbar.asAsked, "and forward wraps to the default")
        #expect(DualSenseLightbar.cycle("ff40a0", forward: true) == DualSenseLightbar.asAsked, "no custom entry when none is saved")
        #expect(DualSenseLightbar.cycle(DualSenseLightbar.asAsked, forward: true) == "000000")
        #expect(DualSenseLightbar.cycle(DualSenseLightbar.asAsked, forward: false) == "ff40a0")
    }

    /// A step away from the colour the panel opened on is not final: it stays
    /// a stop, so walking the whole list in either direction comes back to it,
    /// and a pick from the menu can reach it too.
    @Test func aCustomColourTheRecordOpenedOnStaysAStopForTheVisit() {
        let opened = "123abc"
        let stops = DualSenseLightbar.presets.count + 2
        for forward in [true, false] {
            var value = opened
            var seen: [String] = []
            for _ in 0..<stops {
                value = DualSenseLightbar.cycle(value, opened: opened, forward: forward)
                seen.append(value)
            }
            #expect(value == opened, "a full lap \(forward ? "forward" : "back") returns to the custom colour")
            #expect(Set(seen).count == stops, "every stop visited once: \(seen)")
            #expect(seen.contains(DualSenseLightbar.asAsked))
        }
        // Off it, the menu still lists it once, last.
        let menu = DualSenseLightbar.dropdownOptions(current: "ff0000", opened: opened)
        #expect(menu.map(\.id) == [DualSenseLightbar.asAsked] + DualSenseLightbar.presets.map(\.id) + [opened])
        #expect(menu.last?.label == "Custom #123abc")
        // On it, not listed twice; opened at a preset or the default, nothing added.
        #expect(DualSenseLightbar.dropdownOptions(current: opened, opened: opened).count == stops)
        #expect(DualSenseLightbar.dropdownOptions(current: "ff0000", opened: "ff0000").count == stops - 1)
        #expect(DualSenseLightbar.dropdownOptions(current: "ff0000", opened: DualSenseLightbar.asAsked).count == stops - 1)
        #expect(DualSenseLightbar.dropdownOptions(current: "ff0000", opened: nil).count == stops - 1)
        // A record written by hand in another shape is folded the same way.
        #expect(DualSenseLightbar.dropdownOptions(current: "ff0000", opened: "#123ABC").last?.id == opened)
    }

    // MARK: the launch, from the saved options

    /// The Launcher's own assembly: what the console says and what the
    /// registry gets come from one reading of the form, so a choice cannot
    /// reach one and miss the other.
    @Test @MainActor func theLaunchPlanCarriesTheLightsIntoBothTheSentenceAndTheValues() {
        let form = GameOptions()
        form.dualSenseLightbar = "FF0000"
        form.dualSensePlayerLights = DualSensePlayerLights.player3.rawValue
        let engine = DualSenseRoute.EngineAnswers(tellsTheBus: true, canSetLights: true)
        let pads = [pad(SonyPads.dualSense, "Bluetooth")]

        let plan = DualSenseRoute.launchPlan(options: form, pads: pads, engine: engine)
        #expect(plan.overrides == overrides(pads, lightbar: "ff0000", player: .player3, canSetLights: true,
                                            sdl: form.enableSDL, tells: true))
        #expect(plan.overrides.count == 2)
        #expect(plan.overrides.allSatisfy { $0.lightbarColour == 0x01FF_0000 && $0.playerLights == 0x115 })
        #expect(plan.summary == said(pads, lightbar: "ff0000", player: .player3, canSetLights: true,
                                     sdl: form.enableSDL, tells: true))
        #expect(plan.summary?.contains("red (#ff0000)") == true)
        #expect(plan.summary?.contains("player 3") == true)

        // An engine without the patch: neither half claims or writes a light.
        let without = DualSenseRoute.launchPlan(options: form, pads: pads,
                                                engine: .init(tellsTheBus: true, canSetLights: false))
        #expect(without.overrides.allSatisfy { $0.lightbarColour == 0 && $0.playerLights == 0 })
        #expect(without.summary?.contains("no lights option") == true)

        // A leftover in the record is the default on both sides.
        form.dualSenseLightbar = "garbage"
        form.dualSensePlayerLights = "player-9"
        let leftover = DualSenseRoute.launchPlan(options: form, pads: [], engine: engine)
        #expect(leftover.overrides.allSatisfy { $0.lightbarColour == 0 && $0.playerLights == 0 })
        #expect(leftover.summary == said([], canSetLights: true, sdl: form.enableSDL, tells: true))
    }

    /// The other six values go through the same assembly, and at the default
    /// every one of the eight is the neutral value on both models.
    @Test @MainActor func theLaunchPlanAtTheDefaultWritesEveryNeutralValue() {
        let plan = DualSenseRoute.launchPlan(options: GameOptions(), pads: [],
                                             engine: .init(tellsTheBus: true, canEmulateUSB: true,
                                                           canRewriteVibration: true, canXInputRumble: true,
                                                           canSetLights: true))
        #expect(plan.overrides.map(\.path) == SonyPads.models.map { DualSenseRoute.sectionPath(productID: $0) })
        for override in plan.overrides {
            #expect(override.values.map(\.key) == [DualSenseRoute.hidrawValue, DualSenseRoute.usbEmulationValue,
                                                   DualSenseRoute.productIDValue, DualSenseRoute.vibrationModeValue,
                                                   DualSenseRoute.vibrationGainValue, DualSenseRoute.xinputRumbleValue,
                                                   DualSenseRoute.lightbarColourValue, DualSenseRoute.playerLightsValue,
                                                   DualSenseRoute.idlePowerOffMinutesValue])
            #expect(override.values.map(\.value) == [1, 0, 0, 0, UInt32(DualSenseVibration.neutralGain), 0, 0, 0, 0])
        }
        #expect(plan.summary == nil)
    }

    @Test func aPadCanReachBothRows() {
        let list = OptionFocus.visibleControls(for: OptionPanelState(isNative: false, vibrationGainShown: true))
        let at = { (control: OptionControl) in list.firstIndex(of: control) ?? -1 }
        #expect(at(.lightbar) >= 0 && at(.playerLights) >= 0)
        #expect(at(.padSeenAs) + 1 == at(.lightbar), "the pad's column: how it is seen, then how it looks")
        #expect(at(.lightbar) + 1 == at(.playerLights))
        #expect(at(.playerLights) + 1 == at(.hidTrace), "the trace closes the pad's column")
        #expect(at(.hidTrace) < at(.vibration), "and the vibration column is walked after it")
        #expect(OptionControl.lightbar.opensMenu)
        #expect(OptionControl.playerLights.opensMenu)
        #expect(!OptionControl.lightbar.isButton && !OptionControl.playerLights.isButton)
        #expect(!OptionFocus.visibleControls(for: OptionPanelState(isNative: true)).contains(.lightbar))
    }
}
