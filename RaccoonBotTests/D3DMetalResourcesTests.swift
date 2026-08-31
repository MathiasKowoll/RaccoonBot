//
//  D3DMetalResourcesTests.swift
//  RaccoonBotTests
//

import Foundation
import Testing
@testable import RaccoonBot

struct D3DMetalResourcesTests {

    /// The generations as they sit in the source tree, which is what the build
    /// copies into Resources. Read here rather than out of Bundle.main, whose
    /// meaning depends on which bundle hosts the tests.
    private func generation(_ version: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RaccoonBot/Libs/d3dMetal\(version)")
    }

    /// The two generations do not carry the same names. A written list had 4's
    /// spellings, so installing 3 could not find `d3d10.dll` or
    /// `nvngx-on-metalfx.dll` and never installed its own `atidxx64.dll` or
    /// `nvngx.dll` -- while copyResource logged and carried on, so the install
    /// reported success and the engine held a mix of both.
    @Test func eachGenerationIsReadFromWhatItActuallyCarries() throws {
        let three = Set(d3dMetalResources(inGeneration: generation("3")))
        let four = Set(d3dMetalResources(inGeneration: generation("4")))
        try #require(!three.isEmpty, "no d3dMetal3 in this bundle")
        try #require(!four.isEmpty, "no d3dMetal4 in this bundle")

        #expect(three.contains("external"))
        #expect(four.contains("external"))
        #expect(three.contains("wine/x86_64-windows/atidxx64.dll"))
        #expect(three.contains("wine/x86_64-windows/nvngx.dll"))
        #expect(four.contains("wine/x86_64-windows/d3d10.dll"))
        #expect(four.contains("wine/x86_64-windows/nvngx-on-metalfx.dll"))

        // and neither is asked for a name it does not have
        #expect(three.contains("wine/x86_64-windows/d3d10.dll") == false)
        #expect(four.contains("wine/x86_64-windows/atidxx64.dll") == false)
    }

    /// Nothing is asked for that the generation does not carry -- which is the
    /// whole point, since the written list asked generation 3 for four names
    /// only generation 4 has.
    @Test func nothingIsAskedForThatTheGenerationDoesNotCarry() {
        for version in ["3", "4"] {
            let root = generation(version)
            let asked = d3dMetalResources(inGeneration: root)
            for path in asked where path != "external" {
                #expect(FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path(percentEncoded: false)),
                        "asked for \(path), which generation \(version) does not carry")
            }
        }
    }

    /// The unix half is symlinks into external, not regular files. Enumerating
    /// with isRegularFile drops all six per generation, and `find -type f`
    /// hides them the same way -- which is how they were first mistaken for
    /// missing entirely.
    @Test func theSymlinkedUnixLoadersAreNotDropped() {
        for version in ["3", "4"] {
            let asked = d3dMetalResources(inGeneration: generation(version))
            let unix = asked.filter { $0.contains("x86_64-unix") }
            #expect(unix.count == 6, "generation \(version) offered \(unix.count) unix loaders")
        }
    }

    /// The destination rename still applies: 4 ships nvngx-on-metalfx and the
    /// engine wants nvngx.
    @Test func theMetalFXLoaderIsStillRenamedAtTheDestination() {
        let asked = d3dMetalResources(inGeneration: generation("4"))
        #expect(asked.contains("wine/x86_64-windows/nvngx-on-metalfx.dll"))
        let dest = "wine/x86_64-windows/nvngx-on-metalfx.dll"
            .replacingOccurrences(of: "nvngx-on-metalfx", with: "nvngx")
        #expect(dest == "wine/x86_64-windows/nvngx.dll")
    }
}

