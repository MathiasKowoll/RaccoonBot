//
//  StoreActionsTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Who gets asked to remove a game, and when nobody can be.
@MainActor
struct UninstallTests {

    /// `steamAppID` is a `let` on `SteamGame`, so a title with a specific one
    /// is built fresh rather than mutated from a template.
    private func steamGame(_ appID: Int) -> Game {
        let blank = SteamGame(type: "game", name: "A Game", steamAppID: appID, requiredAge: "0",
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

    @Test func aSteamTitleIsUninstalledBySteam() {
        #expect(Uninstall.route(for: steamGame(220)) == .steam(appID: "220"))
    }

    /// The store field was added with the second store; every card written
    /// before it carries nil, and nil is Steam.
    @Test func aCardFromBeforeTheStoreFieldIsStillSteams() {
        var g = steamGame(400)
        g.store = nil
        #expect(Uninstall.route(for: g) == .steam(appID: "400"))
    }

    /// Epic has no uninstall command at all -- `?action=uninstall` is
    /// answered "Was unable to find URI Handler" -- so the route is its
    /// Library, where the user presses Uninstall on the card.
    @Test func anEpicTitleGoesToTheLauncherSLibrary() {
        var g = steamGame(0)
        g.store = .epic
        #expect(Uninstall.route(for: g) == .epic(uri: "com.epicgames.launcher://store/library"))
    }

    /// Steam's command takes files away the moment it is sent, so it is asked
    /// about first. Epic's only opens a window, and Epic confirms inside it.
    @Test func onlyTheRouteThatRemovesSomethingAsksFirst() {
        #expect(Uninstall.needsConfirmation(.steam(appID: "220")))
        #expect(!Uninstall.needsConfirmation(.epic(uri: Uninstall.epicLibraryURI)))
    }

    /// Added by hand, never installed by Steam: `steam://uninstall/0` would
    /// open a dialog about a game the client has never heard of.
    @Test func aTitleWithNoSteamIDHasNoRoute() {
        var g = steamGame(0)
        g.store = .steam
        #expect(Uninstall.route(for: g) == nil)
    }
}


/// Which client is asked to install, and where.
@MainActor
struct InstallRouteTests {

    private func owned(_ appID: String, store: Store) -> OwnedGame {
        OwnedGame(appID: appID, name: "A Game", platforms: ["windows"], lastPlayed: nil,
                  playtimeMinutes: nil, coverURL: nil, store: store)
    }

    /// The one that was wrong: an Epic title with no macOS build resolved to
    /// `toMac: false` and fell through to Steam, which cannot read an Epic id.
    @Test func anEpicTitleNeverGoesToSteam() {
        let game = owned("epic:ns:it:app", store: .epic)
        #expect(Install.route(for: game, toMac: false)
                == .epicInBottle(uri: "com.epicgames.launcher://apps/ns%3Ait%3Aapp?action=install"))
        #expect(Install.route(for: game, toMac: true)
                == .epicInBottle(uri: "com.epicgames.launcher://apps/ns%3Ait%3Aapp?action=install"))
    }

    /// A launch resolves from the AppName alone; an install was only ever
    /// measured with the full triple, so a partial id yields no URI and the
    /// launcher is opened instead of being sent a request nothing verified.
    @Test func anEpicIDMissingItsCatalogueItemHasNoInstallURI() {
        #expect(Install.route(for: owned("epic:::app", store: .epic), toMac: false)
                == .epicInBottle(uri: nil))
    }

    @Test func aSteamTitleGoesToTheBottleOrToTheMac() {
        let game = owned("220", store: .steam)
        #expect(Install.route(for: game, toMac: false) == .steamInBottle(appID: "220"))
        #expect(Install.route(for: game, toMac: true) == .steamOnMac(appID: "220"))
    }
}
