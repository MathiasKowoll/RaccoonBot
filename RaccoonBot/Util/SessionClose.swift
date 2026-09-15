//
//  SessionClose.swift
//  RaccoonBot
//
//  Ending a session on purpose: a Stop button, and a launch that finds the
//  last session still open. The order each follows is kept here with every
//  step injected, so it can be tested without a bottle; the steps themselves
//  are wired in Launcher.swift.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Which store clients are in a bottle, by the names lsof gave.
nonisolated struct StoreClients: Equatable {
    /// Steam itself. Only a bottle with this in it has Steam asked to leave:
    /// "Steam.exe -shutdown" with no Steam running would start one. The Steam
    /// bottle's bootstrap_log.txt records 25 client starts launched with
    /// nothing but -shutdown, each running Steam's update check.
    let steam: Bool
    /// The Epic launcher itself, which is what `quitEpic` asks.
    let epicLauncher: Bool
    /// The name prefixes closeBottle waits for, of the clients with anything
    /// at all in the bottle: a Steam that has already gone can leave its web
    /// helper behind, and closeBottle gives that its time too.
    let waitedFor: [String]
    /// Every steam.exe in the bottle has already been sent its shutdown --
    /// see SteamShutdowns. It is leaving, and is waited for, not asked again.
    let steamAlreadyAsked: Bool

    init(steam: Bool, epicLauncher: Bool, waitedFor: [String], steamAlreadyAsked: Bool = false) {
        self.steam = steam
        self.epicLauncher = epicLauncher
        self.waitedFor = waitedFor
        self.steamAlreadyAsked = steamAlreadyAsked
    }

    init(names: [String]) {
        self.init(names: names, steamAlreadyAsked: false)
    }

    /// From a scan, knowing which Steam processes were already sent their
    /// shutdown: Steam counts as already asked only when every steam.exe in
    /// the scan was, by pid and name -- see BottleProcesses.stillThere.
    init(processes: [BottleProcesses.Running], alreadyAsked asked: [BottleProcesses.Running]) {
        let steams = Self.steams(among: processes)
        self.init(names: processes.map(\.name),
                  steamAlreadyAsked: !steams.isEmpty && BottleProcesses.stillThere(steams, of: asked).count == steams.count)
    }

    /// Steam itself, by the name lsof gives it.
    static let steamName = "steam.exe"

    /// The Steam processes in a scan that "Steam.exe -shutdown" goes to:
    /// steam.exe, and nothing else that starts with "steam". Its helpers do
    /// -- steamwebhelper.exe, and steamerrorreporter.exe,
    /// steamerrorreporter64.exe and steamsysinfo.exe in the Steam bottle's
    /// Steam folder -- and one can outlive Steam, so a prefix answers "Steam
    /// is here" for a bottle with no Steam in it. Compared whole, and
    /// safely: the name is shorter than lsofNameLimit, so lsof gives it
    /// uncut.
    nonisolated static func steams(among processes: [BottleProcesses.Running]) -> [BottleProcesses.Running] {
        processes.filter { $0.name.lowercased() == steamName }
    }

    private init(names: [String], steamAlreadyAsked: Bool) {
        let lower = names.map { $0.lowercased() }
        // Epic first, the order SessionTeardown asks them in.
        self.init(steam: lower.contains(Self.steamName),
                  epicLauncher: lower.contains("epicgameslauncher.exe"),
                  waitedFor: ["epic", "steam"].filter { prefix in lower.contains { $0.hasPrefix(prefix) } },
                  steamAlreadyAsked: steamAlreadyAsked)
    }

    /// Whether Steam is to be sent its shutdown: it is there, and it has not
    /// been sent one already.
    var asksSteam: Bool { steam && !steamAlreadyAsked }

    /// What closeBottle is handed. With no client left there is nothing for
    /// it to wait for, and "steam" is what every Stop handed it before this.
    var closeBottleClients: [String] { waitedFor.isEmpty ? ["steam"] : waitedFor }
}

