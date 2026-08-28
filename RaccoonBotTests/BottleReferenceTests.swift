//
//  BottleReferenceTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

@Suite("Reading a bottle however it was written")
struct BottleReferenceTests {

    /// The shape that reached `--bottle` and made every shutdown fail.
    @Test func aFileURLYieldsTheNameAndItsRoot() throws {
        let ref = try #require(BottleReference(
            "file:///Users/someone/Library/Application%20Support/RaccoonBot/CXPBottles/Steam/"))

        #expect(ref.name == "Steam")
        #expect(ref.root == "/Users/someone/Library/Application Support/RaccoonBot/CXPBottles")
    }

    @Test func percentEncodingIsUndoneInTheName() throws {
        let ref = try #require(BottleReference("file:///Users/someone/CXPBottles/Steam%20ARM"))
        #expect(ref.name == "Steam ARM")
    }

    @Test func aPlainPathWorksToo() throws {
        let ref = try #require(BottleReference("/Users/someone/CXPBottles/Steam"))
        #expect(ref.name == "Steam")
        #expect(ref.root == "/Users/someone/CXPBottles")
    }

    /// A bare name is already what `--bottle` wants; there is no root to find,
    /// and inventing one would send the engine somewhere.
    @Test func aBareNameIsLeftAlone() throws {
        let ref = try #require(BottleReference("Steam"))
        #expect(ref.name == "Steam")
        #expect(ref.root == "")
        #expect(ref.environmentPrefix == "")
    }

    @Test func aRootBecomesAnEnvironmentPrefix() throws {
        let ref = try #require(BottleReference("/Users/someone/CXPBottles/Steam"))
        #expect(ref.environmentPrefix == "CX_BOTTLE_PATH=\"/Users/someone/CXPBottles\" ")
    }

    /// The root must not change shape according to what happens to exist on
    /// this machine, or the same bottle reads differently on two computers.
    @Test func theRootDoesNotDependOnWhatIsOnDisk() throws {
        let missing = try #require(BottleReference("/nowhere/at/all/CXPBottles/Steam"))
        #expect(missing.root == "/nowhere/at/all/CXPBottles")
        #expect(!missing.root.hasSuffix("/"))
    }

    @Test func trailingSlashesDoNotProduceAnEmptyName() throws {
        let ref = try #require(BottleReference("/Users/someone/CXPBottles/Steam/"))
        #expect(ref.name == "Steam")
    }

    @Test(arguments: ["", "   ", "/"])
    func nothingUsableIsRejected(_ input: String) {
        #expect(BottleReference(input) == nil)
    }
}
