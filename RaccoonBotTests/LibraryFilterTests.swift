//
//  LibraryFilterTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
import AppKit
@testable import RaccoonBot

/// Narrowing the library: by store, by platform, and by what is typed.
@MainActor
struct LibraryFilterTests {

    private func game(_ name: String, store: Store?, windows: Bool = true, mac: Bool = false) -> Game {
        var g = Game(from: Game.steamEmptyGame, id: "id-\(name)", isNative: mac && !windows,
                     downloadProgress: 100, isInstalled: true, appNames: [])
        g.name = name
        g.store = store
        g.platforms = Platforms(windows: windows, mac: mac, linux: false)
        return g
    }

    private func owned(_ name: String, store: Store, platforms: Set<String> = ["windows"]) -> OwnedGame {
        OwnedGame(appID: store == .epic ? "epic:ns:it:\(name)" : name, name: name,
                  platforms: platforms, lastPlayed: nil, playtimeMinutes: nil,
                  coverURL: nil, store: store)
    }

    private func globals() -> LibraryPageGlobals {
        let g = LibraryPageGlobals()
        g.games = [game("Steam One", store: nil), game("Steam Two", store: .steam)]
        g.epicGames = [game("Epic One", store: .epic)]
        g.ownedGames = [owned("Steam Owned", store: .steam)]
        g.epicOwnedGames = [owned("Epic Owned", store: .epic)]
        return g
    }

    // MARK: the store filter

    @Test func noStoreChosenShowsEveryStore() {
        let g = globals()
        #expect(g.filteredGames.count == 3)
        #expect(g.filteredOwnedGames.count == 2)
    }

    @Test func choosingOneStoreShowsOnlyIt() {
        let g = globals()
        g.storeFilter = [.epic]
        #expect(g.filteredGames.map(\.name) == ["Epic One"])
        #expect(g.filteredOwnedGames.map(\.displayName) == ["Epic Owned"])
        g.storeFilter = [.steam]
        #expect(g.filteredGames.map(\.name).sorted() == ["Steam One", "Steam Two"])
        #expect(g.filteredOwnedGames.map(\.displayName) == ["Steam Owned"])
    }

    /// A card written before the store field existed carries nil, and nil is
    /// Steam. Filtering to Steam must not drop it.
    @Test func aCardWithNoStoreIsSteams() {
        let g = globals()
        g.storeFilter = [.steam]
        #expect(g.filteredGames.contains { $0.name == "Steam One" }, "nil means Steam")
        g.storeFilter = [.epic]
        #expect(!g.filteredGames.contains { $0.name == "Steam One" })
    }

    @Test func choosingBothIsTheSameAsChoosingNeither() {
        let g = globals()
        g.storeFilter = [.steam, .epic]
        #expect(g.filteredGames.count == 3)
    }

    /// The list view goes through rows, which carry the store on the row.
    @Test func theListNarrowsByStoreToo() {
        let g = globals()
        g.tab = .all
        #expect(g.rows.count == 5)
        g.storeFilter = [.epic]
        #expect(g.rows.map(\.name).sorted() == ["Epic One", "Epic Owned"])
    }

    // MARK: the defect this uncovered

    /// The grid computed the platform filter and then reassigned the list it
    /// had just narrowed, so filtering by platform did nothing there while
    /// working in the list view.
    @Test func theGridNarrowsByPlatform() {
        let g = LibraryPageGlobals()
        g.games = [game("Windows Only", store: .steam, windows: true, mac: false),
                   game("Mac Only", store: .steam, windows: false, mac: true)]
        g.platformFilter = ["macos"]
        #expect(g.filteredGames.map(\.name) == ["Mac Only"])
    }

    /// And the two narrow together rather than one replacing the other.
    @Test func storeAndPlatformNarrowTogether() {
        let g = LibraryPageGlobals()
        g.games = [game("Steam Mac", store: .steam, windows: false, mac: true)]
        g.epicGames = [game("Epic Mac", store: .epic, windows: false, mac: true),
                       game("Epic Windows", store: .epic, windows: true, mac: false)]
        g.storeFilter = [.epic]
        g.platformFilter = ["macos"]
        #expect(g.filteredGames.map(\.name) == ["Epic Mac"])
    }

    @Test func searchStillNarrowsWhatTheFiltersLeft() {
        let g = globals()
        g.storeFilter = [.steam]
        g.filter = "two"
        #expect(g.filteredGames.map(\.name) == ["Steam Two"])
        g.filter = "ep"          // under three characters is not a search
        #expect(g.filteredGames.count == 2)
    }

    // MARK: the other defect

    /// Epic's owned titles were read, counted and then drawn by nothing:
    /// everything that displays or counts read `ownedGames`, which is Steam's
    /// alone, while `allOwnedGames` reached one isEmpty check.
    @Test func theNotInstalledTabCountsEveryStore() {
        let g = globals()
        g.tab = .notInstalled
        #expect(g.tabTotal == 2)
        #expect(g.rows.map(\.name).sorted() == ["Epic Owned", "Steam Owned"])
    }

    // MARK: the toolbar's glyphs

    /// The badge draws these by name; a name this system does not have draws
    /// nothing at all, silently.
    @Test func everySymbolTheStoreFilterDrawsExists() {
        for name in ["storefront", "storefront.fill"] + Store.allCases.map(\.systemSymbol) {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                    Comment(rawValue: name))
        }
    }
}
