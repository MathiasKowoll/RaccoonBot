//
//  MGVFOutdatedTests.swift
//  RaccoonBotTests
//
//  Whether a game that already has a fix learns that the fix changed.
//
//  Before this, it could not: the state came from asking the installer "are
//  you installed", which is not the same question. A title fixed from an old
//  bundle read as patched forever, and an improved fix only ever reached
//  people who had not applied the old one yet.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct MGVFFingerprintTests {

    private func bundleDir(script: String, files: [String: String] = [:]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mgvf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try script.write(to: dir.appendingPathComponent("install.sh"), atomically: true, encoding: .utf8)
        for (name, body) in files {
            try body.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return dir
    }

    private func game(files: [String] = []) -> MGVFGame {
        MGVFGame(name: "Some Title", script: "install.sh", exe: "Game.exe",
                 files: files, carrier: "libogg_64.dll", keptAs: "libogg_real.dll",
                 carrierDir: "", why: "VP9 in WebM", writesRegistry: false, scope: nil,
                 backend: nil, gptk: nil, env: nil, codec: "libgstlibav")
    }

    @Test func theSameFixFingerprintsTheSame() throws {
        let dir = try bundleDir(script: "#!/bin/sh\necho one\n")
        #expect(game().fingerprint(inDirectory: dir) == game().fingerprint(inDirectory: dir))
    }

    /// The case the whole thing exists for. A fix improves by someone editing
    /// the script; every field in the manifest stays exactly as it was, so an
    /// entry-only comparison would call it unchanged.
    @Test func changingTheScriptChangesTheFingerprint() throws {
        let before = try bundleDir(script: "#!/bin/sh\necho one\n")
        let after = try bundleDir(script: "#!/bin/sh\necho one\necho and better\n")
        #expect(game().fingerprint(inDirectory: before) != game().fingerprint(inDirectory: after))
    }

    @Test func changingAnInstalledFileChangesIt() throws {
        let before = try bundleDir(script: "#!/bin/sh\n", files: ["proxy.dll": "AAAA"])
        let after = try bundleDir(script: "#!/bin/sh\n", files: ["proxy.dll": "BBBB"])
        let g = game(files: ["proxy.dll"])
        #expect(g.fingerprint(inDirectory: before) != g.fingerprint(inDirectory: after))
    }

    @Test func changingWhereTheCarrierLivesChangesIt() throws {
        let dir = try bundleDir(script: "#!/bin/sh\n")
        let a = game()
        let b = MGVFGame(name: "Some Title", script: "install.sh", exe: "Game.exe",
                         files: [], carrier: "libogg_64.dll", keptAs: "libogg_real.dll",
                         carrierDir: "Engine/Binaries", why: "VP9 in WebM",
                         writesRegistry: false, scope: nil, backend: nil, gptk: nil, env: nil,
                         codec: "libgstlibav")
        #expect(a.fingerprint(inDirectory: dir) != b.fingerprint(inDirectory: dir))
    }

    /// Fields are length-prefixed so two different splits cannot collide:
    /// "ab"+"c" and "a"+"bc" are the same concatenation and not the same fix.
    @Test func adjacentFieldsCannotBeConfusedForEachOther() throws {
        let dir = try bundleDir(script: "#!/bin/sh\n")
        let a = MGVFGame(name: "T", script: "install.sh", exe: "Game.exe", files: [],
                         carrier: "ab", keptAs: "c", carrierDir: "", why: "",
                         writesRegistry: false, scope: nil, backend: nil, gptk: nil, env: nil, codec: nil)
        let b = MGVFGame(name: "T", script: "install.sh", exe: "Game.exe", files: [],
                         carrier: "a", keptAs: "bc", carrierDir: "", why: "",
                         writesRegistry: false, scope: nil, backend: nil, gptk: nil, env: nil, codec: nil)
        #expect(a.fingerprint(inDirectory: dir) != b.fingerprint(inDirectory: dir))
    }

    /// `why` is prose for the confirmation dialog. Rewording it is not a new
    /// fix, and treating it as one would re-offer every title on a typo fix.
    @Test func rewordingTheExplanationIsNotANewFix() throws {
        let dir = try bundleDir(script: "#!/bin/sh\n")
        let a = game()
        let b = MGVFGame(name: "Some Title", script: "install.sh", exe: "Game.exe",
                         files: [], carrier: "libogg_64.dll", keptAs: "libogg_real.dll",
                         carrierDir: "", why: "a completely different sentence",
                         writesRegistry: false, scope: nil, backend: nil, gptk: nil, env: nil,
                         codec: "libgstlibav")
        #expect(a.fingerprint(inDirectory: dir) == b.fingerprint(inDirectory: dir))
    }
}

/// The states, and the one rule that keeps this honest: a folder we recorded
/// nothing for is a folder we cannot speak about.
struct MGVFOutdatedStateTests {

    @Test func outdatedIsActionableButNotInstallable() {
        #expect(GameFixState.outdated.isActionable)
        #expect(GameFixState.outdated.isApplied)
        #expect(GameFixState.patched.isApplied)
        #expect(!GameFixState.patched.isActionable)
        #expect(GameFixState.needsPatch.isActionable)
        #expect(!GameFixState.needsPatch.isApplied)
    }

    @Test func dismissedIsStillNotSomethingToDo() {
        // A removal was a decision. A newer fix does not undo it.
        #expect(!GameFixState.dismissed.isActionable)
        #expect(!GameFixState.dismissed.isApplied)
    }

    @Test func unknownIsNeitherAppliedNorActionable() {
        // "We could not look" is not "it is missing" and not "it is there".
        #expect(!GameFixState.unknown("boom").isActionable)
        #expect(!GameFixState.unknown("boom").isApplied)
    }
}

/// Asking GitHub for a release tag, when GitHub does not answer with one.
///
/// The anonymous API allows sixty requests an hour and answers 403 with a body
/// that has a `message` and no `tag_name`. Every value in this function used
/// to be force-unwrapped, and a trap is not catchable by the do/catch around
/// the call site -- so being rate limited while patching CrossOver killed the
/// application.
struct ReleaseLookupTests {

    @Test func rateLimitingIsExplainedRatherThanCrashing() {
        let message = ReleaseLookupError.http(403).errorDescription ?? ""
        #expect(message.contains("rate limiting"))
        #expect(message.contains("sixty"), "the number is the actionable part")
    }

    @Test func otherFailuresCarryTheirCode() {
        #expect(ReleaseLookupError.http(500).errorDescription?.contains("500") == true)
        #expect(ReleaseLookupError.noTag.errorDescription?.isEmpty == false)
    }

    /// A body shaped like GitHub's rate-limit reply decodes to a dictionary
    /// with no tag. That is the exact shape that used to trap.
    @Test func aBodyWithNoTagIsAnErrorNotATrap() throws {
        let body = Data(#"{"message":"API rate limit exceeded","documentation_url":"https://..."}"#.utf8)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["tag_name"] == nil)
        #expect(json?["message"] != nil)
    }
}
