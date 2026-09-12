//
//  MachineIdentityTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct MachineIdentityTests {

    /// The variant is the unit, so the split has to get it right on every shape
    /// Apple ships and has to refuse to guess on anything it does not know.
    @Test func theVariantIsReadFromTheBrandStringAndNeverGuessed() {
        #expect(MachineIdentity.split(brand: "Apple M4 Max") == ("M4", "Max"))
        #expect(MachineIdentity.split(brand: "Apple M1 Pro") == ("M1", "Pro"))
        #expect(MachineIdentity.split(brand: "Apple M2 Ultra") == ("M2", "Ultra"))
        #expect(MachineIdentity.split(brand: "Apple M3") == ("M3", ""), "a base part has no tier, and an empty tier is the answer rather than a gap")
        // A generation this build has never heard of still parses, because the
        // rule is "M followed by digits" and not a list of chips we knew about
        // on the day this was written.
        #expect(MachineIdentity.split(brand: "Apple M9 Max") == ("M9", "Max"))
        // And something that is not an Apple part keeps its whole name and
        // takes no tier. Inventing one would put a wrong value in the single
        // field a reader would trust.
        let intel = MachineIdentity.split(brand: "Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz")
        #expect(intel.1 == "")
        #expect(intel.0.contains("Intel"))
        #expect(MachineIdentity.split(brand: "") == ("unknown", ""))
    }

    /// A word that merely starts with M is not a chip.
    @Test func onlyAnMFollowedByDigitsIsTheChip() {
        #expect(MachineIdentity.split(brand: "Apple Mac M2 Pro").0 == "M2")
        #expect(MachineIdentity.split(brand: "Mystery Machine").1 == "")
    }

    /// Read from the machine this is running on. The assertions are about
    /// shape rather than about values, because the values are whatever Mac
    /// happens to be running the suite.
    @Test func theMachineDescribesItself() {
        let m = MachineIdentity.current
        #expect(!m.chip.isEmpty)
        #expect(!m.model.isEmpty)
        #expect(m.memoryGB > 0, "every Mac has memory; a zero here means the sysctl name moved")
        #expect(!m.macOS.isEmpty)
        #expect(m.described.contains(m.chip))
        #expect(m.described.contains(m.model))
        // Apple Silicon only, which every supported Mac is. The GPU core count
        // is allowed to be zero -- it is one IOKit property and this must not
        // refuse to identify a machine for want of it -- but on a Mac that can
        // run this at all it should be there.
        if m.family.first == "M" {
            #expect(m.gpuCores > 0, "gpu-core-count is readable on Apple Silicon; zero means the IOKit class moved")
        }
    }

    /// Reading it twice gives the same answer, because it is cached and because
    /// nothing it reads changes while the application runs.
    @Test func itIsStableWithinARun() {
        #expect(MachineIdentity.current == MachineIdentity.current)
        #expect(MachineIdentity.current == MachineIdentity.detect())
    }

    /// The point of the whole thing: a saved record carries the machine it was
    /// written on. This is the round-trip that the Metal HUD settings and the
    /// trace toggle both failed, in the same initialiser, on two separate days.
    @Test func aSavedRecordCarriesTheMachine() throws {
        let options = GameOptions()
        let saved = GameOptionsData(data: options)
        #expect(saved.savedOnMachine == MachineIdentity.current)

        let coded = try JSONEncoder().encode(saved)
        let back = try JSONDecoder().decode(GameOptionsData.self, from: coded)
        #expect(back.savedOnMachine == MachineIdentity.current, "and it survives the disk, which is the only place it is any use")
    }

    /// A record from somewhere else keeps the machine it came from. Rewriting
    /// it on sight would turn every downloaded configuration into a claim about
    /// this Mac, which is the one thing a catalog of them must never do.
    @Test func aRecordFromAnotherMachineIsNotRelabelledByReadingIt() throws {
        let elsewhere = MachineIdentity(chip: "Apple M1", family: "M1", tier: "",
                                        model: "MacBookAir10,1", gpuCores: 7,
                                        memoryGB: 8, macOS: "15.0")
        var data = GameOptionsData(data: GameOptions())
        data.savedOnMachine = elsewhere

        let coded = try JSONEncoder().encode(data)
        let back = try JSONDecoder().decode(GameOptionsData.self, from: coded)
        #expect(back.savedOnMachine == elsewhere)

        // And reading it into the panel leaves it alone, because the panel has
        // no field for it and set(data:) is not where it is written.
        let options = GameOptions()
        options.set(data: back)
        #expect(back.savedOnMachine == elsewhere)
    }

    /// An older record has no machine at all, and that is a legal value rather
    /// than something to invent one for.
    @Test func aRecordFromBeforeThisExistedHasNoMachine() throws {
        let old = try JSONDecoder().decode(GameOptionsData.self, from: Data(#"{"wineMSync":true}"#.utf8))
        #expect(old.savedOnMachine == nil)
        #expect(old.wineMSync == true)
    }
}
