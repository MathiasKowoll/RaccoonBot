//
//  EngineIdentityTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

@Suite("Knowing which engine this is")
struct EngineIdentityTests {

    private var patched: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications/Crossover_patched.app")
    }
    private let stock = URL(fileURLWithPath: "/Applications/CrossOver.app")

    /// The engine this machine actually runs games on.
    @Test func therealPatchedEngineIdentifiesItself() throws {
        try #require(FileManager.default.fileExists(atPath: patched.path))
        let id = EngineIdentity(ofEngineAt: patched)
        #expect(id.app == "Crossover_patched.app")
        #expect(id.version == "26.3.0.39832")
        #expect(id.wine == "wine-11.0-8726-g2e2f5fca349")
    }

    /// The measurement behind the whole rule: a patched copy and a stock
    /// CrossOver report the same CFBundleVersion, so the name is the only thing
    /// that separates them.
    @Test func bothEnginesReportTheSameVersion() throws {
        try #require(FileManager.default.fileExists(atPath: stock.path))
        try #require(FileManager.default.fileExists(atPath: patched.path))
        let a = EngineIdentity(ofEngineAt: patched)
        let b = EngineIdentity(ofEngineAt: stock)
        #expect(a.version == b.version, "if these ever differ, the name is no longer load-bearing")
        #expect(a.app != b.app)
    }

    /// The published payload, against the engines on this machine.
    ///
    /// The JSON is the one v4.12.0 ships, kept here rather than read from the
    /// cache: a machine that has not downloaded it yet would otherwise turn
    /// this into a test that passes by finding nothing, which is the shape of
    /// green that has cost this project a whole night.
    @Test func theShippedPayloadMatchesThisEngineAndNotTheOther() throws {
        try #require(FileManager.default.fileExists(atPath: patched.path))
        try #require(FileManager.default.fileExists(atPath: stock.path))

        let payload = try JSONDecoder().decode(MGVFEnginePayload.self, from: Data(#"""
        {"script":"install-engine-media.sh","scope":"engine",
         "install":[{"file":"engine-winegstreamer.dll","dest":"lib/wine/x86_64-windows/winegstreamer.dll"},
                    {"file":"engine-winegstreamer.so","dest":"lib/wine/x86_64-unix/winegstreamer.so"}],
         "builtFor":{"app":"Crossover_patched.app","version":"26.3.0.39832",
                     "wine":"wine-11.0-8726-g2e2f5fca349"}}
        """#.utf8))

        let here = EngineIdentity(ofEngineAt: patched)
        let other = EngineIdentity(ofEngineAt: stock)
        #expect(payload.matches(app: here.app, version: here.version, wine: here.wine),
                "the payload should apply to the engine it names")
        #expect(payload.matches(app: other.app, version: other.version, wine: other.wine) == false,
                "and never to the stock CrossOver that reports the same version")
        for item in payload.install { #expect(!item.dest.lowercased().contains("d3d9")) }
    }

    /// And if a catalogue has been downloaded that carries one, it must say the
    /// same thing. Opportunistic on purpose -- it asserts nothing when there is
    /// nothing to assert about, and the test above covers the logic regardless.
    @Test func adownloadedCatalogueAgreesWhenThereIsOne() throws {
        let mgvf = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/RaccoonBot/mgvf")
        let payloads = ((try? FileManager.default.contentsOfDirectory(at: mgvf, includingPropertiesForKeys: nil)) ?? [])
            .map { $0.appendingPathComponent("manifest.json") }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? JSONDecoder().decode(MGVFManifest.self, from: $0) }
            .compactMap(\.engine)
        guard !payloads.isEmpty else { return }

        let here = EngineIdentity(ofEngineAt: patched)
        for payload in payloads {
            #expect(payload.matches(app: here.app, version: here.version, wine: here.wine))
            for item in payload.install { #expect(!item.dest.lowercased().contains("d3d9")) }
        }
    }

    @Test func anEngineThatIsNotThereSaysSoRatherThanGuessing() {
        let id = EngineIdentity(ofEngineAt: URL(fileURLWithPath: "/nowhere/None.app"))
        #expect(id.app == "None.app")
        #expect(id.version == nil)
        #expect(id.wine == nil)
    }

    @Test(arguments: [
        ("wine-11.0-8726-g2e2f5fca349", "wine-11.0-8726-g2e2f5fca349"),
        ("prefix wine-11.0-8726-g2e2f5fca349\u{0}suffix", "wine-11.0-8726-g2e2f5fca349"),
    ])
    func theTagIsReadOutOfSurroundingBytes(_ c: (haystack: String, wanted: String)) {
        #expect(EngineIdentity.tag(in: Data(c.haystack.utf8)) == c.wanted)
    }

    /// A bare version with no commit is some other string, not the build tag.
    @Test(arguments: ["wine-", "wine-11.0", "no tag here at all"])
    func somethingThatIsNotABuildTagIsNotRead(_ haystack: String) {
        #expect(EngineIdentity.tag(in: Data(haystack.utf8)) == nil)
    }
}
