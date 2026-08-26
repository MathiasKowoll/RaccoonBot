//
//  SteamStoreTests.swift
//  RaccoonBotTests
//
//  The adapter that lets this client read Valve instead of the proxy.
//
//  Every shape asserted here was observed on store.steampowered.com, not
//  imagined: the app ids are in the comments so a failure can be re-checked.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct SteamStoreEnvelopeTests {

    private func data(_ s: String) -> Data { s.data(using: .utf8)! }

    @Test func unwrapsTheAppIdKeyedEnvelope() throws {
        // Valve keys by app id and wraps in success/data. The client's own type
        // expects {"data":[…]}, so without this every record fails on the first
        // key with keyNotFound("data").
        let payload = try SteamStore.unwrap(data(#"{"220":{"success":true,"data":{"name":"Half-Life 2"}}}"#),
                                            appID: "220")
        #expect(payload?["name"] as? String == "Half-Life 2")
    }

    @Test func treatsSuccessFalseAsAnAnswerNotAFailure() throws {
        // Observed live on app id 12750 (GRID), twice, minutes apart: the game
        // is installed and Steam no longer has a store page for it. That is a
        // fact to remember, not an error to retry forever.
        #expect(try SteamStore.unwrap(data(#"{"12750":{"success":false}}"#), appID: "12750") == nil)
    }

    @Test func reportsSomethingThatIsNotAStoreAnswerAtAll() {
        #expect(throws: SteamStoreError.self) {
            _ = try SteamStore.unwrap(self.data(#"{"message":"nope"}"#), appID: "220")
        }
    }
}

struct SteamStoreNormalisationTests {

    @Test func acceptsRequiredAgeInBothDirections() {
        // Measured: int 0 for 42680 and 220, string "17" for 1174180. The same
        // field, the same day. A one-way int->string cast would be wrong half
        // the time, so both are accepted and the string form is kept.
        #expect(SteamStore.normalise(["required_age": 0])["required_age"] as? String == "0")
        #expect(SteamStore.normalise(["required_age": "17"])["required_age"] as? String == "17")
    }

    @Test func dropsTheEmptyArrayValveSendsForAnUnsupportedPlatform() {
        // mac_requirements comes back as [] rather than an object for a title
        // with no mac build. Requirements cannot decode an array.
        let out = SteamStore.normalise(["mac_requirements": [], "linux_requirements": []])
        #expect(out["mac_requirements"] == nil)
        #expect(out["linux_requirements"] == nil)
    }

    @Test func stringifiesDisplayTypeInsidePackageGroups() {
        let out = SteamStore.normalise(["package_groups": [["display_type": 0, "name": "default"]]])
        let groups = out["package_groups"] as? [[String: Any]]
        #expect(groups?.first?["display_type"] as? String == "0")
    }

    @Test func rendersTheHtmlTheProxyUsedToRender() {
        // 0 of the 420 records the proxy cached carried a single tag, while the
        // live endpoint returns 32 of them for app id 220 alone. Nothing
        // downstream strips HTML: GameDetailView prints the string as-is.
        let out = SteamStore.normalise([
            "detailed_description": "<p class=\"bb_paragraph\">Hello <strong>world</strong></p><ul><li>one</li><li>two</li></ul>"
        ])
        let text = out["detailed_description"] as? String ?? ""
        #expect(!text.contains("<"))
        #expect(text.contains("Hello world"))
        #expect(text.contains("- one"))
        #expect(text.contains("- two"))
    }
}

struct SteamStorePlainTextTests {

    @Test func turnsListsIntoLinesAndBreaksIntoNewlines() {
        #expect(SteamStore.plainText(from: "a<br>b") == "a\nb")
        #expect(SteamStore.plainText(from: "<li>x</li>") == "- x")
    }

    @Test func decodesTheEntitiesValveEscapes() {
        #expect(SteamStore.plainText(from: "Tom &amp; Jerry") == "Tom & Jerry")
        #expect(SteamStore.plainText(from: "&quot;quoted&quot;") == "\"quoted\"")
        #expect(SteamStore.plainText(from: "it&#39;s") == "it's")
    }

    @Test func doesNotLeaveTheBlankLinesTagRemovalCreates() {
        let text = SteamStore.plainText(from: "<p>a</p><p></p><p></p><p>b</p>")
        #expect(!text.contains("\n\n\n"))
    }

    @Test func leavesPlainTextAlone() {
        // The 420 already-rendered records must survive a second pass
        // unchanged, because they stay in the cache alongside new ones.
        let already = "The best-selling first person action series of all-time returns."
        #expect(SteamStore.plainText(from: already) == already)
    }
}
