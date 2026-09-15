//
//  SessionCloseTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Serialised because the launch generation is a process-wide singleton; each
/// case works in a bottle of its own.
@Suite("Closing a session on purpose", .serialized)
struct SessionCloseTests {

    /// A bottle nothing else touches.
    private func bottle(_ name: String) -> String {
        "file:///Users/someone/Library/Application%20Support/RaccoonBot/CXPBottles/\(name)-\(UUID().uuidString)/"
    }

    private final class Calls {
        var taken: [String] = []
        /// The bottle's generation when a launch read its awaited starts.
        var generationAtTheRead: Int?
        func record(_ name: String) { taken.append(name) }
    }

    private func process(_ pid: pid_t, _ name: String) -> BottleProcesses.Running {
        BottleProcesses.Running(pid: pid, name: name)
    }

    /// Names that are not games, the way `notGames` answers for a bottle with
    /// Steam and the Epic launcher in it.
    private let notGames: Set<String> = BottleProcesses.wineFurniture.union([
        "steam.exe", "steamwebhelper.exe", "gameoverlayui64.exe",
        "epicgameslauncher.exe", "epicwebhelper.exe", "eosoverlayrenderer-win64-shipping.exe",
    ])

    // MARK: - Which clients a bottle holds

    @Test func theClientsAreReadFromTheNames() {
        #expect(StoreClients(names: ["wineserver", "Steam.exe", "steamwebhelper.exe", "EpicGamesLauncher.exe", "EpicWebHelper.exe"])
                == StoreClients(steam: true, epicLauncher: true, waitedFor: ["epic", "steam"]))
        // Steam itself has gone and its helper has not: waited for, never asked.
        let helper = StoreClients(names: ["steamwebhelper.exe", "services.exe"])
        #expect(helper.steam == false)
        #expect(helper.waitedFor == ["steam"])
        #expect(StoreClients(names: ["services.exe"]).closeBottleClients == ["steam"])
    }

    /// Steam itself, never a process that shares its prefix: every one of
    /// these can be in a bottle Steam has left, and "Steam.exe -shutdown"
    /// sent on its account would start a Steam.
    @Test func onlySteamItselfIsSteam() {
        let leftBehind = [process(1, "wineserver"), process(31, "steamwebhelper.exe"),
                          process(32, "steamerrorreporter64.exe"), process(33, "steamsysinfo.exe")]
        #expect(StoreClients.steams(among: leftBehind).isEmpty)
        #expect(StoreClients.steams(among: leftBehind + [process(30, "Steam.exe")]).map(\.pid) == [30])
        #expect(StoreClients(processes: leftBehind, alreadyAsked: []).steam == false)
    }

    // MARK: - What a launch does with a bottle left open

    @Test func aBottleWithOnlyAStoreInItIsClosed() {
        let scan = [process(1, "wineserver"), process(2, "services.exe"), process(3, "steam.exe"), process(4, "steamwebhelper.exe")]
        #expect(LeftOpenSession.decide(processes: scan, notGames: notGames)
                == .close(StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"])))
    }

    @Test func aBottleWithAGameInItIsLaunchedInto() {
        let scan = [process(1, "wineserver"), process(3, "steam.exe"), process(9, "nioh.exe")]
        #expect(LeftOpenSession.decide(processes: scan, notGames: notGames) == .gameRunning(["nioh.exe"]))
    }

    /// A name nobody listed is a game, as gamesRunning has it -- a fix
    /// installer's reg.exe included, which is the direction that closes
    /// nothing under it.
    @Test func aNameNobodyListedIsAGame() {
        let scan = [process(1, "wineserver"), process(3, "steam.exe"), process(12, "reg.exe")]
        #expect(LeftOpenSession.decide(processes: scan, notGames: notGames) == .gameRunning(["reg.exe"]))
    }

    @Test func noSessionIsNothingToClose() {
        #expect(LeftOpenSession.decide(processes: [], notGames: notGames) == .nothingToClose)
        #expect(LeftOpenSession.decide(processes: [process(1, "wineserver"), process(2, "services.exe")],
                                       notGames: notGames) == .nothingToClose)
        // Outlived its server: an orphan, which clearOrphans deals with.
        #expect(LeftOpenSession.decide(processes: [process(3, "steam.exe")], notGames: notGames) == .nothingToClose)
    }

    /// An engine that names its server for its architecture.
    @Test func aServerIsNeverAGame() {
        let scan = [process(1, "wineserver-x86"), process(3, "steam.exe")]
        #expect(BottleProcesses.games(among: scan, notGames: notGames).isEmpty)
        #expect(LeftOpenSession.decide(processes: scan, notGames: notGames)
                == .close(StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"])))
    }

    /// lsof cuts a name at 31 characters; a known name is compared cut the
    /// same way.
    @Test func aLongNameIsComparedAtLsofsLimit() {
        let cut = String("EOSOverlayRenderer-Win64-Shipping.exe".prefix(BottleProcesses.lsofNameLimit))
        let scan = [process(1, "wineserver"), process(5, "EpicGamesLauncher.exe"), process(6, cut)]
        #expect(LeftOpenSession.decide(processes: scan, notGames: notGames)
                == .close(StoreClients(steam: false, epicLauncher: true, waitedFor: ["epic"])))
    }

    // MARK: - What is not a game, read from a bottle

    private func makeBottle(_ files: [String]) throws -> URL {
        let bottle = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bottle-\(UUID().uuidString)")
        for file in files {
            let url = bottle.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        return bottle
    }

    /// Steam's default library is Steam's own folder, so a title installed
    /// there -- and the installers Steam runs from Steamworks Shared -- are
    /// not Steam's: a launch closes nothing under such a title, and a Stop
    /// ends it first.
    @Test func aTitleInSteamsOwnLibraryIsAGame() throws {
        let steam = "drive_c/Program Files (x86)/Steam/"
        let bottle = try makeBottle([steam + "steam.exe", steam + "bin/cef/cef.win64/steamwebhelper.exe",
                                     steam + "steamapps/common/Nioh/nioh.exe",
                                     steam + "steamapps/common/Steamworks Shared/_CommonRedist/vcredist/2022/VC_redist.x64.exe"])
        defer { try? FileManager.default.removeItem(at: bottle) }
        #expect(BottleProcesses.steamsOwnExecutables(inBottleAt: bottle) == ["steam.exe", "steamwebhelper.exe"])

        let scan = [process(1, "wineserver"), process(3, "steam.exe"), process(9, "nioh.exe")]
        let names = BottleProcesses.notGames(inBottleAt: bottle)
        #expect(LeftOpenSession.decide(processes: scan, notGames: names) == .gameRunning(["nioh.exe"]))
        #expect(SessionStop.condemned(among: scan, notGames: names).map(\.name) == ["nioh.exe"])
    }

    /// A title the Epic launcher installed beside itself is not the
    /// launcher's; Epic Online Services, which carries an .egstore of its own,
    /// still is.
    @Test func aTitleTheEpicLauncherInstalledBesideItIsAGame() throws {
        let epic = "drive_c/Program Files (x86)/Epic Games/"
        let bottle = try makeBottle([epic + "Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe",
                                     epic + "Epic Online Services/service/EpicOnlineServicesHost.exe",
                                     epic + "Epic Online Services/.egstore/service.manifest",
                                     epic + "AlanWake2/AlanWake2.exe",
                                     epic + "AlanWake2/.egstore/4FC854614CB844490C7D97AE630D7FC5.manifest"])
        defer { try? FileManager.default.removeItem(at: bottle) }
        // "c:" the way CrossOver writes it: a relative link.
        try FileManager.default.createDirectory(at: bottle.appendingPathComponent("dosdevices"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: bottle.appendingPathComponent("dosdevices/c:").path,
                                                   withDestinationPath: "../drive_c")
        let manifests = bottle.appendingPathComponent("drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests")
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        try Data(#"{"AppName": "Kaboom", "InstallLocation": "C:\\Program Files (x86)\\Epic Games\\AlanWake2"}"#.utf8)
            .write(to: manifests.appendingPathComponent("2B1BB70440EAD4F57994D18449CB7CA0.item"))

        #expect(BottleProcesses.launchersOwnExecutables(inBottleAt: bottle)
                == ["epicgameslauncher.exe", "epiconlineserviceshost.exe"])
    }

    /// A Stop never asks or ends wine's own -- a fix installer's reg.exe
    /// among them, which a launch does count as a game -- nor Steam, the
    /// launcher, or wine's taskkill.
    @Test func aStopEndsNoneOfWinesOwn() {
        let scan = [process(1, "wineserver"), process(2, "services.exe"), process(3, "steam.exe"),
                    process(4, "EpicGamesLauncher.exe"), process(12, "reg.exe"), process(13, "regedit.exe"),
                    process(14, "cmd.exe"), process(15, "taskkill.exe"), process(40, "nioh.exe")]
        #expect(SessionStop.condemned(among: scan, notGames: notGames).map(\.name) == ["nioh.exe"])
    }

    // MARK: - A Steam already asked to leave

    /// Waited for, not asked again -- by pid and name, and only when every
    /// steam.exe in the bottle was asked.
    @Test func aSteamAlreadyAskedIsNotAskedAgain() {
        let steam = process(30, "steam.exe")
        let scan = [process(1, "wineserver"), steam, process(31, "steamwebhelper.exe")]
        let asked = StoreClients(processes: scan, alreadyAsked: [steam])
        #expect(asked == StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"], steamAlreadyAsked: true))
        #expect(asked.asksSteam == false)
        #expect(asked.closeBottleClients == ["steam"])
        // Another Steam, a second one beside it, or a pid something else held.
        #expect(StoreClients(processes: scan, alreadyAsked: [process(29, "steam.exe")]).asksSteam)
        #expect(StoreClients(processes: scan + [process(33, "steam.exe")], alreadyAsked: [steam]).asksSteam)
        #expect(StoreClients(processes: scan, alreadyAsked: [process(30, "other.exe")]).asksSteam)
        #expect(StoreClients(processes: [process(1, "wineserver")], alreadyAsked: [steam]) == StoreClients(names: ["wineserver"]))
    }

    @Test func aShutdownIsRememberedForAMinuteUnderEitherSpelling() {
        let steamBottle = bottle("Steam")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        SteamShutdowns.shared.record([process(30, "steam.exe")], in: steamBottle, at: t0)
        #expect(SteamShutdowns.shared.askedToLeave(in: String(steamBottle.dropLast()), at: t0.addingTimeInterval(59)).map(\.pid) == [30])
        // Written out rather than read from the constant, so that a Steam
        // asked a minute ago is asked again whatever the constant becomes.
        #expect(SteamShutdowns.shared.askedToLeave(in: steamBottle, at: t0.addingTimeInterval(60)).isEmpty)
        #expect(SteamShutdowns.shared.askedToLeave(in: bottle("Steam"), at: t0).isEmpty)
    }

    @Test @MainActor func aSteamAlreadyLeavingIsNotAskedAgainBeforeALaunch() async throws {
        let calls = Calls()
        #expect(try await closeLeftOpen(StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"]), calls: calls,
                                        clientsAfterTheWaits: StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"],
                                                                           steamAlreadyAsked: true)))
        #expect(calls.taken == ["steam sync", "look", "close steam"])
    }

    // MARK: - A store still starting a title

    @Test func aStartIsAwaitedUntilItsOwnLaunchEndsIt() {
        let steam = bottle("Steam")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let starts = AwaitedTitleStarts.shared
        starts.began(.steam, generation: 3, bottle: steam, until: t0.addingTimeInterval(100))
        #expect(starts.awaited(in: String(steam.dropLast()), at: t0) == [.steam])
        #expect(starts.awaited(in: steam, at: t0.addingTimeInterval(100)).isEmpty)
        starts.ended(.steam, generation: 2, bottle: steam)
        #expect(starts.awaited(in: steam, at: t0) == [.steam], "an earlier launch's end is not this one's")
        starts.ended(.epic, generation: 3, bottle: steam)
        #expect(starts.awaited(in: steam, at: t0) == [.steam])
        starts.ended(.steam, generation: 3, bottle: steam)
        #expect(starts.awaited(in: steam, at: t0).isEmpty)
    }

    @Test func onlyAStoreInTheBottleThatIsStillStartingKeepsItOpen() {
        let steamOnly = StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"])
        let epicOnly = StoreClients(steam: false, epicLauncher: true, waitedFor: ["epic"])
        #expect(LeftOpenSession.storeStillStarting(steamOnly, awaited: [.steam]) == .steam)
        #expect(LeftOpenSession.storeStillStarting(epicOnly, awaited: [.epic]) == .epic)
        #expect(LeftOpenSession.storeStillStarting(epicOnly, awaited: [.steam]) == nil)
        #expect(LeftOpenSession.storeStillStarting(steamOnly, awaited: []) == nil)
    }

    // MARK: - The close, in order

    @MainActor
    private func closeLeftOpen(_ clients: StoreClients, calls: Calls,
                               clientsAfterTheWaits: StoreClients? = nil,
                               unwantedDuring: String? = nil) async throws -> Bool {
        var wanted = true
        func step(_ name: String) {
            calls.record(name)
            if name == unwantedDuring { wanted = false }
        }
        return try await LeftOpenSession.close(
            clients: clients,
            stillWanted: { wanted },
            waitForSteamExitSync: { step("steam sync") },
            waitForEpicExitSync: { step("epic sync") },
            clientsNow: { step("look"); return clientsAfterTheWaits ?? clients },
            quitEpic: { step("quit epic") },
            quitSteam: { step("quit steam") },
            closeBottle: { step("close " + $0.joined(separator: "+")) })
    }

    @Test @MainActor func theSyncsComeBeforeTheClientsAndTheClientsBeforeTheBottle() async throws {
        let steam = Calls()
        #expect(try await closeLeftOpen(StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"]), calls: steam))
        #expect(steam.taken == ["steam sync", "look", "quit steam", "close steam"])

        let both = Calls()
        #expect(try await closeLeftOpen(StoreClients(steam: true, epicLauncher: true, waitedFor: ["epic", "steam"]), calls: both))
        #expect(both.taken == ["steam sync", "epic sync", "look", "quit epic", "quit steam", "close epic+steam"])
    }

    /// Never a Steam that is not running: one that left during the wait is not
    /// asked, and its leftovers are still waited for.
    @Test @MainActor func aClientThatLeftDuringTheWaitIsNotAsked() async throws {
        let calls = Calls()
        #expect(try await closeLeftOpen(StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"]), calls: calls,
                                        clientsAfterTheWaits: StoreClients(steam: false, epicLauncher: false, waitedFor: ["steam"])))
        #expect(calls.taken == ["steam sync", "look", "close steam"])
    }

    /// Stop or Play inside any step: nothing more is asked of anything.
    @Test(arguments: [
        ("steam sync", ["steam sync"]),
        ("epic sync", ["steam sync", "epic sync"]),
        ("look", ["steam sync", "epic sync", "look"]),
        ("quit epic", ["steam sync", "epic sync", "look", "quit epic"]),
        ("quit steam", ["steam sync", "epic sync", "look", "quit epic", "quit steam"]),
    ])
    @MainActor func aLaunchNoLongerWantedAsksNothingMore(_ c: (during: String, taken: [String])) async throws {
        let calls = Calls()
        #expect(try await closeLeftOpen(StoreClients(steam: true, epicLauncher: true, waitedFor: ["epic", "steam"]),
                                        calls: calls, unwantedDuring: c.during) == false)
        #expect(calls.taken == c.taken)
    }

    // MARK: - The launch's opening, with a session left open

    @MainActor
    private func ready(_ steam: String, launch: PendingLaunch, calls: Calls,
                       awaited: Set<AwaitedTitleStarts.Store> = [],
                       firstSettle: BottleProcesses.Settling = .inUse(by: ["steam.exe"]),
                       decision: LeftOpenSession.Decision,
                       duringClose: () -> Void = {},
                       duringSecondSettle: () -> Void = {}) async -> (generation: Int?, handed: LeftOpenSession.Request?) {
        var settles = 0
        var handed: LeftOpenSession.Request?
        let generation = await readyBottleForLaunch(
            id: "1", bottle: steam, bottleURL: URL(string: steam)!, cxAppPath: "", hidTraceEnabled: false, launch: launch,
            titleStartsAwaited: { bottle in
                calls.generationAtTheRead = LaunchGeneration.shared.current(for: bottle)
                return awaited
            },
            settle: { _ in
                settles += 1
                calls.record("settle")
                if settles == 1 { return firstSettle }
                duringSecondSettle()
                return .notRunning
            },
            leftOpen: { _ in calls.record("look"); return decision },
            closeLeftOpen: { request in
                calls.record("close")
                handed = request
                duringClose()
                return request.stillWanted()
            },
            clearOrphans: { _ in calls.record("clear orphans") })
        return (generation, handed)
    }

    /// The session is closed with the launch's own generation, the bottle is
    /// waited for again, and only then are orphans cleared.
    @Test @MainActor func aSessionLeftOpenIsClosedBeforeTheLaunch() async {
        let steam = bottle("Steam")
        let launch = PendingLaunch()
        let calls = Calls()
        let clients = StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"])
        let (generation, handed) = await ready(steam, launch: launch, calls: calls, decision: .close(clients))

        #expect(calls.taken == ["settle", "look", "close", "settle", "clear orphans"])
        #expect(generation == LaunchGeneration.shared.current(for: steam))
        #expect(handed?.generation == generation, "closeBottle must not stand down for the launch closing it")
        #expect(handed?.clients == clients)
        #expect(launch.decided == nil)
    }

    @Test(arguments: [LeftOpenSession.Decision.gameRunning(["nioh.exe"]), .nothingToClose])
    @MainActor func nothingIsClosedWithAGameInTheBottleOrNoSession(_ decision: LeftOpenSession.Decision) async {
        let steam = bottle("Steam")
        let launch = PendingLaunch()
        let calls = Calls()
        let (generation, _) = await ready(steam, launch: launch, calls: calls, decision: decision)
        #expect(calls.taken == ["settle", "look", "clear orphans"])
        #expect(generation == LaunchGeneration.shared.current(for: steam))
    }

    /// A store still starting a title for an earlier launch is launched into,
    /// and whether one is is read before this launch is counted: the earlier
    /// tracker ends its wait once it is.
    @Test @MainActor func aStoreStillStartingATitleIsLaunchedInto() async {
        let steam = bottle("Steam")
        let calls = Calls()
        let (generation, handed) = await ready(steam, launch: PendingLaunch(), calls: calls, awaited: [.steam],
                                               decision: .close(StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"])))
        #expect(calls.taken == ["settle", "look", "clear orphans"])
        #expect(handed == nil)
        #expect(generation != nil)
        #expect(calls.generationAtTheRead.map { $0 + 1 } == generation)
    }

    /// A bottle that is not in use is not looked at for a session.
    @Test @MainActor func aBottleNotInUseIsNotLookedAt() async {
        let steam = bottle("Steam")
        let calls = Calls()
        _ = await ready(steam, launch: PendingLaunch(), calls: calls, firstSettle: .notRunning, decision: .nothingToClose)
        #expect(calls.taken == ["settle", "clear orphans"])
    }

    @Test @MainActor func aStopDuringTheCloseStartsNothing() async {
        let steam = bottle("Steam")
        let launch = PendingLaunch()
        let calls = Calls()
        let (generation, _) = await ready(steam, launch: launch, calls: calls,
                                          decision: .close(StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"])),
                                          duringClose: { _ = LaunchGeneration.shared.stopped(bottle: steam) })
        #expect(generation == nil)
        #expect(calls.taken == ["settle", "look", "close"])
        #expect(launch.decided == .abandoned)
    }

    @Test @MainActor func aPlayDuringTheCloseTakesTheBottle() async {
        let steam = bottle("Steam")
        let launch = PendingLaunch()
        let calls = Calls()
        let (generation, _) = await ready(steam, launch: launch, calls: calls,
                                          decision: .close(StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"])),
                                          duringClose: { LaunchGeneration.shared.launched(bottle: steam) })
        #expect(generation == nil)
        #expect(calls.taken == ["settle", "look", "close"])
        #expect(launch.decided == .superseded)
    }

    /// The wait after the close is asked about too.
    @Test @MainActor func aStopWhileTheClosedBottleComesDownStartsNothing() async {
        let steam = bottle("Steam")
        let launch = PendingLaunch()
        let calls = Calls()
        let (generation, _) = await ready(steam, launch: launch, calls: calls,
                                          decision: .close(StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"])),
                                          duringSecondSettle: { _ = LaunchGeneration.shared.stopped(bottle: steam) })
        #expect(generation == nil)
        #expect(calls.taken == ["settle", "look", "close", "settle"])
        #expect(launch.decided == .abandoned)
    }

    // MARK: - A Stop, in order

    private func describe(_ scope: SteamExitSync.Scope) -> String {
        switch scope {
        case .app(let id): return "app \(id)"
        case .anyApp: return "any"
        }
    }

    /// "ended" is where the Stop tells the window its game is over.
    @MainActor
    private func stop(_ target: SessionStop.Target, in bottle: String, calls: Calls,
                      knownNames: [String] = [],
                      games: [BottleProcesses.Running] = [],
                      afterTheGrace: [BottleProcesses.Running] = [],
                      underWay: SessionStop.UnderWay = SessionStop.UnderWay(steam: [], epic: false),
                      clients: StoreClients = StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"]),
                      clientsAfterTheWaits: StoreClients? = nil,
                      launchDuring: String? = nil,
                      theRequestFails: Bool = false) async throws -> SessionStop.Outcome {
        let generation = LaunchGeneration.shared.stopped(bottle: bottle)
        var looks = 0
        func step(_ name: String) {
            calls.record(name)
            if name == launchDuring { LaunchGeneration.shared.launched(bottle: bottle) }
        }
        return try await SessionStop.run(
            target: target, generation: generation, bottle: bottle,
            knownNames: knownNames,
            watchExitSyncs: { step("watch"); return underWay },
            gamesToEnd: { step("games"); return games },
            askToClose: { condemned in
                step("ask " + condemned.map(\.name).joined(separator: "+"))
                if theRequestFails { throw CancellationError() }
            },
            grace: { _ in step("grace") },
            scan: { step("scan"); return afterTheGrace },
            kill: { stubborn in step("kill " + stubborn.map { "\($0.pid):\($0.name)" }.joined(separator: "+")) },
            gameEnded: { step("ended") },
            clients: {
                looks += 1
                step("clients")
                return looks > 1 ? (clientsAfterTheWaits ?? clients) : clients
            },
            waitForSteamExitSync: { scope, seed in step("steam sync \(describe(scope)) \(seed.sorted())") },
            waitForEpicExitSync: { step("epic sync") },
            quitEpic: { step("quit epic") },
            quitSteam: { step("quit steam") },
            closeBottle: { step("close " + $0.joined(separator: "+")) })
    }

    /// The fault this exists for: a hung game kept Steam from leaving, and the
    /// bottle was ended with Steam's exit sync never waited for. The game goes
    /// first -- asked, given its grace, then ended -- and only what was asked
    /// is ended: a pid reused by another name and a newcomer are left alone.
    /// The window is told the game is over as soon as it is, before any wait.
    @Test @MainActor func theGameGoesFirstThenTheSyncThenTheClientThenTheBottle() async throws {
        let calls = Calls()
        let outcome = try await stop(.steamTitle(appID: "485510"), in: bottle("Steam"), calls: calls,
                                     knownNames: ["nioh.exe", "crashhandler.exe"],
                                     games: [process(40, "nioh.exe"), process(41, "crashhandler.exe")],
                                     afterTheGrace: [process(40, "nioh.exe"), process(41, "steamerrorreporter.exe"),
                                                     process(77, "nioh.exe")])
        #expect(outcome == .closed)
        #expect(calls.taken == ["watch", "games", "ask nioh.exe+crashhandler.exe", "grace", "scan", "kill 40:nioh.exe", "ended",
                                "clients", "steam sync app 485510 []", "clients", "quit steam", "close steam"])
    }

    /// Nothing to end and no sync running: straight to the client.
    @Test @MainActor func withNoGameAndNoSyncTheClientIsAskedAtOnce() async throws {
        let calls = Calls()
        #expect(try await stop(.steamTitle(appID: "485510"), in: bottle("Steam"), calls: calls) == .closed)
        #expect(calls.taken == ["watch", "games", "ended", "clients", "clients", "quit steam", "close steam"])
    }

    /// A fault found by reading the code, not seen on a live bottle. A Stop
    /// ends every game in the bottle, and the Steam bottle holds both
    /// clients, so the other game can be another store's title: its tracker
    /// stands down on the Stop, and its exit sync was waited for only when
    /// the card pressed was of its own store. Every store present is waited
    /// for once the Stop has ended a game the pressed title is not known by.
    @Test @MainActor func aStopWaitsForTheSyncOfEveryTitleItEnded() async throws {
        let both = StoreClients(steam: true, epicLauncher: true, waitedFor: ["epic", "steam"])

        let steamTitleBeside = Calls()
        _ = try await stop(.epicTitle, in: bottle("Steam"), calls: steamTitleBeside, knownNames: ["AlanWake2.exe"],
                           games: [process(5, "AlanWake2.exe"), process(40, "nioh.exe")], clients: both)
        #expect(steamTitleBeside.taken == ["watch", "games", "ask AlanWake2.exe+nioh.exe", "grace", "scan", "ended",
                                           "clients", "steam sync any []", "epic sync",
                                           "clients", "quit epic", "quit steam", "close epic+steam"])

        let epicTitleBeside = Calls()
        _ = try await stop(.steamTitle(appID: "485510"), in: bottle("Steam"), calls: epicTitleBeside, knownNames: ["nioh.exe"],
                           games: [process(40, "nioh.exe"), process(5, "AlanWake2.exe")], clients: both)
        #expect(epicTitleBeside.taken == ["watch", "games", "ask nioh.exe+AlanWake2.exe", "grace", "scan", "ended",
                                          "clients", "steam sync any []", "epic sync",
                                          "clients", "quit epic", "quit steam", "close epic+steam"])

        let besideATitleOfOurOwn = Calls()
        _ = try await stop(.otherTitle, in: bottle("Steam"), calls: besideATitleOfOurOwn, knownNames: ["MyGame.exe"],
                           games: [process(9, "MyGame.exe"), process(40, "nioh.exe")])
        #expect(besideATitleOfOurOwn.taken == ["watch", "games", "ask MyGame.exe+nioh.exe", "grace", "scan", "ended",
                                               "clients", "steam sync any []", "clients", "quit steam", "close steam"])
    }

    /// Another title is a name the pressed one is not known by, compared as
    /// `games` compares: lowercased, and at lsof's cut.
    @Test func whetherAStopEndedAnotherTitle() {
        let whole = "EOSOverlayRenderer-Win64-Shipping.exe"
        let cut = String(whole.prefix(BottleProcesses.lsofNameLimit))
        #expect(SessionStop.endedAnotherTitle([process(40, "Nioh.exe")], knownNames: ["nioh_launcher.exe", "nioh.exe"]) == false)
        #expect(SessionStop.endedAnotherTitle([process(6, cut)], knownNames: [whole]) == false)
        #expect(SessionStop.endedAnotherTitle([process(40, "nioh.exe"), process(5, "AlanWake2.exe")], knownNames: ["nioh.exe"]))
        #expect(SessionStop.endedAnotherTitle([process(5, "game.exe")], knownNames: []))
        #expect(SessionStop.endedAnotherTitle([], knownNames: []) == false)
    }

    /// A game that exited on its own a moment before the Stop: its sync is
    /// still waited for, by every title's rule.
    @Test @MainActor func aSyncAlreadyRunningIsWaitedForWithoutAGame() async throws {
        let calls = Calls()
        _ = try await stop(.steamTitle(appID: "485510"), in: bottle("Steam"), calls: calls,
                           underWay: SessionStop.UnderWay(steam: ["241100"], epic: false))
        #expect(calls.taken.contains("steam sync any [\"241100\"]"))
    }

    /// An Epic title in the Steam bottle: the launcher's sync, not Steam's,
    /// and both clients asked, the launcher first.
    @Test @MainActor func anEpicTitleWaitsForTheLauncherAndAsksBothClients() async throws {
        let calls = Calls()
        let both = StoreClients(steam: true, epicLauncher: true, waitedFor: ["epic", "steam"])
        _ = try await stop(.epicTitle, in: bottle("Steam"), calls: calls, knownNames: ["AlanWake2.exe"],
                           games: [process(5, "AlanWake2.exe")], clients: both)
        #expect(calls.taken == ["watch", "games", "ask AlanWake2.exe", "grace", "scan", "ended",
                                "clients", "epic sync", "clients", "quit epic", "quit steam", "close epic+steam"])
    }

    /// The toolbar cannot know whose game it ended, so it waits for both.
    @Test @MainActor func theToolbarWaitsForEveryStore() async throws {
        let calls = Calls()
        let both = StoreClients(steam: true, epicLauncher: true, waitedFor: ["epic", "steam"])
        _ = try await stop(.everything, in: bottle("Steam"), calls: calls,
                           games: [process(5, "game.exe")], clients: both)
        #expect(calls.taken == ["watch", "games", "ask game.exe", "grace", "scan", "ended",
                                "clients", "steam sync any []", "epic sync", "clients", "quit epic", "quit steam", "close epic+steam"])
    }

    /// A title no store syncs waits for nothing, and a request that could not
    /// be sent still ends the game.
    @Test @MainActor func aRequestThatFailsStillEndsTheGame() async throws {
        let calls = Calls()
        _ = try await stop(.otherTitle, in: bottle("Steam"), calls: calls, knownNames: ["MyGame.exe"],
                           games: [process(9, "MyGame.exe")], afterTheGrace: [process(9, "MyGame.exe")],
                           theRequestFails: true)
        #expect(calls.taken == ["watch", "games", "ask MyGame.exe", "grace", "scan", "kill 9:MyGame.exe", "ended",
                                "clients", "clients", "quit steam", "close steam"])
    }

    /// A Steam a teardown asked just before the Stop is waited for, not asked
    /// again.
    @Test @MainActor func aSteamAlreadyLeavingIsNotAskedAgainByAStop() async throws {
        let calls = Calls()
        _ = try await stop(.steamTitle(appID: "485510"), in: bottle("Steam"), calls: calls,
                           clientsAfterTheWaits: StoreClients(steam: true, epicLauncher: false, waitedFor: ["steam"],
                                                              steamAlreadyAsked: true))
        #expect(calls.taken == ["watch", "games", "ended", "clients", "clients", "close steam"])
    }

    /// Never a Steam that is not running.
    @Test @MainActor func aClientThatLeftDuringTheSyncIsNotAsked() async throws {
        let calls = Calls()
        _ = try await stop(.steamTitle(appID: "485510"), in: bottle("Steam"), calls: calls,
                           games: [process(40, "nioh.exe")],
                           clientsAfterTheWaits: StoreClients(steam: false, epicLauncher: false, waitedFor: ["steam"]))
        #expect(calls.taken.contains("quit steam") == false)
        #expect(calls.taken.last == "close steam")
    }

    /// A game launched into the bottle while the stop runs takes the bottle
    /// from it. The kill before that still comes: it is matched to what was
    /// running when Stop was pressed.
    @Test(arguments: [
        ("grace", ["watch", "games", "ask nioh.exe", "grace", "scan", "kill 40:nioh.exe", "ended"]),
        ("steam sync app 485510 []", ["watch", "games", "ask nioh.exe", "grace", "scan", "kill 40:nioh.exe", "ended",
                                      "clients", "steam sync app 485510 []"]),
        ("quit steam", ["watch", "games", "ask nioh.exe", "grace", "scan", "kill 40:nioh.exe", "ended",
                        "clients", "steam sync app 485510 []", "clients", "quit steam"]),
    ])
    @MainActor func aLaunchDuringTheStopTakesTheBottle(_ c: (during: String, taken: [String])) async throws {
        let calls = Calls()
        let outcome = try await stop(.steamTitle(appID: "485510"), in: bottle("Steam"), calls: calls, knownNames: ["nioh.exe"],
                                     games: [process(40, "nioh.exe")], afterTheGrace: [process(40, "nioh.exe")],
                                     launchDuring: c.during)
        #expect(outcome == .leftToANewerLaunch)
        #expect(calls.taken == c.taken)
    }

    @Test @MainActor func aLaunchWhileTheEpicLauncherIsAskedSparesSteam() async throws {
        let calls = Calls()
        let both = StoreClients(steam: true, epicLauncher: true, waitedFor: ["epic", "steam"])
        #expect(try await stop(.epicTitle, in: bottle("Steam"), calls: calls, clients: both,
                               launchDuring: "quit epic") == .leftToANewerLaunch)
        #expect(calls.taken == ["watch", "games", "ended", "clients", "clients", "quit epic"])
    }

    // MARK: - What a Stop waits for and how it asks

    @Test func whichTitleAStopIsAbout() {
        #expect(SessionStop.target(isEpic: true, isCustom: false, steamAppID: 0) == .epicTitle)
        #expect(SessionStop.target(isEpic: false, isCustom: true, steamAppID: 12) == .otherTitle)
        #expect(SessionStop.target(isEpic: false, isCustom: false, steamAppID: 0) == .otherTitle)
        #expect(SessionStop.target(isEpic: false, isCustom: false, steamAppID: 241100) == .steamTitle(appID: "241100"))
    }

    @Test func whichSteamSyncAStopWaitsFor() {
        func wait(_ target: SessionStop.Target, ended: Bool, another: Bool = false, _ underWay: Set<String>) -> SteamExitSync.Scope? {
            SessionStop.steamWait(target: target, aGameWasEnded: ended, anotherTitleWasEnded: another, underWay: underWay)
        }
        #expect(wait(.steamTitle(appID: "1"), ended: true, []) == .app("1"))
        #expect(wait(.steamTitle(appID: "1"), ended: true, ["1"]) == .app("1"))
        #expect(wait(.steamTitle(appID: "1"), ended: true, ["2"]) == .anyApp)
        #expect(wait(.steamTitle(appID: "1"), ended: false, []) == nil)
        #expect(wait(.everything, ended: true, []) == .anyApp)
        #expect(wait(.everything, ended: false, []) == nil)
        #expect(wait(.epicTitle, ended: true, []) == nil)
        #expect(wait(.otherTitle, ended: true, ["2"]) == .anyApp)
        // Another title's game was ended with the pressed one's.
        #expect(wait(.steamTitle(appID: "1"), ended: true, another: true, []) == .anyApp)
        #expect(wait(.epicTitle, ended: true, another: true, []) == .anyApp)
        #expect(wait(.otherTitle, ended: true, another: true, []) == .anyApp)
    }

    @Test func whetherAStopWaitsForTheEpicLauncher() {
        func waits(_ target: SessionStop.Target, ended: Bool, another: Bool = false, _ underWay: Bool) -> Bool {
            SessionStop.waitsForEpic(target: target, aGameWasEnded: ended, anotherTitleWasEnded: another, underWay: underWay)
        }
        #expect(waits(.epicTitle, ended: true, false))
        #expect(waits(.everything, ended: true, false))
        #expect(waits(.steamTitle(appID: "1"), ended: true, false) == false)
        #expect(waits(.epicTitle, ended: false, false) == false)
        #expect(waits(.steamTitle(appID: "1"), ended: false, true))
        // Another title's game was ended with the pressed one's.
        #expect(waits(.steamTitle(appID: "1"), ended: true, another: true, false))
        #expect(waits(.otherTitle, ended: true, another: true, false))
    }

    /// taskkill marks one process for each /IM, so two of a name are named
    /// twice; a name lsof cut short is completed from the title's names when
    /// exactly one fits; a name the shell would read is not handed over.
    @Test func theNamesTaskkillIsGiven() {
        let limit = BottleProcesses.lsofNameLimit
        let whole = "EOSOverlayRenderer-Win64-Shipping.exe"
        let cut = String(whole.prefix(limit))
        #expect(SessionStop.imageNames(toAsk: [process(1, "nioh.exe"), process(2, "nioh.exe")], knownNames: [])
                == ["nioh.exe", "nioh.exe"])
        #expect(SessionStop.imageNames(toAsk: [process(3, cut)], knownNames: ["launcher.exe", whole]) == [whole])
        #expect(SessionStop.imageNames(toAsk: [process(3, cut)], knownNames: []) == [cut])
        #expect(SessionStop.imageNames(toAsk: [process(3, cut)], knownNames: [whole, cut + "-other.exe"]) == [cut])
        #expect(SessionStop.imageNames(toAsk: [process(4, "a\"b.exe"), process(5, "$x.exe")], knownNames: []).isEmpty)
        #expect(SessionStop.taskkillArguments(["nioh.exe", "nioh.exe"]) == "/IM \"nioh.exe\" /IM \"nioh.exe\"")
    }

    // MARK: - A teardown that finds Stop was pressed leaves the rest to it

    /// The Stop now closes the bottle itself; a tracker's teardown carrying on
    /// would ask Steam to shut down a second time, after it may have gone.
    @Test @MainActor func aStopDuringATeardownLeavesTheRestToTheStop() async throws {
        let steam = bottle("Steam")
        let generation = LaunchGeneration.shared.current(for: steam)
        let calls = Calls()
        let wentThrough = try await SessionTeardown.run(
            isEpic: false, generation: generation, bottle: steam, reason: "a test",
            waitForEpicLauncher: { calls.record("epic launcher settles") },
            waitForCloudSync: { calls.record("cloud sync"); _ = LaunchGeneration.shared.stopped(bottle: steam) },
            steamIsInBottle: { calls.record("is steam here"); return true },
            quitEpic: { calls.record("quit epic") },
            quitSteam: { calls.record("quit steam") },
            closeBottle: { calls.record("close " + $0.joined(separator: "+")) })
        #expect(wentThrough == false)
        #expect(calls.taken == ["cloud sync"])

        let epic = bottle("Epic")
        let epicCalls = Calls()
        let epicWentThrough = try await SessionTeardown.run(
            isEpic: true, generation: LaunchGeneration.shared.current(for: epic), bottle: epic, reason: "a test",
            waitForEpicLauncher: { epicCalls.record("epic launcher settles") },
            waitForCloudSync: { epicCalls.record("cloud sync") },
            steamIsInBottle: { epicCalls.record("is steam here"); return true },
            quitEpic: { epicCalls.record("quit epic"); _ = LaunchGeneration.shared.stopped(bottle: epic) },
            quitSteam: { epicCalls.record("quit steam") },
            closeBottle: { epicCalls.record("close " + $0.joined(separator: "+")) })
        #expect(epicWentThrough == false)
        #expect(epicCalls.taken == ["epic launcher settles", "quit epic", "is steam here"])
    }
}

