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

/// An installed title must never also read as owned-and-not-installed --
/// not in the not-installed tab, and not folded into "All".
@MainActor
struct InstalledExcludesOwnedTests {

    /// `steamAppID` is a `let` on `SteamGame`, so a title with a specific one
    /// is built fresh rather than mutated from a template.
    private func steamGame(_ appID: Int, name: String) -> Game {
        let blank = SteamGame(type: "game", name: name, steamAppID: appID, requiredAge: "0",
                              isFree: false, controllerSupport: nil, dlc: nil,
                              detailedDescription: "", aboutTheGame: "", shortDescription: "",
                              supportedLanguages: nil, headerImage: "", capsuleImage: "",
                              capsuleImageV5: nil, website: nil, pcRequirements: nil,
                              macRequirements: nil, linuxRequirements: nil, legalNotice: nil,
                              developers: nil, publishers: nil, priceOverview: nil, packages: nil,
                              packageGroups: nil, platforms: Platforms(windows: true, mac: false, linux: false),
                              metacritic: nil, categories: nil, genres: nil, screenshots: nil,
                              movies: nil, recommendations: nil, achievements: nil,
                              releaseDate: ReleaseDate(comingSoon: false, date: ""), supportInfo: nil,
                              background: nil, backgroundRaw: nil, contentDescriptors: nil, ratings: nil)
        return Game(from: blank, id: "id-\(appID)", isNative: false,
                   downloadProgress: 100, isInstalled: true, appNames: [])
    }

    private func steamMeta(_ appID: Int) -> GamesMeta {
        GamesMeta(appid: String(appID), installdir: "dir\(appID)", bytesDownloaded: "0", BytesTodownload: "0")
    }

    private func epicGame(triple: String, name: String) -> Game {
        var g = Game(from: Game.steamEmptyGame, id: triple, isNative: false,
                     downloadProgress: 100, isInstalled: true, appNames: [])
        g.name = name
        g.store = .epic
        g.platforms = Platforms(windows: true, mac: false, linux: false)
        return g
    }

    /// Steam's own owned-not-installed list is computed once, behind a flag
    /// nothing resets when a title gets installed afterwards (GamesList.swift,
    /// `ownedLoaded`). Reproduced directly here, without waiting for that
    /// timing: an OwnedGame is put in `ownedGames` for a title that is, at
    /// the same time, in `gamesMeta` as installed -- exactly what a stale
    /// scan leaves behind.
    @Test func aSteamTitleInstalledAfterTheOwnedScanIsNotDuplicated() {
        let g = LibraryPageGlobals()
        g.games = [steamGame(1_000_000, name: "Newly Installed")]
        g.gamesMeta = [steamMeta(1_000_000)]
        g.ownedGames = [OwnedGame(appID: "1000000", name: "Newly Installed",
                                  platforms: ["windows"], lastPlayed: nil,
                                  playtimeMinutes: nil, coverURL: nil, store: .steam)]

        #expect(g.allOwnedGames.isEmpty, "installed, so not owned-and-not-installed")

        g.tab = .all
        let matches = g.rows.filter { $0.name == "Newly Installed" }
        #expect(matches.count == 1, "one row, not one per list")
        #expect(matches.first?.isInstalled == true)

        g.tab = .notInstalled
        #expect(g.rows.isEmpty)
        #expect(g.tabTotal == 0)
    }

    /// The same defect, on Epic's side, with the triple id rather than a
    /// numeric appid -- the two owned lists are keyed differently and both
    /// have to be covered.
    @Test func anEpicTitleInstalledAfterTheOwnedScanIsNotDuplicated() {
        let triple = "epic:ns:item:app1"
        let g = LibraryPageGlobals()
        g.epicGames = [epicGame(triple: triple, name: "Epic Newly Installed")]
        g.gamesMeta = [GamesMeta(appid: triple, installdir: "EpicGame", bytesDownloaded: "0", BytesTodownload: "0")]
        g.epicOwnedGames = [OwnedGame(appID: triple, name: "Epic Newly Installed",
                                      platforms: ["windows"], lastPlayed: nil,
                                      playtimeMinutes: nil, coverURL: nil, store: .epic)]

        #expect(g.allOwnedGames.isEmpty)
        g.tab = .all
        #expect(g.rows.filter { $0.name == "Epic Newly Installed" }.count == 1)
    }

