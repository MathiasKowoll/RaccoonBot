//
//  EmbeddedFixesTests.swift
//  RaccoonBotTests
//

import Foundation
import Testing
@testable import RaccoonBot

struct EmbeddedFixesTests {

    /// The payload as it sits in the source tree, which is what the build
    /// copies into Resources.
    private var embedded: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RaccoonBot/Libs/mgvf/MacGameVideoFix.app/Contents/Resources")
    }

    /// The index this application reads. Embedding an app without it is the
    /// failure that held this change up for a release: the catalogue would
    /// report unavailable and every title would show as needing nothing, which
    /// looks exactly like success.
    @Test func theManifestTravels() throws {
        let manifest = embedded.appendingPathComponent("manifest.json")
        try #require(FileManager.default.fileExists(atPath: manifest.path(percentEncoded: false)))
        let data = try Data(contentsOf: manifest)
        let decoded = try JSONDecoder().decode(MGVFManifest.self, from: data)
        #expect(decoded.schema == 3)
        #expect(decoded.games.isEmpty == false)
    }

    /// A published app was once a strict subset of the tarball, missing NINJA
    /// GAIDEN 3 and the manifest. Both are asserted here so an embedded copy
    /// that regressed would fail on this side too, not only on theirs.
    @Test func whatTheTarballShipsIsHereToo() {
        for name in ["install-ng3-fix.sh", "ng3-d3d9.dll", "make-engine-copy.sh",
                     "install-engine-media.sh"] {
            #expect(FileManager.default.fileExists(
                atPath: embedded.appendingPathComponent(name).path(percentEncoded: false)),
                    "\(name) is not in the embedded application")
        }
    }

    /// Every installer the manifest names has to be there, or a title silently
    /// has no fix.
    @Test func everyScriptTheManifestNamesIsPresent() throws {
        let data = try Data(contentsOf: embedded.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(MGVFManifest.self, from: data)
        for game in manifest.games {
            #expect(FileManager.default.fileExists(
                atPath: embedded.appendingPathComponent(game.script).path(percentEncoded: false)),
                    "\(game.name) names \(game.script), which is not embedded")
        }
    }

    /// There is no download left to fall back to, and the error says so rather
    /// than suggesting one.
    @Test func theAbsenceOfTheEmbeddedCopyIsExplained() {
        let message = MGVFBundleError.notBundled.errorDescription ?? ""
        #expect(message.contains("inside the application"))
        #expect(message.contains("no download"))
    }
}