/// The Steam processes each bottle's "Steam.exe -shutdown" went to, and when.
///
/// A Steam that was asked to leave stays in the bottle while it writes its own
/// state, and a scan cannot tell it from one that is staying. Asked again, the
/// second request reaches the bottle a moment after the scan, through wine,
/// and if that Steam has finished leaving by then the request starts a Steam
/// instead -- which closeBottle then waits thirty seconds for and ends in the
/// middle of its start. A teardown that has just asked Steam to leave, with a
/// Play or a Stop pressed behind it, is exactly that. So every request is
/// written down against the Steam processes it was sent to, and the close
/// before a launch and a Stop do not ask those again: closeBottle waits for
/// them as for any client.
final class SteamShutdowns: @unchecked Sendable {
    static let shared = SteamShutdowns()

    /// How long a Steam that was sent its shutdown counts as leaving. Chosen,
    /// not measured: twice the thirty seconds closeBottle gives a client. A
    /// Steam still there after it is asked again. A request that reaches a
    /// running Steam starts no client: Steam logged off in the Steam bottle
    /// at 00:44:29, 00:45:52 and 00:54:38 on 2026-09-15, and bootstrap_log.txt
    /// records no client start at any of them.
    static let leavingFor: TimeInterval = 60

    private let lock = NSLock()
    private var sent: [String: [(process: BottleProcesses.Running, at: Date)]] = [:]

    /// Records that these Steam processes were sent a shutdown. Keyed like
    /// LaunchGeneration, so two spellings of one bottle meet.
    func record(_ steams: [BottleProcesses.Running], in bottle: String, at now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        let key = LaunchGeneration.key(for: bottle)
        let kept = (sent[key] ?? []).filter { now.timeIntervalSince($0.at) < Self.leavingFor }
        sent[key] = kept + steams.map { (process: $0, at: now) }
    }

    /// The Steam processes in this bottle sent a shutdown within `leavingFor`.
    func askedToLeave(in bottle: String, at now: Date = Date()) -> [BottleProcesses.Running] {
        lock.lock(); defer { lock.unlock() }
        return (sent[LaunchGeneration.key(for: bottle)] ?? [])
            .filter { now.timeIntervalSince($0.at) < Self.leavingFor }
            .map(\.process)
    }
}

/// Launches whose store has been asked to start a title and has started
/// nothing yet, though their window has been given back.
///
/// Steam took two minutes to start Ninja Gaiden 3 on 2026-09-15, most of it at
/// its own ShowInterstitials step, and the tracker gives the window back when
/// Steam has started nothing ninety seconds past its first step -- then goes
/// on waiting, up to SteamLaunchIdentification.steamStartLimit. The Epic
/// tracker does the same after 180 seconds. Play can be pressed again then,
/// and a launch that found only the store in the bottle would close it in the
/// middle of that start, and every such press would begin it again. So while
/// a start is waited for, a launch into that bottle does not close the store
/// it waits on: it goes into the bottle as it is, as launches did before
/// LeftOpenSession. The tracker ends its entry however its wait ends; the
/// time on it only bounds an entry a tracker never ended.
final class AwaitedTitleStarts: @unchecked Sendable {
    nonisolated enum Store: Hashable, Sendable {
        case steam
        case epic
    }

    static let shared = AwaitedTitleStarts()

    private let lock = NSLock()
    private var waits: [String: [Store: (generation: Int, until: Date)]] = [:]

    func began(_ store: Store, generation: Int, bottle: String, until: Date) {
        lock.lock(); defer { lock.unlock() }
        waits[LaunchGeneration.key(for: bottle), default: [:]][store] = (generation, until)
    }

    /// Ends the wait of that generation only: a newer launch's tracker may
    /// already have begun one of its own for the same store.
    func ended(_ store: Store, generation: Int, bottle: String) {
        lock.lock(); defer { lock.unlock() }
        let key = LaunchGeneration.key(for: bottle)
        guard waits[key]?[store]?.generation == generation else { return }
        waits[key]?[store] = nil
    }

    func awaited(in bottle: String, at now: Date = Date()) -> Set<Store> {
        lock.lock(); defer { lock.unlock() }
        return Set((waits[LaunchGeneration.key(for: bottle)] ?? [:]).filter { now < $0.value.until }.keys)
    }
}

