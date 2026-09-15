//
//  SteamLaunchIdentification.swift
//  RaccoonBot
//
//  How a Steam title is recognised once its launch command has run, kept apart
//  from the waiting so the rules can be tested without a Steam.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Recognising a Steam title is what makes its session close the moment it
/// ends.
///
/// The executable's name is what the termination observer in getGameTracker
/// matches when a game exits. A title that is never recognised is still
/// closed, but by the process log's idle grace instead -- two minutes for a
/// session under five -- and that is the whole difference between Steam
/// leaving the second a short session ends and Steam sitting on screen after
/// it.
///
/// The wait used to be timed from the launch command, ninety seconds for each
/// of its two steps, and Steam can take longer than that to start anything.
/// Measured in the Steam bottle on 2026-09-15, three launches of Ninja Gaiden
/// 3, each into a Steam that started fresh for it (each begins with a new
/// "Client version" line) and took 29 to 33 seconds to come up. In the first,
/// RaccoonBot's command ran at 00:40:29 and Steam's LaunchApp then waited for a
/// user response at its ShowInterstitials step from 00:41:12 to 00:42:30, so
/// the game was started at 00:42:31, two minutes after the command. What Steam
/// showed in that time is not in its logs. In the other two the same step
/// passed within the second, the game was started about thirty-five seconds
/// after the command, and Steam was asked to leave within a second of the game
/// exiting, which only a recognised title does. After the first, Steam was
/// still open a minute and a half after the game had exited, when it was
/// closed by hand.
///
/// RaccoonBot's own log of that session was not kept, so which of the two
/// steps ran out is read from the code, not seen: the process log already
/// held earlier Ninja Gaiden 3 entries, the first step answers from those on
/// its first read, and the second step's ninety seconds then end before
/// 00:42:31.
///
/// So past the old limit the clock counts from when Steam starts the title,
/// not from when it was asked to. Everything up to the old limit is exactly as
/// it was; only what happens after it has changed, and only for a name read
/// inside the old limit that is the one executable Steam started -- see
/// `step(now:oldLimit:launchBegan:named:steam:bottleTakenOver:)` and
/// `startedOnly(_:executables:)`.
nonisolated enum SteamLaunchIdentification {
    /// How long each step waits once there is something to look for -- the
    /// limit the whole wait used to have.
    static let patience: TimeInterval = 90

    /// How long a launch waits for Steam to start anything for it at all.
    ///
    /// Chosen, not measured, the way the Epic tracker's half hour was: long
    /// enough for a Steam that updates itself, asks somebody to sign in, or
    /// waits on its own window before it starts the title -- the one such wait
    /// measured was 78 seconds -- and short enough that an abandoned launch
    /// does not leave a watch behind for the rest of the day, to claim a title
    /// somebody starts later from Steam's own window.
    static let steamStartLimit: TimeInterval = 30 * 60

    /// What Steam's own process log has said about this title since the launch.
    enum SteamRecord: Equatable {
        /// No process log is followed -- a native title -- so nothing can say
        /// whether Steam has started it, and the wait is what it always was.
        case unwatched
        /// Steam has written nothing for this title since the launch.
        case startedNothing
        /// Steam started a process for this title, the first of this launch
        /// at `at`. `executables` names every process it has started for the
        /// title since, in order, the way `trackedExecutable` names them.
        case started(at: Date, executables: [String])
    }

    enum Step: Equatable {
        /// Look for the title now.
        case look
        /// Steam has started nothing for this title yet, so there is nothing
        /// to look for. Not a failure: Steam may still be starting, or waiting
        /// on something of its own before it starts the title.
        case wait
        /// The title was not recognised in time. Never a reason to close
        /// anything -- see the MGS4 comment where getGameTracker handles it.
        case giveUp
        /// Another launch into this bottle, or a Stop, has taken it over
        /// while this was still waiting past the old limit -- for Steam to
        /// start the title, or for a title Steam had started to be seen
        /// running.
        case standDown
    }

    /// What recognising the title came to.
    enum Identification: Equatable {
        case found(String)
        /// Steam gave no name that was seen running in time. Not evidence
        /// that nothing is running -- see the MGS4 comment in getGameTracker.
        case notFound
        /// Another launch into this bottle, or a Stop, took it over while
        /// this was still waiting past the old limit.
        case stoodDown
    }

    /// What a step of the wait should do at `now`.
    ///
    /// `oldLimit` is when the old wait would have stopped this step looking;
    /// `launchBegan` is when the first step began. `named` is the name the
    /// step looks for: nil while the name itself is still being read, and
    /// empty when that step found none.
    static func step(now: Date, oldLimit: Date, launchBegan: Date, named: String?,
                     steam: SteamRecord, bottleTakenOver: Bool) -> Step {
        if now <= oldLimit { return .look }

        // Past the old limit only a name read inside it is looked for. The
        // step that reads the name gives up here, as it always did, and so
        // does a step with no name to look for -- see startedOnly for what a
        // name first read any later would be.
        guard let named, !named.isEmpty else { return .giveUp }

        let beyondTheOldLimit: Step
        switch steam {
        case .unwatched:
            return .giveUp
        case .startedNothing:
            if now > launchBegan.addingTimeInterval(steamStartLimit) { return .giveUp }
            beyondTheOldLimit = .wait
        case .started(let at, let executables):
            // The same patience, counted from when Steam started the title.
            if now > at.addingTimeInterval(patience) { return .giveUp }
            guard startedOnly(named, executables: executables) else { return .giveUp }
            beyondTheOldLimit = .look
        }
        // Only here, past the point where the old wait had already ended, and
        // whether Steam started the title before that point or after it. A
        // newer launch into this bottle has its own tracker, and this one
        // recognising that launch's title would call onLoad for it and hand
        // back an observer that replaces the newer one's.
        return bottleTakenOver ? .standDown : beyondTheOldLimit
    }

    /// Whether Steam has started one executable for the title and nothing
    /// else, and it is the one being looked for.
    ///
    /// The name is read from the whole cumulative log, so for a title played
    /// before it is whatever Steam started last in an earlier session -- and
    /// that is not always the game. Counted in the Steam bottle's process log
    /// per start of Steam: 14 of MGS4's 44 starts end on
    /// "UnityCrashHandler64.exe --attach", a helper that exited in the same
    /// second as its launcher in every such session read, and 13 of Nioh's 41
    /// ran nothing but nioh_launcher.exe. Inside the old limit that has always
    /// been so, and it is left alone. Past it, a name is looked for only while
    /// it is all Steam has started: 43 of those 44 MGS4 starts begin with
    /// launcher.exe and the other with the game's command line, so a crash
    /// handler's name does not pass there. Nor does the game's own name for
    /// Nioh, Red Dead Redemption 2 or an Unreal title that starts a bootstrap
    /// and then a -Shipping executable: it gives up as soon as Steam logs the
    /// launcher it starts first, which is where the old wait ended up whenever
    /// Steam was late.
    ///
    /// What still passes is a name equal to the first executable Steam starts,
    /// until Steam logs the next one: nioh_launcher.exe, when the last Nioh
    /// session ran nothing else, in the 3 to 73 seconds Steam took to start
    /// nioh.exe after it in the 28 starts that got that far. That is reasoned
    /// from the log, not seen; the launch inside the old limit has had the same
    /// exposure all along, and shutDown still refuses to close a bottle with a
    /// game running in it.
    ///
    /// A title with no entry of its own in the log is not looked for late at
    /// all, which is why `step` wants a name read inside the old limit. The
    /// first name a later read found would be whatever Steam started first for
    /// this launch, and for a title with a chain that is its launcher: the
    /// first Nioh entry in the Steam bottle's process log, on 2026-08-26, names
    /// nioh_launcher.exe. Recognised by that name, the launcher's exit is what
    /// the observer would act on, and the game's exit would not match. The
    /// cost is that the first launch of a title Steam starts as one executable,
    /// when Steam is late, is closed by the idle grace, as it was before.
    static func startedOnly(_ named: String, executables: [String]) -> Bool {
        Set(executables) == [named]
    }

    /// The executable one of Steam's "adding PID" lines names for `appID`, as
    /// SteamLaunchWatcher has always read it; nil for any other line.
    ///
    /// Not the same reading as SteamGameProcessLog's quoted path, and not
    /// meant to be: this is the name the termination observer compares, and
    /// changing what it yields changes which exit closes a session. For a line
    /// whose entry is a command line -- MGS4's game -- it yields a string no
    /// running application is ever called. MGS4's launcher, logged with no
    /// arguments, yields "launcher.exe", and its crash handler
    /// "UnityCrashHandler64.exe"; the tests pin all three.
    static func trackedExecutable(in line: some StringProtocol, appID: String) -> String? {
        let line = String(line)
        guard line.contains("AppID \(appID) adding PID") else { return nil }
        return line.firstMatch(of: #/[^\\]+\.exe/#).map { String($0.output) } ?? "not found"
    }

    /// The executable named by the last "adding PID" line for `appID` in a
    /// whole log, or nil when there is none.
    ///
    /// Split by lines, not by "[": splitting on the bracket that opens each
    /// entry's timestamp works until a path contains one, and Ninja Gaiden 3
    /// installs into "[NINJA GAIDEN Master Collection] NINJA GAIDEN 3 Razor's
    /// Edge". The line broke in the middle, the AppID landed in one piece and
    /// the executable in another, and the game was never identified.
    ///
    /// The log is cumulative -- the Steam bottle's goes back to June -- so for
    /// a title played before, this answers from an earlier session on the
    /// first read, before Steam has started anything for this one.
    static func lastTrackedExecutable(inLog content: String, appID: String) -> String? {
        var found: String?
        for line in content.split(whereSeparator: \.isNewline) {
            if let named = trackedExecutable(in: line, appID: appID) { found = named }
        }
        return found
    }

    /// How one step of the wait ended.
    enum Outcome<Found> {
        case found(Found)
        case gaveUp
        case stoodDown
    }

    /// Why the wait released the window.
    enum WindowRelease: Equatable {
        /// Steam had started nothing by the moment the old wait gave up.
        case steamHasStartedNothing
        /// The wait ended without recognising the title.
        case notRecognised
    }
}

extension SteamLaunchIdentification.Outcome: Equatable where Found: Equatable {}

/// One launch's wait to recognise its title, shared by both of its steps.
///
/// It keeps what the steps must agree on: the clock they run on, and whether
/// the window has already been released, so that it is released once.
nonisolated final class SteamIdentificationWait {
    let launchBegan: Date
    private let steamRecord: () -> SteamLaunchIdentification.SteamRecord
    private let bottleTakenOver: () -> Bool
    private let releaseWindow: (SteamLaunchIdentification.WindowRelease) -> Void
    private let now: () -> Date
    private let sleep: () async throws -> Void
    private var oldLimit: Date?
    private(set) var releasedTheWindow = false

    /// No defaults for what the wait is told: one built without a process log
    /// and a takeover check waits exactly as the old wait did, and a call that
    /// left them out would bring the defect back without a word. That makes
    /// leaving them out fail to compile, and no more; getGameTracker builds
    /// its wait with `init(following:bottleTakenOver:releaseWindow:now:sleep:)`.
    ///
    /// `now` and `sleep` are the clock both steps run on, a second a look.
    /// `launchBegan` defaults to the clock's now.
    init(launchBegan: Date? = nil,
         steamRecord: @escaping () -> SteamLaunchIdentification.SteamRecord,
         bottleTakenOver: @escaping () -> Bool,
         releaseWindow: @escaping (SteamLaunchIdentification.WindowRelease) -> Void,
         now: @escaping () -> Date = { Date() },
         sleep: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 1_000_000_000) }) {
        self.launchBegan = launchBegan ?? now()
        self.steamRecord = steamRecord
        self.bottleTakenOver = bottleTakenOver
        self.releaseWindow = releaseWindow
        self.now = now
        self.sleep = sleep
    }

    /// Starts a step at `at`, or at the clock's now, with the ninety seconds
    /// of looking the old wait gave every step from its start.
    ///
    /// A second step never begins later than the old wait began it. It
    /// begins inside the first step's limit when the first read a name, and
    /// just past it when the first gave up with none -- `step` does not let
    /// the first read a name past its limit.
    func beginStep(at: Date? = nil) {
        oldLimit = (at ?? now()).addingTimeInterval(SteamLaunchIdentification.patience)
    }

    func next(named: String?, at: Date? = nil) -> SteamLaunchIdentification.Step {
        let moment = at ?? now()
        if oldLimit == nil { beginStep(at: moment) }
        let step = SteamLaunchIdentification.step(now: moment, oldLimit: oldLimit!,
                                                  launchBegan: launchBegan, named: named,
                                                  steam: steamRecord(),
                                                  bottleTakenOver: bottleTakenOver())
        // A step waits only past its old limit, with a name read inside the
        // first step's. Of the two steps SteamLaunchWatcher runs, that is the
        // second, past its ninety seconds: the moment the old wait gave up and
        // released the window. So the window is released at the first wait,
        // and a Steam that never starts the title leaves it dimmed as long as
        // the old wait did. A title that shows up later is still recognised,
        // and onLoad marks it playing again -- the same thing the process-log
        // watch does when a game comes back after a gap.
        if step == .wait { releaseWindowOnce(.steamHasStartedNothing) }
        return step
    }

    /// Releases the window unless this wait already has.
    ///
    /// onTerminate clears whatever is marked as playing, and by the time a
    /// wait that already released the window ends, that need not be this
    /// title.
    func releaseWindowOnce(_ why: SteamLaunchIdentification.WindowRelease) {
        guard !releasedTheWindow else { return }
        releasedTheWindow = true
        releaseWindow(why)
    }

    /// One step: every second, ask `next` and, when it says so, `look`.
    ///
    /// While Steam has started nothing, `look` is not called. The looks before
    /// the old limit have already read everything that was there, and reading
    /// the whole log or listing every running application each second for as
    /// long as Steam takes would find nothing new.
    @MainActor
    func run<Found>(named: String?, look: () -> Found?) async throws -> SteamLaunchIdentification.Outcome<Found> {
        beginStep(at: now())
        while true {
            try await sleep()
            switch next(named: named, at: now()) {
            case .standDown:
                return .stoodDown
            case .giveUp:
                return .gaveUp
            case .wait:
                continue
            case .look:
                if let found = look() { return .found(found) }
            }
        }
    }
}

