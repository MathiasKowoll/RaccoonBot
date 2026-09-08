//
//  DualSenseRouteTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Which way a DualSense goes through winebus, from how it is attached.
struct DualSenseRouteTests {

    private func pad(_ pid: Int, _ transport: String) -> SonyPads.Pad { .init(productID: pid, transport: transport) }
    private func hidraw(_ o: [DualSenseRoute.Override], _ pid: Int) -> UInt32? {
        o.first { $0.path == DualSenseRoute.sectionPath(productID: pid) }?.hidraw
    }

    /// The key winebus enumerates: Devices\<vid>/<pid>, lowercase hex, four
    /// digits each, doubled backslashes as the .reg file has them.
    @Test func theSectionIsTheOneWinebusReads() {
        #expect(DualSenseRoute.sectionPath(productID: 0x0DF2)
                == "System\\\\CurrentControlSet\\\\Services\\\\winebus\\\\Devices\\\\054c/0df2")
    }

    /// Measured: over Bluetooth the raw path never rumbles, the SDL one does.
    @Test func aBluetoothDualSenseGoesThroughSDL() {
        let o = DualSenseRoute.overrides(for: [pad(SonyPads.dualSenseEdge, "Bluetooth")], sdlEnabled: true, engineTellsTheBus: false)
        #expect(hidraw(o, SonyPads.dualSenseEdge) == 0)
        #expect(hidraw(o, SonyPads.dualSense) == 1, "the model that is not here stays raw")
    }

    /// Over USB the raw path works and keeps touchpad, gyro and triggers.
    @Test func aUSBDualSenseStaysRaw() {
        let o = DualSenseRoute.overrides(for: [pad(SonyPads.dualSense, "USB")], sdlEnabled: true, engineTellsTheBus: false)
        #expect(hidraw(o, SonyPads.dualSense) == 1)
    }

    /// Explicit state, always: with nothing attached both models are written
    /// raw, so a 0 left by an earlier Bluetooth session cannot linger.
    @Test func nothingAttachedWritesRawForBothModels() {
        let o = DualSenseRoute.overrides(for: [], sdlEnabled: true, engineTellsTheBus: false)
        #expect(o.count == 2)
        #expect(o.allSatisfy { $0.hidraw == 1 })
    }

    /// The override only stops the raw copy; it does not make the SDL one.
    /// With SDL off a Bluetooth pad would vanish, so it stays raw.
    @Test func withSDLOffTheOverrideIsNeverWritten() {
        let o = DualSenseRoute.overrides(for: [pad(SonyPads.dualSenseEdge, "Bluetooth")], sdlEnabled: false, engineTellsTheBus: false)
        #expect(hidraw(o, SonyPads.dualSenseEdge) == 1)
        #expect(DualSenseRoute.summary(for: [pad(SonyPads.dualSenseEdge, "Bluetooth")], sdlEnabled: false, engineTellsTheBus: false)?
                    .contains("turn Enable SDL on") == true)
    }

    /// Two of one model, one on each transport: the key cannot tell them
    /// apart, and the one that would otherwise be silent wins.
    @Test func bluetoothWinsWhenTheSameModelIsOnBoth() {
        let o = DualSenseRoute.overrides(for: [pad(SonyPads.dualSense, "USB"), pad(SonyPads.dualSense, "BluetoothLowEnergy")],
                                         sdlEnabled: true, engineTellsTheBus: false)
        #expect(hidraw(o, SonyPads.dualSense) == 0)
    }

    /// With MacGameVideoFix's controller-bus set in the engine, Steam learns
    /// the transport on the raw route and keeps every feature: no detour.
    @Test func anEngineThatTellsTheBusKeepsTheRawRoute() {
        let o = DualSenseRoute.overrides(for: [pad(SonyPads.dualSenseEdge, "Bluetooth")], sdlEnabled: true, engineTellsTheBus: true)
        #expect(hidraw(o, SonyPads.dualSenseEdge) == 1)
        #expect(DualSenseRoute.summary(for: [pad(SonyPads.dualSenseEdge, "Bluetooth")], sdlEnabled: true, engineTellsTheBus: true)?
                    .contains("tells Steam") == true)
    }

    /// The capability is read from the engine's own winebus.sys, and a missing
    /// engine reads as not having it.
    @Test func aMissingEngineDoesNotTellTheBus() {
        #expect(DualSenseRoute.engineTellsTheBus(cxAppPath: nil) == false)
        #expect(DualSenseRoute.engineTellsTheBus(cxAppPath: "/nonexistent.app") == false)
    }

    @Test func somebodyElsesPadIsNotMentioned() {
        #expect(DualSenseRoute.summary(for: [pad(0x05C4, "Bluetooth")], sdlEnabled: true, engineTellsTheBus: false) == nil)
    }

    // MARK: what the pad looks like, per game

    /// The matrix's shorthand. The engine that can emulate also tells the bus:
    /// one build carries both patches, and a Bluetooth pad on that engine stays
    /// raw, which is the only route the emulation exists on.
    private func over(_ pads: [SonyPads.Pad], _ presentation: DualSensePresentation,
                      sdl: Bool = true, tells: Bool = true, canEmulate: Bool = true) -> [DualSenseRoute.Override] {
        DualSenseRoute.overrides(for: pads, sdlEnabled: sdl, engineTellsTheBus: tells,
                                 presentation: presentation, engineCanEmulateUSB: canEmulate)
    }
    private func entry(_ o: [DualSenseRoute.Override], _ pid: Int) -> DualSenseRoute.Override? {
        o.first { $0.path == DualSenseRoute.sectionPath(productID: pid) }
    }
    private func said(_ pads: [SonyPads.Pad], _ presentation: DualSensePresentation,
                      sdl: Bool = true, tells: Bool = true, canEmulate: Bool = true) -> String {
        DualSenseRoute.summary(for: pads, sdlEnabled: sdl, engineTellsTheBus: tells,
                               presentation: presentation, engineCanEmulateUSB: canEmulate) ?? ""
    }

    /// The two names mgvf-0005 reads, and the one mgvf-0002 does. A value
    /// spelled differently is written into the bottle and read by nobody, and
    /// the bottle looks configured.
    @Test func theValueNamesAreTheOnesThePatchReads() {
        #expect(DualSenseRoute.hidrawValue == "Hidraw")
        #expect(DualSenseRoute.usbEmulationValue == "UsbEmulation")
        #expect(DualSenseRoute.productIDValue == "ProductId")
    }

    /// A title nobody has told otherwise gets the pad as it is, and the bottle
    /// gets zeros -- which is what every title got before the option existed.
    @Test func theDefaultIsThePadAsItIs() {
        #expect(DualSensePresentation.byDefault == .asItIs)
        #expect(DualSensePresentation.pickable(nil) == DualSensePresentation.asItIs.rawValue)
        #expect(DualSensePresentation.pickable("something a later build wrote") == DualSensePresentation.asItIs.rawValue)
        let o = over([pad(SonyPads.dualSenseEdge, "Bluetooth")], .asItIs)
        #expect(entry(o, SonyPads.dualSenseEdge)?.usbEmulation == 0)
        #expect(entry(o, SonyPads.dualSenseEdge)?.askedProductID == 0)
    }

    /// The case this was built for: an Edge on Bluetooth, on the patched
    /// engine, asked to look plugged in. Its own id, so nothing to override.
    @Test func anEdgeOnBluetoothIsAskedToLookWired() {
        let o = over([pad(SonyPads.dualSenseEdge, "Bluetooth")], .wired)
        #expect(entry(o, SonyPads.dualSenseEdge)?.usbEmulation == 1)
        #expect(entry(o, SonyPads.dualSenseEdge)?.askedProductID == 0)
        #expect(entry(o, SonyPads.dualSenseEdge)?.hidraw == 1, "the emulation lives on the raw route")
        #expect(entry(o, SonyPads.dualSense)?.usbEmulation == 1,
                "the model that is not here gets the same choice, for when it is the one that arrives")
    }

    /// A pad already on USB has nothing to be presented as, and the driver
    /// ignores both values for anything that is not on Bluetooth. The choice is
    /// written for it all the same, because the pad this title is set up for is
    /// the one that comes back over Bluetooth later -- and the console says so
    /// rather than leaving "nothing to present" sounding like "nothing was
    /// written".
    @Test func aWiredPadIsToldSoAndTheChoiceIsWrittenAnyway() {
        let o = over([pad(SonyPads.dualSenseEdge, "USB")], .wired)
        #expect(entry(o, SonyPads.dualSenseEdge)?.usbEmulation == 1)
        let sentence = said([pad(SonyPads.dualSenseEdge, "USB")], .wired)
        #expect(sentence.contains("nothing to present"))
        #expect(sentence.contains("when it comes back over Bluetooth"))
    }

    /// An engine whose winebus has no USB emulation is never asked for it: the
    /// values would sit in the bottle unread, and the console would have
    /// promised something that never happened.
    @Test func anEngineWithoutThePatchIsNeverAskedToEmulate() {
        for presentation in DualSensePresentation.allCases {
            let o = over([pad(SonyPads.dualSenseEdge, "Bluetooth")], presentation, canEmulate: false)
            #expect(o.allSatisfy { $0.usbEmulation == 0 && $0.askedProductID == 0 }, "for \(presentation)")
        }
        #expect(said([pad(SonyPads.dualSenseEdge, "Bluetooth")], .wired, canEmulate: false)
                    .contains("no USB emulation"))
    }

    /// A pad handed to SDL is a wine gamepad before winebus could present it as
    /// anything. On the older engine, where Bluetooth still means the SDL
    /// detour, the emulation is not asked for.
    @Test func aPadRoutedThroughSDLIsNeverPresentedAsWired() {
        let o = over([pad(SonyPads.dualSenseEdge, "Bluetooth")], .wired, sdl: true, tells: false)
        #expect(entry(o, SonyPads.dualSenseEdge)?.hidraw == 0, "it is on the SDL route")
        #expect(entry(o, SonyPads.dualSenseEdge)?.usbEmulation == 0)
        #expect(said([pad(SonyPads.dualSenseEdge, "Bluetooth")], .wired, sdl: true, tells: false)
                    .contains("a pad handed to SDL"))
    }

    /// The choice for a title whose Sony library never heard of the Edge: the
    /// plain pad's id is written, for the Edge to be presented under.
    @Test func theStandardChoiceNamesThePlainPadForAnEdge() {
        let o = over([pad(SonyPads.dualSenseEdge, "Bluetooth")], .wiredStandard)
        #expect(entry(o, SonyPads.dualSenseEdge)?.usbEmulation == 1)
        #expect(entry(o, SonyPads.dualSenseEdge)?.askedProductID == UInt32(SonyPads.dualSense))
    }

    /// And it is served. The driver carries the plain DualSense's own USB
    /// report descriptor beside the Edge's -- read from the pad on a cable, 289
    /// bytes against the Edge's 405 -- so the Edge is genuinely created as
    /// 054c:0ce6 rather than having the override refused and arriving as a
    /// wired Edge. The console names what the game sees, not what is on the
    /// desk.
    @Test func theStandardChoiceIsServedForAnEdge() {
        let asPlain = DualSensePresentation.wiredStandard
        #expect(asPlain.askedProductID(for: SonyPads.dualSenseEdge) == SonyPads.dualSense)
        #expect(asPlain.presentsAsWired)
        let sentence = said([pad(SonyPads.dualSenseEdge, "Bluetooth")], .wiredStandard)
        #expect(sentence.contains("presented as a plain wired DualSense rather than as an Edge"))
        #expect(sentence.contains("has not been captured yet") == false)
    }

    /// The plain pad is presented as wired too, whichever of the two choices
    /// asks for it: its descriptor is compiled in as well. Asking a plain pad
    /// to look like a plain pad is not an override, so its id stays 0 and the
    /// driver keeps the pad's own.
    @Test func aPlainDualSenseIsPresentedAsWiredToo() {
        for presentation in [DualSensePresentation.wired, .wiredStandard] {
            #expect(presentation.presentsAsWired, "for \(presentation)")
            #expect(presentation.askedProductID(for: SonyPads.dualSense) == SonyPads.dualSense, "for \(presentation)")
            #expect(presentation.productIDValue(for: SonyPads.dualSense) == 0, "for \(presentation)")
            let o = over([pad(SonyPads.dualSense, "Bluetooth")], presentation)
            #expect(entry(o, SonyPads.dualSense)?.usbEmulation == 1, "for \(presentation)")
            #expect(entry(o, SonyPads.dualSense)?.askedProductID == 0, "for \(presentation)")
            let sentence = said([pad(SonyPads.dualSense, "Bluetooth")], presentation)
            #expect(sentence.contains("presented as a wired DualSense"), "for \(presentation)")
            #expect(sentence.contains("no USB report descriptor") == false, "for \(presentation)")
        }
    }

    /// What makes it per game: every launch writes all three values for both
    /// models, so the title that wants the pad as it is clears what the last
    /// title set rather than inheriting it.
    @Test func everyLaunchClearsWhatTheLastGameAskedFor() {
        let o = over([pad(SonyPads.dualSenseEdge, "Bluetooth")], .asItIs)
        #expect(o.count == 2)
        #expect(o.allSatisfy { $0.usbEmulation == 0 && $0.askedProductID == 0 })
    }

    /// The case the console's own advice depends on: the pad is off, or on a
    /// cable, when the game starts. The choice goes in anyway, because winebus
    /// reads it as the pad arrives -- so "reconnect the pad" can work at all.
    /// Gating this on "attached over Bluetooth right now" wrote a 0 for exactly
    /// the pad the sentence was about, and bought nothing: the driver refuses
    /// these values by itself for anything that is not a hidraw device on
    /// BUS_TYPE_BLUETOOTH.
    @Test func theChoiceIsWrittenForAPadThatIsNotEvenHere() {
        let o = over([], .wired)
        #expect(o.count == 2)
        #expect(o.allSatisfy { $0.usbEmulation == 1 && $0.hidraw == 1 })
        #expect(entry(o, SonyPads.dualSenseEdge)?.askedProductID == 0)
        #expect(entry(over([], .wiredStandard), SonyPads.dualSenseEdge)?.askedProductID
                == UInt32(SonyPads.dualSense))
        // And a pad on a cable is not a reason to skip the model either.
        #expect(over([pad(SonyPads.dualSense, "USB")], .wired).allSatisfy { $0.usbEmulation == 1 })
    }

    /// With nothing attached the console still has something to say, because
    /// something was still written. Silence there would read as "nothing was
    /// done", which is the opposite of what happened -- and a title that asked
    /// for nothing still says nothing, as it always did.
    @Test func theConsoleSpeaksWithNoPadAttached() {
        #expect(said([], .wired).contains("no DualSense attached"))
        #expect(said([], .wired).contains("arrives over Bluetooth"))
        #expect(said([], .wired, canEmulate: false).contains("no USB emulation"))
        #expect(DualSenseRoute.summary(for: [], sdlEnabled: true, engineTellsTheBus: true,
                                       presentation: .asItIs, engineCanEmulateUSB: true) == nil)
    }

    /// The one gate that stays on the presentation, and why it is expressed as
    /// the route this same list writes rather than as the pad's transport:
    /// `Hidraw` 0 beside `UsbEmulation` 1 under one key is a pair that
    /// contradicts itself, and no combination of options may produce one.
    @Test func theRegistryNeverHoldsAContradictoryPair() {
        let arrangements = [[], [pad(SonyPads.dualSense, "Bluetooth")],
                            [pad(SonyPads.dualSenseEdge, "Bluetooth")],
                            [pad(SonyPads.dualSenseEdge, "USB")],
                            [pad(SonyPads.dualSense, "Bluetooth"), pad(SonyPads.dualSenseEdge, "USB")]]
        for pads in arrangements {
            for presentation in DualSensePresentation.allCases {
                for sdl in [true, false] {
                    for tells in [true, false] {
                        for canEmulate in [true, false] {
                            let o = over(pads, presentation, sdl: sdl, tells: tells, canEmulate: canEmulate)
                            #expect(o.allSatisfy { $0.hidraw == 1 || $0.usbEmulation == 0 },
                                    "\(pads.map(\.transport)) \(presentation) sdl \(sdl) tells \(tells) can \(canEmulate)")
                            #expect(o.allSatisfy { $0.usbEmulation == 1 || $0.askedProductID == 0 },
                                    "an id is only asked for where the emulation is")
                        }
                    }
                }
            }
        }
    }

    /// Never "now". Both values are read as the device arrives, so the console
    /// says what has to happen for them to be read at all -- and says it for
    /// the default too, because writing zeros is a request as much as writing
    /// ones is: the title that goes back to the pad as it is is undoing what
    /// the last title asked for, and that lands no sooner.
    @Test func theConsoleSaysWhenItTakesEffect() {
        #expect(said([pad(SonyPads.dualSenseEdge, "Bluetooth")], .wired).contains("when the pad next arrives"))
        #expect(said([pad(SonyPads.dualSenseEdge, "Bluetooth")], .wired).contains("Steam closed"))
        #expect(said([pad(SonyPads.dualSenseEdge, "Bluetooth")], .asItIs)
                    .contains("clears what the last title asked for"))
        #expect(said([pad(SonyPads.dualSenseEdge, "Bluetooth")], .asItIs, canEmulate: false)
                    .contains("clears what the last title asked for") == false,
                "an engine that cannot emulate has nothing to clear")
    }

    /// And the route half of the sentence follows the emulation: mgvf-0005
    /// creates the device as USB, so mgvf-0002's compatible ids and hidapi's
    /// flag say USB too. The console used to say the engine tells Steam the pad
    /// is on Bluetooth in the same breath as saying it is presented as wired.
    @Test func theRouteSentenceFollowsWhatTheBusIsToldToSay() {
        let presented = said([pad(SonyPads.dualSenseEdge, "Bluetooth")], .wired)
        #expect(presented.contains("tells Steam it is on USB"))
        #expect(presented.contains("tells Steam it is on Bluetooth") == false)
        #expect(said([pad(SonyPads.dualSense, "Bluetooth")], .wired).contains("tells Steam it is on USB"),
                "the plain pad is presented as well")
        // A pad nothing is presenting keeps the truthful Bluetooth sentence.
        #expect(said([pad(SonyPads.dualSense, "Bluetooth")], .wired, canEmulate: false)
                    .contains("tells Steam it is on Bluetooth"))
    }

    // MARK: the engine, from its own binary

    /// An engine shaped like a real one as far as this question goes: one
    /// winebus.sys, where the engine keeps it. Nothing is written anywhere near
    /// a real engine.
    private func engine(winebus: URL) throws -> URL {
        let f = FileManager.default
        let app = f.temporaryDirectory.appendingPathComponent("pad-\(UUID().uuidString).app", isDirectory: true)
        let dir = app.appendingPathComponent("Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows")
        try f.createDirectory(at: dir, withIntermediateDirectories: true)
        try f.copyItem(at: winebus, to: dir.appendingPathComponent("winebus.sys"))
        return app
    }

    /// The patched winebus this application carries, and the one MacGameVideoFix
    /// built beside it -- whichever is on this machine.
    private var patchedWinebus: URL? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [
            root.appendingPathComponent("RaccoonBot/Libs/mgvf/MacGameVideoFix.app/Contents/Resources/engine-controller-winebus.sys"),
            root.deletingLastPathComponent().appendingPathComponent("MacGameVideoFix/runtime/engine-controller-winebus.sys"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// Read from the binary, not from a version: mgvf-0005 leaves the name of
    /// the value it reads in the PE as a UTF-16 literal, and a winebus without
    /// the patch has no reason to contain that word.
    @Test func aPatchedWinebusSaysSoInItsOwnBytes() throws {
        guard let winebus = patchedWinebus else { return }   // another machine, another checkout
        let app = try engine(winebus: winebus)
        defer { try? FileManager.default.removeItem(at: app) }
        let path = app.path(percentEncoded: false)
        #expect(DualSenseRoute.engineCanEmulateUSB(cxAppPath: path))
        #expect(DualSenseRoute.engineTellsTheBus(cxAppPath: path), "mgvf-0005 travels with mgvf-0002")
    }

    private func winebus(ofEngineAt path: String) -> String {
        path + "/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows/winebus.sys"
    }

    /// The negative, against real engines rather than a made-up file, and read
    /// only -- nothing here opens an engine for writing.
    ///
    /// Stock CrossOver is nobody's copy: this application patches copies it
    /// made and never the installation itself, so the stock engine is the one
    /// that has to answer no. And whatever else is installed, an engine that
    /// answers yes tells the bus as well: mgvf-0005 lives in the same winebus
    /// as mgvf-0002 and cannot be in an engine without it. Skipped, quietly,
    /// on a machine with no engine installed.
    @Test func aRealEngineIsReadForWhatItActuallyCarries() {
        let f = FileManager.default
        let stock = "/Applications/CrossOver.app"
        if f.fileExists(atPath: winebus(ofEngineAt: stock)) {
            #expect(DualSenseRoute.engineCanEmulateUSB(cxAppPath: stock) == false,
                    "a stock CrossOver carries none of our patches")
        }
        let ours = f.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Crossover_MGVF.app").path(percentEncoded: false)
        for engine in [stock, ours] where f.fileExists(atPath: winebus(ofEngineAt: engine)) {
            if DualSenseRoute.engineCanEmulateUSB(cxAppPath: engine) {
                #expect(DualSenseRoute.engineTellsTheBus(cxAppPath: engine),
                        "mgvf-0005 never travels without mgvf-0002: \(engine)")
            }
        }
    }

    /// And a winebus that is not one of ours at all answers no rather than
    /// throwing or guessing.
    @Test func aWinebusWithNeitherPatchAnswersNo() throws {
        let f = FileManager.default
        let bytes = f.temporaryDirectory.appendingPathComponent("pad-\(UUID().uuidString).sys")
        try Data("MZ and then some bytes that say nothing about any bus".utf8).write(to: bytes)
        defer { try? f.removeItem(at: bytes) }
        let app = try engine(winebus: bytes)
        defer { try? f.removeItem(at: app) }
        #expect(DualSenseRoute.engineCanEmulateUSB(cxAppPath: app.path(percentEncoded: false)) == false)
        #expect(DualSenseRoute.engineTellsTheBus(cxAppPath: app.path(percentEncoded: false)) == false)
    }

    /// Nothing to read is not a yes.
    @Test func aMissingEngineCannotEmulate() {
        #expect(DualSenseRoute.engineCanEmulateUSB(cxAppPath: nil) == false)
        #expect(DualSenseRoute.engineCanEmulateUSB(cxAppPath: "") == false)
        #expect(DualSenseRoute.engineCanEmulateUSB(cxAppPath: "/nonexistent.app") == false)
    }

    // MARK: the option on disk

    /// A new form starts on the default, and the choice survives the round trip
    /// through the saved record -- the trip three HUD fields did not survive.
    @Test func theChoiceSurvivesTheSavedRecord() {
        #expect(GameOptions().dualSensePresentation == DualSensePresentation.asItIs.rawValue)
        let mine = GameOptions()
        mine.dualSensePresentation = DualSensePresentation.wiredStandard.rawValue
        let restored = GameOptions()
        restored.set(data: GameOptionsData(data: mine))
        #expect(restored.dualSensePresentation == DualSensePresentation.wiredStandard.rawValue)
    }

    /// The merge path, which is the one an imported configuration takes: a
    /// record that says nothing about the pad leaves the choice alone, and one
    /// that does is folded the same way the load folds it.
    @Test func theMergePathKeepsAndFoldsTheChoice() {
        let form = GameOptions()
        form.dualSensePresentation = DualSensePresentation.wired.rawValue
        form.importAutoConfig(data: GameOptionsData(data: GameOptions()) )
        #expect(form.dualSensePresentation == DualSensePresentation.asItIs.rawValue,
                "a record built from a form does say, and says the default")

        var silent = GameOptionsData(data: GameOptions())
        silent.dualSensePresentation = nil
        form.dualSensePresentation = DualSensePresentation.wired.rawValue
        form.importAutoConfig(data: silent)
        #expect(form.dualSensePresentation == DualSensePresentation.wired.rawValue)

        var strange = silent
        strange.dualSensePresentation = "a choice this build does not have"
        form.importAutoConfig(data: strange)
        #expect(form.dualSensePresentation == DualSensePresentation.asItIs.rawValue)
    }

    /// A record saved before this option existed decodes, and reads as the
    /// default rather than as nothing.
    @Test func aRecordFromBeforeTheOptionReadsAsTheDefault() throws {
        let old = try JSONDecoder().decode(GameOptionsData.self, from: Data(#"{"enableSDL": true}"#.utf8))
        #expect(old.dualSensePresentation == nil)
        let form = GameOptions()
        form.set(data: old)
        #expect(form.dualSensePresentation == DualSensePresentation.asItIs.rawValue)
    }

    /// Every entry the menu offers is one the enum knows, in the order it is
    /// declared, with the default first -- a pad cycles through this list.
    @Test func theMenuOffersTheThreeChoices() {
        #expect(DualSensePresentation.dropdownOptions.map(\.id)
                == DualSensePresentation.allCases.map(\.rawValue))
        #expect(DualSensePresentation.dropdownOptions.first?.id == DualSensePresentation.byDefault.rawValue)
        #expect(DualSensePresentation.allCases.count == 3)
        #expect(DualSensePresentation.dropdownOptions.allSatisfy { !$0.label.isEmpty })
    }
}