/// A launch into a bottle whose last session was left open.
///
/// A bottle with Steam or the Epic launcher still up in it, and no game,
/// used to be launched into as it was. Everything that reads the bottle at
/// boot then belonged to whatever started it: the registry was left alone
/// because a wineserver was alive, so this title's controller settings were
/// not written; a HID trace came out without winebus's lines; and an Epic
/// title handed its URI to the launcher already running and inherited its
/// environment, not this title's options. So such a session is closed first,
/// the way a session is closed after a game, and the launch starts the bottle
/// itself. The price, accepted by the user on 2026-09-15, is that Steam
/// restarts on every such launch, including a Steam opened by RaccoonBot's
/// own Steam button.
///
/// A game running in the bottle is never closed for a launch: the launch
/// goes into the bottle as it is.
enum LeftOpenSession {
    nonisolated enum Decision: Equatable {
        /// There is no session to close: the bottle is not up, or only wine's
        /// own processes are in it.
        case nothingToClose
        /// Something the bottle's lists do not know is running, by the names
        /// lsof gave. Nothing is closed.
        case gameRunning([String])
        /// Only these clients and wine's own processes are in it.
        case close(StoreClients)
    }

    /// The decision, taking the scan and the names that are not games rather
    /// than making them.
    ///
    /// A game is what `gamesRunning` counts, so a name nobody has listed is
    /// one -- reg.exe from a fix installer included, which is the direction
    /// that closes nothing under it.
    nonisolated static func decide(processes: [BottleProcesses.Running], notGames: Set<String>) -> Decision {
        guard case .inUse = BottleProcesses.occupancy(of: processes) else { return .nothingToClose }
        let games = BottleProcesses.games(among: processes, notGames: notGames)
        if !games.isEmpty { return .gameRunning(Set(games.map(\.name)).sorted()) }
        return .close(StoreClients(names: processes.map(\.name)))
    }

    /// The decision for a bottle as it is now.
    static func decision(inBottleAt bottle: URL) async -> Decision {
        // Off the main actor, as the wait before it: a scan runs lsof and
        // waits for it, and the first look at a bottle's names walks the
        // Steam and Epic Games folders.
        let (here, notGames) = await Task.detached(priority: .userInitiated) {
            (BottleProcesses.running(inBottleAt: bottle), BottleProcesses.notGames(inBottleAt: bottle))
        }.value
        return decide(processes: here, notGames: notGames)
    }

    /// The store in the bottle that is still starting a title for an earlier
    /// launch, if any -- see AwaitedTitleStarts. With one, nothing is closed.
    nonisolated static func storeStillStarting(_ clients: StoreClients,
                                               awaited: Set<AwaitedTitleStarts.Store>) -> AwaitedTitleStarts.Store? {
        if clients.steam && awaited.contains(.steam) { return .steam }
        if clients.epicLauncher && awaited.contains(.epic) { return .epic }
        return nil
    }

    /// What a launch hands the close: which bottle, the clients found in it,
    /// the launch's own generation for closeBottle, and the launch's own
    /// question of whether it is still wanted.
    struct Request {
        let bottle: String
        let bottleURL: URL
        let cxAppPath: String
        let generation: Int
        let clients: StoreClients
        let stillWanted: () -> Bool
    }

