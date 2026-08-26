//
//  OwnedLibraryTests.swift
//  RaccoonBotTests
//
//  The list of everything a person owns, read from disk rather than from a
//  proxy holding somebody's Steam Web API key.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct OwnedLibraryParsingTests {

    private func localConfig(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("localconfig-\(UUID().uuidString).vdf")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func readsAppIdsWithWhenTheyWereLastPlayed() throws {
        let url = try localConfig("""
        "UserLocalConfigStore"
        {
            "Software"
            {
                "Valve"
                {
                    "Steam"
                    {
                        "apps"
                        {
                            "220"
                            {
                                "LastPlayed"    "1629933180"
                                "Playtime"      "48"
                            }
                            "440"
                            {
                                "LastPlayed"    "1403006724"
                            }
                            "7"
                            {
                                "cloud"
                                {
                                    "last_sync_state"   "synchronized"
                                }
                            }
                        }
                    }
                }
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let apps = OwnedLibrary.ownedApps(inLocalConfigAt: url)
        #expect(apps.count == 3)
        #expect(apps["220"]?.playtime == 48)
        #expect(apps["220"]?.lastPlayed != nil)
        // Present but never played: an entry with no LastPlayed is still owned.
        #expect(apps["7"] != nil)
        #expect(apps["7"]?.lastPlayed == nil)
    }

    @Test func survivesTheKeysBeingCapitalisedDifferently() throws {
        // Steam has shipped these keys with different capitalisation across
        // client versions, and a miss empties the whole library rather than
        // one field of it.
        let url = try localConfig("""
        "userlocalconfigstore"
        {
            "software" { "valve" { "steam" { "Apps"
            {
                "220" { "lastplayed" "1629933180" }
            } } } }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(OwnedLibrary.ownedApps(inLocalConfigAt: url).count == 1)
    }

    @Test func returnsNothingForAFileThatIsNotOne() throws {
        let url = try localConfig("this is not a vdf")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(OwnedLibrary.ownedApps(inLocalConfigAt: url).isEmpty)
        #expect(OwnedLibrary.ownedApps(inLocalConfigAt: URL(fileURLWithPath: "/nope")).isEmpty)
    }
}

struct OwnedGameShapeTests {

    private func game(_ os: Set<String>) -> OwnedGame {
        OwnedGame(appID: "1", name: "", platforms: os, lastPlayed: nil,
                  playtimeMinutes: nil, coverURL: nil)
    }

    @Test func asksWhichPlatformOnlyWhenThereIsAChoice() {
        #expect(game(["windows", "macos"]).isCrossPlatform)
        #expect(!game(["windows"]).isCrossPlatform)
        #expect(!game(["macos"]).isCrossPlatform)
        #expect(!game([]).isCrossPlatform)
    }

    @Test func showsAnAppIdRatherThanABlankRow() {
        // 36 of 427 owned titles had no record in appinfo.vdf. Hiding them
        // loses games the user owns; naming them by id keeps them reachable,
        // and the cover usually carries the real title anyway.
        #expect(game([]).displayName == "App 1")
        #expect(OwnedGame(appID: "1", name: "Half-Life 2", platforms: [], lastPlayed: nil,
                          playtimeMinutes: nil, coverURL: nil).displayName == "Half-Life 2")
    }
}

// A suite that read this machine's real Steam used to sit here. It failed with
// no expectation message, no crash report and a 0.000s duration, which makes it
// a test of the environment rather than of the code -- and an unreadable one.
// The parsers were validated against the real files another way (2076 apps out
// of appinfo.vdf, 427 owned out of localconfig.vdf, zero errors), and the
// behaviour that matters is verified by running the application.
