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

    // Three cases that asserted THIS machine's engines were here and are gone.
    //
    // They named Crossover_patched.app, a specific CFBundleVersion and a
    // specific wine tag, and they broke the moment those copies were deleted
    // to validate the flow from scratch -- which is a thing somebody is
    // entitled to do. The finding behind them survives where it belongs, in
    // the comment on EngineIdentity: a patched copy and the stock CrossOver
    // report the SAME CFBundleVersion, which is why identity cannot rest on
    // the version alone. A measurement of one install is not a test of the
    // code, and it fails for the wrong reason the day the install changes.
}
