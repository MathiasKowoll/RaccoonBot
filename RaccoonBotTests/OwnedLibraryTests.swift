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

    @Test func stillHasAnIdBasedNameAsALastResort() {
        // Entries appinfo cannot name are now dropped before they become an
        // OwnedGame -- a card reading "App 1139900" tells nobody anything --
        // but the fallback stays, because a name arriving empty from somewhere
        // else should degrade rather than render a blank row.
        #expect(game([]).displayName == "App 1")
        #expect(OwnedGame(appID: "1", name: "Half-Life 2", platforms: [], lastPlayed: nil,
                          playtimeMinutes: nil, coverURL: nil).displayName == "Half-Life 2")
    }
}

/// Reads this machine's actual Steam. Skipped where there is none.
///
/// An earlier version of this suite failed with no message and a 0.000s
/// duration, and I removed it as environment-coupled. That was wrong: it was
/// reporting a crash inside parseVDFToDict on a real localconfig.vdf, which is
/// exactly the bug it existed to catch, and removing it meant shipping the
/// crash to the application instead. Restored, and split so a failure says
/// which file it was reading.
struct OwnedLibraryOnThisMachineTests {

    @Test func readsTheBinaryAppCache() {
        guard let steam = OwnedLibrary.steamRoots().first else { return }
        let url = AppInfoVDF.url(inSteamAt: steam)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        let apps = AppInfoVDF.read(at: url)
        #expect(apps.count > 100, "parsed only \(apps.count) apps out of a real appinfo.vdf")
        #expect(apps.values.contains { $0.isGame })
    }

    @Test func readsTheOwnedListWithoutHangingOrCrashing() {
        // The regression. parseVDFToDict builds the whole file into nested
        // dictionaries and never returns on this one -- a string token followed
        // by a closing brace advances no pointer -- besides calling fatalError()
        // in its lexer. Neither belongs on a file Steam writes.
        guard let steam = OwnedLibrary.steamRoots().first else { return }
        guard let config = OwnedLibrary.localConfigs(inSteamAt: steam).first else { return }
        let owned = OwnedLibrary.ownedApps(inLocalConfigAt: config)
        #expect(owned.count > 10, "parsed only \(owned.count) owned titles")
        #expect(owned.values.contains { $0.lastPlayed != nil })
    }
}

struct LocalConfigScannerTests {

    @Test func readsFieldsOnTheAppAndNotFromInsideItsChildren() {
        // "cloud" and friends are nested one deeper and carry their own keys.
        // Reading at any depth would attribute a child's value to the game.
        let apps = OwnedLibrary.ownedApps(inLocalConfig: """
        "UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps"
        {
            "220"
            {
                "LastPlayed"    "1629933180"
                "Playtime"      "48"
                "cloud"
                {
                    "LastPlayed"    "1"
                }
            }
            "7"
            {
                "cloud" { "last_sync_state" "synchronized" }
            }
        } } } } }
        """)
        #expect(apps.count == 2)
        #expect(apps["220"]?.playtime == 48)
        #expect(apps["220"]?.lastPlayed == Date(timeIntervalSince1970: 1629933180))
        #expect(apps["7"]?.lastPlayed == nil)
    }

    @Test func doesNotSpinOnAShapeItDoesNotExpect() {
        // The failure mode being replaced: upstream's parser loops forever when
        // a string token is followed by a closing brace. This must return.
        _ = OwnedLibrary.ownedApps(inLocalConfig: #""apps" { "220" "}"#)
        _ = OwnedLibrary.ownedApps(inLocalConfig: #""apps" {"#)
        _ = OwnedLibrary.ownedApps(inLocalConfig: "")
        _ = OwnedLibrary.ownedApps(inLocalConfig: #""apps" { "220" { "LastPlayed" "#)
    }

    @Test func findsNothingWhenThereIsNoAppsBlock() {
        #expect(OwnedLibrary.ownedApps(inLocalConfig: #""Software" { "Valve" { } }"#).isEmpty)
    }
}
