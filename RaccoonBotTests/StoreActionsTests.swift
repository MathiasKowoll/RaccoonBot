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

    /// A native title was installed by the Mac's Steam and lives outside the
    /// bottle. Asking the bottle's Steam to remove it is, at best, a dialog
    /// about a game it does not have -- and where the same appid is installed
    /// on both sides, it deletes the copy the user did not choose.
    @Test func aNativeSteamTitleIsUninstalledByTheMacsSteam() {
        let blank = SteamGame(type: "game", name: "A Game", steamAppID: 620, requiredAge: "0",
                              isFree: false, controllerSupport: nil, dlc: nil,
                              detailedDescription: "", aboutTheGame: "", shortDescription: "",
                              supportedLanguages: nil, headerImage: "", capsuleImage: "",
                              capsuleImageV5: nil, website: nil, pcRequirements: nil,
                              macRequirements: nil, linuxRequirements: nil, legalNotice: nil,
                              developers: nil, publishers: nil, priceOverview: nil, packages: nil,
                              packageGroups: nil, platforms: Platforms(windows: false, mac: true, linux: false),
                              metacritic: nil, categories: nil, genres: nil, screenshots: nil,
                              movies: nil, recommendations: nil, achievements: nil,
                              releaseDate: ReleaseDate(comingSoon: false, date: ""), supportInfo: nil,
                              background: nil, backgroundRaw: nil, contentDescriptors: nil, ratings: nil)
        let native = Game(from: blank, id: "id-620", isNative: true,
                          downloadProgress: 100, isInstalled: true, appNames: [])
        #expect(Uninstall.route(for: native) == .steamOnMac(appID: "620"))
        #expect(Uninstall.route(for: steamGame(620)) == .steam(appID: "620"))
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


/// When the Epic launcher may be handed an install, and when doing so would
/// only earn the user an II-E1003.
@MainActor
struct EpicReadinessTests {

    private func log(header: String, ready: Bool) -> String {
        var text = header + "\nAppSettings: Version: 20.2.7-0+UE5\n"
        text += "[2026.09.03-20.24.56:841][  5]LogSysTrayUserPresentation: "
        text += "FSysTrayUserPresentationImpl::AddSocialApplicationViewModel called for product with namespace poodle, apps 29\n"
        if ready {
            text += "[2026.09.03-20.25.04:465][212]LogSysTrayUserPresentation: "
            text += "FSysTrayUserPresentationImpl::AddSocialApplicationViewModel called for product with namespace EpicGamesLauncher, apps 1\n"
        }
        return text
    }

    @Test func theMarkerMeansReady() {
        #expect(EpicReadiness.verdict(logText: log(header: "Log file open, 09/03/26 16:24:53", ready: true),
                                      previousHeader: "Log file open, 09/03/26 16:20:52") == .ready)
    }

    /// The other namespaces fire at 3.7s, a second before the failures. Matching
    /// the bare call would deliver the install into exactly the window this
    /// exists to avoid.
    @Test func anotherNamespaceIsNotTheMarker() {
        #expect(EpicReadiness.verdict(logText: log(header: "Log file open, 09/03/26 16:24:53", ready: false),
                                      previousHeader: "Log file open, 09/03/26 16:20:52") == .notYet)
    }

    /// The one that would silently reintroduce the bug: the launcher has not
    /// rotated its log yet, so what is on disk is the PREVIOUS session -- which
    /// ended with the marker in it. Reading that as readiness would hand the
    /// install to a launcher one second old.
    @Test func thePreviousSessionsMarkerDoesNotCount() {
        let header = "Log file open, 09/03/26 16:20:52"
        #expect(EpicReadiness.verdict(logText: log(header: header, ready: true),
                                      previousHeader: header) == .notYet)
    }

    /// No log at all, and a log with nothing in it: both are "not yet", never a
    /// crash and never a green light.
    @Test func nothingToReadIsNotReady() {
        #expect(EpicReadiness.verdict(logText: nil, previousHeader: nil) == .notYet)
        #expect(EpicReadiness.verdict(logText: "", previousHeader: nil) == .notYet)
        #expect(EpicReadiness.verdict(logText: "\n\n", previousHeader: nil) == .notYet)
    }

    /// A first run, with no previous log to compare against, still needs the
    /// marker before it says yes.
    @Test func withNoPreviousLogTheMarkerStillDecides() {
        #expect(EpicReadiness.verdict(logText: log(header: "Log file open, 09/03/26 16:24:53", ready: false),
                                      previousHeader: nil) == .notYet)
        #expect(EpicReadiness.verdict(logText: log(header: "Log file open, 09/03/26 16:24:53", ready: true),
                                      previousHeader: nil) == .ready)
    }

    @Test func theHeaderIsTheFirstLineThatHasSomethingInIt() {
        #expect(EpicReadiness.header(of: "\n\nLog file open, 09/03/26 16:24:53\nmore\n")
                == "Log file open, 09/03/26 16:24:53")
        #expect(EpicReadiness.header(of: "") == nil)
    }

    /// The wait ends rather than hanging when the launcher never says anything:
    /// two sessions in eleven never emitted the marker, and a late install is
    /// better than none.
    @Test func theWaitGivesUpAndLetsTheCallerDeliver() async {
        let missing = URL(fileURLWithPath: "/nonexistent/EpicGamesLauncher.log")
        let answer = await EpicReadiness.waitUntilInstallable(log: missing, after: nil,
                                                             deadline: 0.3, poll: 0.05)
        #expect(answer == false)
    }
}