    /// The close itself, in order, asking whether the launch is still wanted
    /// after every step that waits and before the next request.
    ///
    /// Each client's exit sync first -- a game that exited on its own a
    /// moment ago may still be uploading, and asking its client to leave now
    /// is the lost save SessionTeardown exists to prevent. The wait closures
    /// return at once when nothing is under way. Then each client still in
    /// the bottle is asked to leave, the Epic launcher before Steam as
    /// SessionTeardown asks them, and closeBottle waits for them and ends the
    /// prefix.
    ///
    /// Returns false when the launch stopped being wanted, and then nothing
    /// more is asked: a Stop pressed meanwhile closes the bottle itself, and
    /// a newer Play does this for itself. The steps are parameters so a test
    /// can press Stop or Play inside any of them.
    static func close(clients: StoreClients,
                      stillWanted: () -> Bool,
                      waitForSteamExitSync: () async throws -> Void,
                      waitForEpicExitSync: () async throws -> Void,
                      clientsNow: () async -> StoreClients,
                      quitEpic: () async throws -> Void,
                      quitSteam: () async throws -> Void,
                      closeBottle: (_ clients: [String]) async throws -> Void) async throws -> Bool {
        if clients.steam {
            try await waitForSteamExitSync()
            guard stillWanted() else { return false }
        }
        if clients.epicLauncher {
            try await waitForEpicExitSync()
            guard stillWanted() else { return false }
        }
        // Asked again: the waits can last a minute, and a client that left
        // in that time must not be asked -- for Steam, that would start one.
        // Nor a Steam already asked, by the last session's teardown a moment
        // ago: it is on its way out -- see SteamShutdowns.
        let leaving = await clientsNow()
        guard stillWanted() else { return false }
        if leaving.epicLauncher {
            try await quitEpic()
            guard stillWanted() else { return false }
        }
        if leaving.asksSteam {
            try await quitSteam()
            guard stillWanted() else { return false }
        }
        try await closeBottle(leaving.closeBottleClients)
        return stillWanted()
    }
}

/// What a Stop button does, in order.
///
/// It used to ask Steam to shut down and then close the bottle, and a game
/// that had hung could keep Steam from leaving: closeBottle then ended the
/// prefix at the end of its thirty seconds, with Steam's exit sync of that
/// game never waited for. So the game goes first, then the store's exit sync,
/// then the client, then the bottle.
enum SessionStop {
    /// Which store's exit sync the ended game belongs to.
    nonisolated enum Target: Equatable {
        case steamTitle(appID: String)
        case epicTitle
        /// A title of the user's own, which no store syncs.
        case otherTitle
        /// The toolbar's Stop, which does not know what is running.
        case everything
    }

    nonisolated static func target(isEpic: Bool, isCustom: Bool, steamAppID: Int) -> Target {
        if isEpic { return .epicTitle }
        if isCustom || steamAppID == 0 { return .otherTitle }
        return .steamTitle(appID: String(steamAppID))
    }

    /// The exit syncs already running when the Stop began, from the whole
    /// logs: Steam's by title, and whether the Epic launcher's is.
    nonisolated struct UnderWay: Equatable {
        var steam: Set<String>
        var epic: Bool
    }

    nonisolated enum Outcome: Equatable {
        /// Every step was taken, up to and including closeBottle.
        case closed
        /// A game was launched into the bottle during the stop, which left
        /// the rest to that launch.
        case leftToANewerLaunch
    }

    /// How long a game asked to close is given before it is ended. Chosen,
    /// not measured: long enough for a title that quits on WM_CLOSE, short
    /// enough that a hung one does not hold the Stop. A title that saves for
    /// longer than this on its way out is ended in the middle of it.
    static let grace: TimeInterval = 5

    /// Never asked or ended as a game: wine's taskkill, which a Stop pressed
    /// a moment earlier may still be running.
    nonisolated static let notAsked: Set<String> = ["taskkill.exe"]

    /// What a Stop asks to close and then ends: what `games` counts, less
    /// wine's own and `notAsked`.
    ///
    /// Wine's own includes the tools a fix installer runs through wine --
    /// reg.exe, regedit.exe, cmd.exe. `games` counts those, so that a launch
    /// closes nothing under an installer; a Stop must not turn that into a
    /// kill five seconds later, between `reg.exe add` and the flush that
    /// BottleProcesses.stillThere describes. They are left to closeBottle, as
    /// every Stop left them before.
    nonisolated static func condemned(among processes: [BottleProcesses.Running],
                                      notGames: Set<String>) -> [BottleProcesses.Running] {
        BottleProcesses.games(among: processes, notGames: notGames.union(BottleProcesses.wineOwn).union(notAsked))
    }