extension SteamIdentificationWait {
    /// The wait getGameTracker builds: told what Steam has started by the
    /// process log it follows, asked afresh at every step, or -- for a native
    /// title, which has no log -- told nothing, so it waits as the old wait
    /// did.
    @MainActor
    convenience init(following processLog: SteamGameProcessLog?,
                     bottleTakenOver: @escaping () -> Bool,
                     releaseWindow: @escaping (SteamLaunchIdentification.WindowRelease) -> Void,
                     now: @escaping () -> Date = { Date() },
                     sleep: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 1_000_000_000) }) {
        self.init(steamRecord: { processLog?.identificationRecord ?? .unwatched },
                  bottleTakenOver: bottleTakenOver,
                  releaseWindow: releaseWindow,
                  now: now,
                  sleep: sleep)
    }

    /// Both steps, as SteamLaunchWatcher runs them: read the name Steam gives
    /// the title from its whole process log, then wait for something by that
    /// name to be running.
    ///
    /// Here rather than in the watcher so that the tests run it: the name each
    /// step is handed decides everything past the old limit. `readLog` returns
    /// the whole log, or nil when it cannot be read; `runningExecutables`
    /// names what is running now; `log` is handed the lines the watcher has
    /// always written.
    @MainActor
    func recognise(appID: String,
                   readLog: () -> String?,
                   runningExecutables: () -> [String],
                   log: (String) -> Void) async throws -> SteamLaunchIdentification.Identification {
        let naming: SteamLaunchIdentification.Outcome<String> = try await run(named: nil) {
            readLog().flatMap { SteamLaunchIdentification.lastTrackedExecutable(inLog: $0, appID: appID) }
        }
        let appName: String
        switch naming {
        case .found(let named):
            appName = named
        case .gaveUp:
            // Empty, as it always was. The second step still spends the ninety
            // seconds it spent before the window was released, and past them
            // `step` has no name to go on with.
            log("\(appID): App name fetching timed out")
            appName = ""
        case .stoodDown:
            return .stoodDown
        }
        log("App name found: \(appName)")
        let running: SteamLaunchIdentification.Outcome<String> = try await run(named: appName) {
            runningExecutables().contains(appName) ? appName : nil
        }
        switch running {
        case .found(let named):
            return .found(named)
        case .gaveUp:
            log("\(appID): Launch tracking timed out")
            return .notFound
        case .stoodDown:
            return .stoodDown
        }
    }
}