/// An Epic title has to be findable by the id its card carries.
@MainActor
struct EpicMetaLookupTests {

    /// The card's id is the launcher's triple; the meta's own `id` is the
    /// library folder plus that, so the two never matched and every Epic title
    /// was invisible -- no video-fix badge, no launch gate, and "Could not work
    /// out where this game is installed" on every Epic options sheet.
    @Test func anEpicTitleIsFoundByItsTriple() {
        let triple = "epic:ns:item:AppName"
        let meta = GamesMeta(appid: triple, installdir: "AlanWake2",
                             gameURL: URL(fileURLWithPath: "/Volumes/X/Games/AlanWake2"),
                             isNative: false,
                             libraryFolder: URL(fileURLWithPath: "/Volumes/X/Games"),
                             bytesDownloaded: "0", BytesTodownload: "0", appNames: [])
        #expect(meta.id != triple, "the premise: the ids genuinely differ")
        #expect(getMeta([meta], byID: triple)?.appid == triple)
    }

    /// The exact id still wins, and a Steam lookup is untouched: the fallback
    /// only answers for an id that begins with "epic:", which digits cannot.
    @Test func aSteamLookupIsUnaffected() {
        let steam = GamesMeta(appid: "220", installdir: "Half-Life 2",
                              bytesDownloaded: "0", BytesTodownload: "0")
        #expect(getMeta([steam], byID: steam.id)?.appid == "220")
        #expect(getMeta([steam], byID: "220") == nil)
    }
}

/// The page for an Epic title nobody has installed here.
@MainActor
struct EpicDetailTests {

    /// With no bottle and no catalogue there is still a card, because the
    /// alternative shipped for a day: the click did nothing at all.
    @Test func withoutACatalogueTheOwnedListsOwnNameIsEnough() async {
        let owned = OwnedGame(appID: "epic:::AppName", name: "Some Game",
                              platforms: ["windows"], lastPlayed: nil, playtimeMinutes: nil,
                              coverURL: URL(string: "https://example.invalid/cover.png"), store: .epic)
        let game = await EpicDetail.game(for: owned, bottleDirectory: nil)
        #expect(game.name == "Some Game")
        #expect(game.store == .epic)
        #expect(game.id == "epic:::AppName")
        #expect(game.isInstalled == false)
    }
}
