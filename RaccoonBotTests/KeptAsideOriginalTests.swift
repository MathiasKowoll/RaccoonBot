//
//  KeptAsideOriginalTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Where the evidence of an installed fix actually is.
///
/// The manifest names a carrier directory. The Unreal installer puts the
/// carrier one subfolder further down, under a compiler-named directory it
/// discovers on the machine -- and a gate that looked only where the manifest
/// said refused four patched titles at launch as needing the fix they had.
struct KeptAsideOriginalTests {

    private func unreal() -> MGVFGame {
        MGVFGame(name: "Mortal Shell 2", script: "install-runtime-fix.sh",
                 exe: "MortalShell2-Win64-Shipping.exe", files: ["libogg_64.dll"],
                 carrier: "libogg_64.dll", keptAs: "libogg_64_real.dll",
                 carrierDir: "Engine/Binaries/ThirdParty/Ogg/Win64", why: "test",
                 writesRegistry: false, scope: nil, backend: nil, gptk: nil, env: nil, codec: nil)
    }

    private func folder(_ build: (URL) throws -> Void) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kept-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try build(dir)
        return dir.path(percentEncoded: false)
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x".write(to: url, atomically: true, encoding: .utf8)
    }

    /// The case on disk: Win64/VS2015/, one level below the manifest's path.
    @Test func findsTheOriginalUnderTheCompilerSubfolder() throws {
        let game = unreal()
        let f = try folder { dir in
            try touch(dir.appendingPathComponent("Engine/Binaries/ThirdParty/Ogg/Win64/VS2015/libogg_64_real.dll"))
        }
        let found = try #require(game.keptAsideOriginal(inGameFolder: f))
        #expect(found.lastPathComponent == "libogg_64_real.dll")
        #expect(found.path(percentEncoded: false).contains("/VS2015/"))
    }

    /// Where the manifest says is still the first place looked.
    @Test func findsItWhereTheManifestSaysToo() throws {
        let game = unreal()
        let f = try folder { dir in
            try touch(dir.appendingPathComponent("Engine/Binaries/ThirdParty/Ogg/Win64/libogg_64_real.dll"))
        }
        #expect(game.keptAsideOriginal(inGameFolder: f) != nil)
    }

    /// Two levels down is still found; three is the bound, deliberately.
    @Test func theSearchIsBoundedAtTwoLevels() throws {
        let game = unreal()
        let two = try folder { dir in
            try touch(dir.appendingPathComponent("Engine/Binaries/ThirdParty/Ogg/Win64/a/b/libogg_64_real.dll"))
        }
        #expect(game.keptAsideOriginal(inGameFolder: two) != nil)
        let three = try folder { dir in
            try touch(dir.appendingPathComponent("Engine/Binaries/ThirdParty/Ogg/Win64/a/b/c/libogg_64_real.dll"))
        }
        #expect(game.keptAsideOriginal(inGameFolder: three) == nil)
    }

    /// Only the kept-aside name counts. The carrier being present says nothing:
    /// it is there before and after the fix.
    @Test func theCarrierAloneIsNotEvidence() throws {
        let game = unreal()
        let f = try folder { dir in
            try touch(dir.appendingPathComponent("Engine/Binaries/ThirdParty/Ogg/Win64/VS2015/libogg_64.dll"))
        }
        #expect(game.keptAsideOriginal(inGameFolder: f) == nil)
    }

    @Test func anEmptyCarrierDirMeansTheGameFolderItself() throws {
        let game = MGVFGame(name: "Resonance", script: "install-resonance-fix.sh", exe: "r.exe",
                            files: ["NvCloth_x64.dll"], carrier: "NvCloth_x64.dll",
                            keptAs: "NvCloth_x64_real.dll", carrierDir: "", why: "test",
                            writesRegistry: false, scope: nil, backend: nil, gptk: nil, env: nil, codec: nil)
        let f = try folder { dir in try touch(dir.appendingPathComponent("NvCloth_x64_real.dll")) }
        #expect(game.keptAsideOriginal(inGameFolder: f) != nil)
    }
}