/// The exit-sync rules, on lines from the Steam bottle's cloud_log.txt of
/// 2026-09-15 and from this machine's earlier logs.
@Suite("Steam's exit sync")
struct SteamExitSyncTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func feed(_ sync: inout SteamExitSync, _ lines: [String], at seconds: TimeInterval) -> [SteamExitSync.Event] {
        lines.compactMap { sync.observe($0, at: at(seconds)) }
    }

    @Test func oneTitlesExitSyncEnds() {
        var sync = SteamExitSync(scope: .app("1369760"), started: t0)
        let events = feed(&sync, [
            "[2026-09-15 00:45:52] [AppID 1369760] Starting sync (up,AC Exit,)",
            "[2026-09-15 00:45:52] [AppID 241100] Starting sync (up,AC Exit,)",
            "[2026-09-15 00:45:52] [AppID 1369760] Upload complete in build list",
        ], at: 1)
        #expect(events == [.began(app: "1369760"), .upToDate(app: "1369760")])
        #expect(sync.verdict(at: at(1)) == .finished)
    }

    /// Every title's wait ends when every exit sync it saw has ended.
    @Test func everyTitlesWaitEndsWithTheLastSync() {
        var sync = SteamExitSync(scope: .anyApp, started: t0)
        _ = feed(&sync, [
            "[2026-09-15 00:54:37] [AppID 1369760] Starting sync (up,AC Exit,)",
            "[2026-09-15 00:54:38] [AppID 1369760] Upload complete in build list",
            "[2026-09-15 00:54:38] [AppID 241100] Starting sync (up,AC Exit,)",
        ], at: 1)
        #expect(sync.verdict(at: at(1)) == .waiting)
        _ = feed(&sync, ["[2026-09-15 00:54:38] [AppID 241100] Upload complete in build list"], at: 2)
        #expect(sync.verdict(at: at(2)) == .finished)
    }

    /// An ending with no exit sync begun is not the end of one.
    @Test func anEndingWithoutAnExitSyncIsNotTheEnd() {
        var sync = SteamExitSync(scope: .anyApp, started: t0)
        _ = feed(&sync, ["[2026-09-15 00:53:33] [AppID 7] Successfully synced to ChangeNumber 0"], at: 1)
        #expect(sync.verdict(at: at(1)) == .waiting)
        #expect(sync.verdict(at: at(15)) == .noExitSync)
    }

    /// The fault the launch rule is for: lines of an earlier session's exit
    /// sync, then that title's launch sync, all in one read. The wait is for
    /// the exit sync that comes after them.
    @Test func aLaunchSyncForgetsTheExitSyncBeforeIt() {
        var sync = SteamExitSync(scope: .app("1369760"), started: t0)
        _ = feed(&sync, [
            "[2026-09-15 00:45:52] [AppID 1369760] Starting sync (up,AC Exit,)",
            "[2026-09-15 00:45:52] [AppID 1369760] Upload complete in build list",
            "[2026-09-15 00:53:35] [AppID 1369760] Starting sync (AC Launch,down,)",
            "[2026-09-15 00:53:36] [AppID 1369760] Successfully synced to ChangeNumber 0",
        ], at: 1)
        #expect(sync.verdict(at: at(1)) == .waiting)
        #expect(sync.sawExitSync == false)
        _ = feed(&sync, [
            "[2026-09-15 00:54:37] [AppID 1369760] Starting sync (up,AC Exit,)",
            "[2026-09-15 00:54:38] [AppID 1369760] Upload complete, result OK",
        ], at: 2)
        #expect(sync.verdict(at: at(2)) == .finished)
    }

    @Test func uploadsAndFailuresAreTold() {
        var uploaded = SteamExitSync(scope: .app("1340990"), started: t0)
        let events = feed(&uploaded, [
            "[..] [AppID 1340990] Starting sync (up,AC Exit,)",
            "[..] [AppID 1340990] Need to upload file KoeiTecmo/Ronin/Savedata/x/SAVEDATA.BIN",
            "[..] [AppID 1340990] Need to upload file KoeiTecmo/Ronin/Savedata/x/SYSTEM.BIN",
            "[2026-08-28 16:34:14] [AppID 1340990] Upload complete, result OK",
        ], at: 1)
        #expect(events.last == .uploaded(app: "1340990", files: 2))

        var failed = SteamExitSync(scope: .app("1340990"), started: t0)
        let line = "[2026-08-28 11:17:20] [AppID 1340990] Failed sync for 'AC Exit,Sync Disabled,' [login=false]"
        let failure = feed(&failed, ["[..] [AppID 1340990] Starting sync (up,AC Exit,)", line], at: 1)
        #expect(failure.last == .failed(app: "1340990", line: line))
    }

    @Test func theWaitsBounds() {
        let quietOne = SteamExitSync(scope: .app("1"), started: t0)
        #expect(quietOne.verdict(at: at(14.9)) == .waiting)
        #expect(quietOne.verdict(at: at(15)) == .noExitSync)

        var begun = SteamExitSync(scope: .app("1"), started: t0)
        _ = feed(&begun, ["[..] [AppID 1] Starting sync (up,AC Exit,)"], at: 1)
        #expect(begun.verdict(at: at(7)) == .waiting)
        #expect(begun.verdict(at: at(7.1)) == .wentQuiet)

        var busy = SteamExitSync(scope: .app("1"), started: t0)
        _ = feed(&busy, ["[..] [AppID 1] Starting sync (up,AC Exit,)"], at: 1)
        _ = feed(&busy, ["[..] [AppID 1] Need to upload file a"], at: 59)
        #expect(busy.verdict(at: at(60)) == .outOfTime)
    }

    /// A sync found running in the whole log counts as begun.
    @Test func aSyncAlreadyUnderWayIsWaitedFor() {
        var sync = SteamExitSync(scope: .anyApp, started: t0, alreadyUnderWay: ["241100"])
        #expect(sync.sawExitSync)
        #expect(sync.verdict(at: at(6)) == .waiting)
        _ = feed(&sync, ["[2026-09-15 00:54:38] [AppID 241100] Upload complete in build list"], at: 3)
        #expect(sync.verdict(at: at(3)) == .finished)
        #expect(SteamExitSync(scope: .anyApp, started: t0, alreadyUnderWay: ["241100"]).verdict(at: at(6.1)) == .wentQuiet)
    }

    @Test func theTitleAndTheTimeOfALine() {
        #expect(SteamExitSync.appID(in: "[2026-09-15 00:45:52] [AppID 241100] Starting sync (up,AC Exit,)") == "241100")
        #expect(SteamExitSync.appID(in: "[..] AppID 241100 adding PID 1") == nil)
        let minus3 = TimeZone(secondsFromGMT: -3 * 3600)!
        let written = SteamExitSync.timestamp(of: "[2026-09-15 00:54:38] [AppID 241100] Upload complete in build list", timeZone: minus3)
        #expect(written == ISO8601DateFormatter().date(from: "2026-09-15T03:54:38Z"))
        #expect(SteamExitSync.timestamp(of: "[..] [AppID 1] Starting sync (up,AC Exit,)") == nil)
    }

    @Test func theSyncsRunningInAWholeLog() {
        let minus3 = TimeZone(secondsFromGMT: -3 * 3600)!
        let now = SteamExitSync.timestamp(of: "[2026-09-15 00:54:48]", timeZone: minus3)!
        func underWay(_ lines: [String], scope: SteamExitSync.Scope = .anyApp) -> Set<String> {
            SteamExitSync.underWay(inLog: lines.joined(separator: "\r\n"), scope: scope, now: now, timeZone: minus3)
        }
        let finished = [
            "[2026-09-15 00:54:37] [AppID 1369760] Starting sync (up,AC Exit,)",
            "[2026-09-15 00:54:38] [AppID 1369760] Upload complete in build list",
            "[2026-09-15 00:54:38] [AppID 241100] Starting sync (up,AC Exit,)",
            "[2026-09-15 00:54:38] [AppID 241100] Upload complete in build list",
        ]
        #expect(underWay(finished).isEmpty)
        #expect(underWay(Array(finished.prefix(3))) == ["241100"])
        #expect(underWay(Array(finished.prefix(3)), scope: .app("1369760")).isEmpty)
        // Begun more than the deadline ago: a sync Steam never finished.
        #expect(underWay(["[2026-09-15 00:45:52] [AppID 241100] Starting sync (up,AC Exit,)"]).isEmpty)
        // A launch since then.
        #expect(underWay(["[2026-09-15 00:54:37] [AppID 241100] Starting sync (up,AC Exit,)",
                          "[2026-09-15 00:54:40] [AppID 241100] Starting sync (AC Launch,down,)"]).isEmpty)
        // A time that cannot be read.
        #expect(underWay(["[..] [AppID 241100] Starting sync (up,AC Exit,)"]).isEmpty)
    }

    /// The launcher's own pair, measured in the Steam bottle's log on 2026-09-10.
    @Test func theEpicLaunchersSyncRunningInItsLog() {
        let started = "[2026.09.10-02.11.30:935][813]LogCloudSync: Cloud Sync: Sync Started for c4763f236d08423eb47b4c3008779c84:93f2a8c3547846eda966cb3c152a026e:dc9d2e595d0e4650b35d659f90d41059"
        let exited = "[2026.09.10-02.11.35:502][882]LogCloudSync: Cloud Sync: Exiting Cloud Sync - SUCCESS - AppName: c4763f236d08423eb47b4c3008779c84:93f2a8c3547846eda966cb3c152a026e:dc9d2e595d0e4650b35d659f90d41059"
        #expect(EpicSettle.syncUnderWay(inLog: started))
        #expect(EpicSettle.syncUnderWay(inLog: [started, exited].joined(separator: "\r\n")) == false)
        #expect(EpicSettle.syncUnderWay(inLog: [started, exited, started].joined(separator: "\n")))
        #expect(EpicSettle.syncUnderWay(inLog: "") == false)
    }
}