    /// The exclusion is by identity, not by wiping the list: a title that
    /// really is not installed keeps showing.
    @Test func aTitleThatIsNotInstalledIsUnaffected() {
        let g = LibraryPageGlobals()
        g.gamesMeta = [steamMeta(1_000_000)]
        g.ownedGames = [
            OwnedGame(appID: "1000000", name: "Installed", platforms: ["windows"], lastPlayed: nil, playtimeMinutes: nil, coverURL: nil, store: .steam),
            OwnedGame(appID: "2000000", name: "Actually Owned", platforms: ["windows"], lastPlayed: nil, playtimeMinutes: nil, coverURL: nil, store: .steam),
        ]
        #expect(g.allOwnedGames.map(\.name) == ["Actually Owned"])
    }

}

/// "All" used to draw two blocks -- every installed card, then every owned
/// card, each in its own visual style and its own sort order -- which is what
/// two lists glued together looks like, because that is what it was. It is
/// one sorted, interleaved list now, and this is that merge, exercised
/// directly rather than through the view it feeds.
@MainActor
struct MixedGridCardTests {

    private func game(_ name: String) -> Game {
        var g = Game(from: Game.steamEmptyGame, id: "g-\(name)", isNative: false,
                     downloadProgress: 100, isInstalled: true, appNames: [])
        g.name = name
        return g
    }

    private func owned(_ name: String) -> OwnedGame {
        OwnedGame(appID: "o-\(name)", name: name, platforms: ["windows"], lastPlayed: nil,
                  playtimeMinutes: nil, coverURL: nil, store: .steam)
    }

    /// The point of the change: installed and owned titles take turns by
    /// name, rather than every installed title first and every owned title
    /// after it.
    @Test func installedAndOwnedInterleaveByName() {
        let cards = GamesList.GridCard.merged(
            installed: [game("Charlie"), game("Alpha")],
            owned: [owned("Bravo"), owned("Delta")])
        #expect(cards.map(\.sortName) == ["Alpha", "Bravo", "Charlie", "Delta"],
                "not [Alpha, Charlie, Bravo, Delta] -- the two lists concatenated and each sorted on its own")
    }

    @Test func eachCardKeepsWhatKindItIs() {
        let cards = GamesList.GridCard.merged(installed: [game("Only Installed")], owned: [owned("Only Owned")])
        guard case .installed(let g) = cards.first(where: { $0.sortName == "Only Installed" })! else {
            Issue.record("installed title lost its kind"); return
        }
        #expect(g.name == "Only Installed")
        guard case .owned(let o) = cards.first(where: { $0.sortName == "Only Owned" })! else {
            Issue.record("owned title lost its kind"); return
        }
        #expect(o.name == "Only Owned")
    }

    @Test func idsAreUniqueAcrossBothKinds() {
        let cards = GamesList.GridCard.merged(
            installed: [game("A"), game("B")],
            owned: [owned("C"), owned("D")])
        #expect(Set(cards.map(\.id)).count == cards.count)
    }

    @Test func emptyEitherSideStillMerges() {
        #expect(GamesList.GridCard.merged(installed: [], owned: [owned("Solo")]).map(\.sortName) == ["Solo"])
        #expect(GamesList.GridCard.merged(installed: [game("Solo")], owned: []).map(\.sortName) == ["Solo"])
        #expect(GamesList.GridCard.merged(installed: [], owned: []).isEmpty)
    }

    /// Case sensitivity must not scatter a shelf that would otherwise read
    /// as alphabetical: an all-caps owned title should not jump ahead of
    /// every lowercase-starting installed one.
    @Test func sortIsCaseInsensitive() {
        let cards = GamesList.GridCard.merged(installed: [game("banana")], owned: [owned("Apple")])
        #expect(cards.map(\.sortName) == ["Apple", "banana"])
    }
}