    /// Whether a Stop ended anything the title it was pressed for is not
    /// known by: a process named none of `knownNames`, compared as `games`
    /// compares, lowercased and at lsof's cut.
    ///
    /// A Stop ends every game in the bottle, and a launch goes into a bottle
    /// with a game already running in it, so the other game can be another
    /// store's title: a Steam title beside an Epic one in the Steam bottle,
    /// which holds both clients here. Its own tracker stands down on the
    /// Stop, so nothing else waits for its exit sync. Which store such a
    /// process belongs to is not known from its name, so every store present
    /// is waited for. A helper of the title's own that it is not known by --
    /// a crash handler -- reads as another game too. That direction costs a
    /// Stop a wait, bounded as every wait here is; the other would cost a
    /// sync.
    nonisolated static func endedAnotherTitle(_ condemned: [BottleProcesses.Running], knownNames: [String]) -> Bool {
        !BottleProcesses.games(among: condemned, notGames: Set(knownNames)).isEmpty
    }

    /// Which of Steam's exit syncs to wait for, or nil for none.
    ///
    /// The ended game's own, when a game was ended and it is a Steam title;
    /// every title's for the toolbar, which cannot know, and whenever the
    /// Stop ended a game its title is not known by -- see endedAnotherTitle.
    /// And every title's whenever one was already running before the Stop --
    /// a game that exited on its own a moment earlier -- since Steam is about
    /// to be asked to leave.
    nonisolated static func steamWait(target: Target, aGameWasEnded: Bool, anotherTitleWasEnded: Bool,
                                      underWay: Set<String>) -> SteamExitSync.Scope? {
        if aGameWasEnded {
            switch target {
            case .steamTitle(let id):
                return !anotherTitleWasEnded && underWay.isSubset(of: [id]) ? .app(id) : .anyApp
            case .everything:
                return .anyApp
            case .epicTitle, .otherTitle:
                if anotherTitleWasEnded { return .anyApp }
            }
        }
        return underWay.isEmpty ? nil : .anyApp
    }

    /// Whether to wait for the Epic launcher to settle: the ended game is an
    /// Epic title, the toolbar cannot say, or the Stop ended a game its title
    /// is not known by; or a launcher sync was already running before the
    /// Stop.
    nonisolated static func waitsForEpic(target: Target, aGameWasEnded: Bool, anotherTitleWasEnded: Bool,
                                         underWay: Bool) -> Bool {
        underWay || (aGameWasEnded && (anotherTitleWasEnded || target == .epicTitle || target == .everything))
    }

    /// The image names to hand taskkill, one for each process to ask, so two
    /// processes of one name are both asked: wine's taskkill marks a single
    /// process for each /IM it is given (programs/taskkill/taskkill.c,
    /// mark_task_process, Wine 11.0 sources on this machine).
    ///
    /// taskkill compares the whole image name, and lsof cuts a name at 31
    /// characters, so a name at that length is resolved against the names
    /// the title is known by when exactly one of them fits; otherwise it is
    /// handed over as lsof gave it and, if that was cut, taskkill finds
    /// nothing and the process is ended after the grace. A name that would
    /// need quoting in the shell is not handed over at all, for the same end.
    nonisolated static func imageNames(toAsk condemned: [BottleProcesses.Running], knownNames: [String]) -> [String] {
        let limit = BottleProcesses.lsofNameLimit
        return condemned.compactMap { process -> String? in
            var name = process.name
            if name.count >= limit {
                let cut = name.lowercased().prefix(limit)
                let fits = Set(knownNames.filter { $0.lowercased().prefix(limit) == cut })
                if fits.count == 1, let whole = fits.first { name = whole }
            }
            guard !name.isEmpty, !name.contains(where: { "\"$`\\".contains($0) }) else { return nil }
            return name
        }
    }

    nonisolated static func taskkillArguments(_ names: [String]) -> String {
        names.map { "/IM \"\($0)\"" }.joined(separator: " ")
    }

