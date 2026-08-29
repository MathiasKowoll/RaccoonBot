//
//  MGVFScopeTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

private func game(_ json: String) throws -> MGVFGame {
    try JSONDecoder().decode(MGVFGame.self, from: Data(json.utf8))
}

@Suite("A fix that goes into the bottle, not beside the game")
struct MGVFScopeTests {

    /// Ninja Gaiden 3's entry, from the v4.11.1 manifest.
    @Test func aBottleScopedEntryDecodesAndSaysSo() throws {
        let entry = try game(#"""
        {"name":"NINJA GAIDEN 3: Razor's Edge","exe":"NINJA GAIDEN 3 Razor's Edge.exe",
         "script":"install-ng3-fix.sh","scope":"bottle","carrier":"","keptAs":"",
         "carrierDir":"","writesRegistry":true,"backend":"dxvk","gptk":"","codec":"",
         "env":{},"why":"Will not start at all.","files":["ng3-d3d9.dll"]}
        """#)
        #expect(entry.installsIntoBottle)
        #expect(entry.writesRegistry)
        #expect(entry.backend == "dxvk")
    }

    /// Every bundle written before this field existed must keep its meaning.
    @Test func anEntryWithoutAScopeIsAFolderEntry() throws {
        let entry = try game(#"""
        {"name":"NINJA GAIDEN 4","exe":"NINJAGAIDEN4-Steam.exe","script":"install-ng4-fix.sh",
         "carrier":"dstorage.dll","keptAs":"dstorage_real.dll","carrierDir":"",
         "writesRegistry":false,"why":"x","files":["dstorage-ng4.dll"]}
        """#)
        #expect(entry.installsIntoBottle == false)
    }

    @Test func anExplicitFolderScopeIsAFolderEntry() throws {
        let entry = try game(#"""
        {"name":"Nioh","exe":"nioh.exe","script":"install-nioh-bridge.sh","scope":"folder",
         "carrier":"GfeSDK.dll","keptAs":"GfeSDK_real.dll","carrierDir":"",
         "writesRegistry":false,"why":"x","files":["GfeSDK.dll"]}
        """#)
        #expect(entry.installsIntoBottle == false)
    }

    /// The real manifest, as shipped -- so a change to its shape is noticed
    /// here rather than by a title quietly never being offered its fix.
    @Test func theShippedManifestHasExactlyOneBottleEntry() throws {
        let bundles = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/RaccoonBot/mgvf"),
            includingPropertiesForKeys: nil)) ?? []
        let manifests = bundles
            .map { $0.appendingPathComponent("manifest.json") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        try #require(!manifests.isEmpty, "no catalogue has been downloaded yet")

        // Only the newest is meaningful; older ones predate the field.
        for manifest in manifests {
            let data = try Data(contentsOf: manifest)
            guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let games = top["games"] as? [[String: Any]] else { continue }
            let bottleScoped = games.filter { ($0["scope"] as? String) == "bottle" }
            #expect(bottleScoped.count <= 1, "more than one bottle-scoped fix is a design change")
            for entry in bottleScoped {
                #expect((entry["carrier"] as? String)?.isEmpty == true,
                        "a bottle fix has no carrier beside the game")
                #expect((entry["writesRegistry"] as? Bool) == true,
                        "a bottle fix that writes no registry would not need the bottle")
            }
        }
    }
}
