//
//  MGVFEnginePayloadTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

private func payload(_ json: String) throws -> MGVFEnginePayload {
    try JSONDecoder().decode(MGVFEnginePayload.self, from: Data(json.utf8))
}

private let real = #"""
{"script":"install-engine-media.sh","scope":"engine",
 "install":[{"file":"engine-winegstreamer.dll","dest":"lib/wine/x86_64-windows/winegstreamer.dll"},
            {"file":"engine-winegstreamer.so","dest":"lib/wine/x86_64-unix/winegstreamer.so"}],
 "builtFor":{"app":"Crossover_patched.app","version":"26.3.0.39832",
             "wine":"wine-11.0-8726-g2e2f5fca349"}}
"""#

@Suite("Media the engine itself needs")
struct MGVFEnginePayloadTests {

    @Test func itDecodesAndKnowsWhereEachHalfGoes() throws {
        let p = try payload(real)
        #expect(p.install.count == 2)
        #expect(p.install.map(\.dest) == ["lib/wine/x86_64-windows/winegstreamer.dll",
                                          "lib/wine/x86_64-unix/winegstreamer.so"])
    }

    @Test func theEngineItWasBuiltForMatches() throws {
        #expect(try payload(real).matches(app: "Crossover_patched.app",
                                          version: "26.3.0.39832",
                                          wine: "wine-11.0-8726-g2e2f5fca349"))
    }

    /// The version alone does not identify an engine. A patched copy and a
    /// stock CrossOver both report 26.3.0.39832, and writing these halves into
    /// the stock one is a thing that has already happened once.
    @Test func aDifferentApplicationWithTheSameVersionIsNotAMatch() throws {
        #expect(try payload(real).matches(app: "CrossOver.app",
                                          version: "26.3.0.39832",
                                          wine: "wine-11.0-8726-g2e2f5fca349") == false)
    }

    /// Onto a different wine they do not degrade: media stops loading, which
    /// is the exact shape of the fault they repair.
    @Test func adifferentWineIsNotAMatch() throws {
        #expect(try payload(real).matches(app: "Crossover_patched.app",
                                          version: "26.3.0.39832",
                                          wine: "wine-11.0-9000-gdeadbeef") == false)
    }

    /// Unknown is not yes. An engine that will not say what wine it carries
    /// gets nothing, because the failure would look like the fault.
    @Test func anEngineThatCannotSayIsNotAMatch() throws {
        #expect(try payload(real).matches(app: "Crossover_patched.app",
                                          version: nil, wine: nil) == false)
    }

    @Test func aPayloadThatSaysNothingAboutItsEngineIsNeverApplied() throws {
        let vague = try payload(#"{"install":[{"file":"a","dest":"b"}]}"#)
        #expect(vague.matches(app: "Crossover_patched.app",
                              version: "26.3.0.39832",
                              wine: "wine-11.0-8726-g2e2f5fca349") == false)
    }

    /// It must never carry a d3d9: the patcher puts d9vk at exactly that path,
    /// and one built alongside these halves is sitting on top of it on this
    /// machine right now.
    @Test func nothingInThePayloadTouchesD3D9() throws {
        for item in try payload(real).install {
            #expect(!item.dest.lowercased().contains("d3d9"))
        }
    }

    /// Absent from every bundle published so far, and that must decode.
    @Test func aManifestWithoutOneStillReads() throws {
        let manifest = try JSONDecoder().decode(
            MGVFManifest.self,
            from: Data(#"{"schema":3,"version":"v4.11.2","commit":"abc","games":[]}"#.utf8))
        #expect(manifest.engine == nil)
        #expect(manifest.isSupported)
    }
}