    /// The stop, in order.
    ///
    /// 1. The exit-sync logs are opened, before anything is ended: Steam
    ///    writes an exit sync within the same second a game stops, and a tail
    ///    opened after the kill would begin past its first line.
    /// 2. The game: every process `condemned` counts is asked to close, given
    ///    the grace, and those same processes -- pid and name, see
    ///    stillThere -- that are still there are ended. Steam, the Epic
    ///    launcher and wine's own processes, its tools included, are never
    ///    among them.
    ///    `gameEnded` is told then, before any wait: the game is over for the
    ///    window, as its tracker's onTerminate has it once the game exits.
    /// 3. The exit syncs: Steam's and the Epic launcher's, of the clients in
    ///    the bottle, for every title ended -- see endedAnotherTitle -- each
    ///    bounded as the teardown after a session bounds it.
    /// 4. Each client still in the bottle is asked to leave -- never one that
    ///    is not there.
    /// 5. closeBottle, decided at the generation of the press.
    ///
    /// A game launched into the bottle during the stop leaves the rest to
    /// that launch, which closes what it finds for itself -- see
    /// LeftOpenSession. The kill in step 2 is not held back for it: it is
    /// matched to processes that were running when the Stop began.
    ///
    /// `knownNames` are the executables the pressed title is known by, the
    /// same names stopEverything completes lsof's cut names from.
    ///
    /// The steps are parameters so a test can run the order on recorded
    /// steps; the Stop buttons pass the real ones through `stopEverything`.
    static func run(target: Target, generation: Int, bottle: String,
                    knownNames: [String],
                    watchExitSyncs: () -> UnderWay,
                    gamesToEnd: () async -> [BottleProcesses.Running],
                    askToClose: ([BottleProcesses.Running]) async throws -> Void,
                    grace: ([BottleProcesses.Running]) async -> Void,
                    scan: () async -> [BottleProcesses.Running],
                    kill: ([BottleProcesses.Running]) -> Void,
                    gameEnded: () -> Void,
                    clients: () async -> StoreClients,
                    waitForSteamExitSync: (SteamExitSync.Scope, Set<String>) async throws -> Void,
                    waitForEpicExitSync: () async throws -> Void,
                    quitEpic: () async throws -> Void,
                    quitSteam: () async throws -> Void,
                    closeBottle: (_ clients: [String]) async throws -> Void) async throws -> Outcome {
        func launchedSinceTheStop() -> Bool {
            guard LaunchGeneration.shared.supersedes(generation, for: bottle) else { return false }
            console.log("stop: a game has been launched into this bottle since Stop was pressed; leaving the rest to it")
            return true
        }

        let underWay = watchExitSyncs()

        let condemned = await gamesToEnd()
        if condemned.isEmpty {
            console.log("stop: no game is running in this bottle")
        } else {
            // A request that could not be sent is not a reason to leave a hung
            // game running: the kill after the grace still comes.
            do {
                try await askToClose(condemned)
            } catch {
                console.error("stop: could not ask the game to close: \(error.localizedDescription)")
            }
            await grace(condemned)
            let stubborn = BottleProcesses.stillThere(await scan(), of: condemned)
            if !stubborn.isEmpty { kill(stubborn) }
        }
        gameEnded()
        if launchedSinceTheStop() { return .leftToANewerLaunch }

        let anotherTitle = endedAnotherTitle(condemned, knownNames: knownNames)
        let present = await clients()
        if present.steam,
           let scope = steamWait(target: target, aGameWasEnded: !condemned.isEmpty,
                                 anotherTitleWasEnded: anotherTitle, underWay: underWay.steam) {
            try await waitForSteamExitSync(scope, underWay.steam)
            if launchedSinceTheStop() { return .leftToANewerLaunch }
        }
        if present.epicLauncher,
           waitsForEpic(target: target, aGameWasEnded: !condemned.isEmpty,
                        anotherTitleWasEnded: anotherTitle, underWay: underWay.epic) {
            try await waitForEpicExitSync()
            if launchedSinceTheStop() { return .leftToANewerLaunch }
        }

        // Asked again: after a wait of up to a minute, a client that left in
        // that time must not be asked -- for Steam, that would start one. Nor
        // a Steam a teardown already asked just before the Stop: it is on its
        // way out -- see SteamShutdowns.
        let leaving = await clients()
        if leaving.epicLauncher {
            try await quitEpic()
            if launchedSinceTheStop() { return .leftToANewerLaunch }
        }
        if leaving.asksSteam {
            try await quitSteam()
            if launchedSinceTheStop() { return .leftToANewerLaunch }
        }
        try await closeBottle(leaving.closeBottleClients)
        return .closed
    }
}
