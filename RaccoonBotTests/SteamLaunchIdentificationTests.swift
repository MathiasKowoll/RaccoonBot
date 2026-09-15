//
//  SteamLaunchIdentificationTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// A time on the day the late start was measured, as Steam's logs print it.
private func at(_ clock: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.date(from: "2026-09-15 \(clock)")!
}

private typealias ID = SteamLaunchIdentification

private let ng3 = "NINJA GAIDEN 3 Razor's Edge.exe"

// Lines copied from the Steam bottle's gameprocess_log.txt.
private let ninjaGaiden3Line = #"[2026-09-15 00:42:31] AppID 1369760 adding PID 1452 as a tracked process ""Z:\Volumes\Crucial X8\SteamLibraryCross\steamapps\common\[NINJA GAIDEN Master Collection] NINJA GAIDEN 3 Razor's Edge\NINJA GAIDEN 3 Razor's Edge.exe"""#
private let earlierNinjaGaiden3Line = #"[2026-08-28 20:23:13] AppID 1369760 adding PID 1340 as a tracked process ""Z:\Volumes\Crucial X8\SteamLibraryCross\steamapps\common\[NINJA GAIDEN Master Collection] NINJA GAIDEN 3 Razor's Edge\NINJA GAIDEN 3 Razor's Edge.exe"""#
private let steamStartedLine = "[2026-09-15 00:41:05] Client version: 1788652215"
private let niohFirstEntry = #"[2026-08-26 14:21:09] AppID 485510 adding PID 1488 as a tracked process ""Z:\Volumes\Crucial X8\SteamLibraryCross\steamapps\common\Nioh\nioh_launcher.exe"""#
private let mgs4CommandLine = #"[2026-08-27 12:49:23] AppID 2492670 adding PID 1724 as a tracked process "-region eu -lan en -selfregion EU -resolution 0 -launcherpath launcher.exe -ctrltype AUTO -launcherroot  "Z:\Volumes\Crucial X8\SteamLibraryCross\steamapps\common\METAL GEAR SOLID 4\launcher"""#
private let mgs4LauncherWithArguments = #"[2026-08-27 12:18:00] AppID 2492670 adding PID 2720 as a tracked process ""Z:\Volumes\Crucial X8\SteamLibraryCross\steamapps\common\METAL GEAR SOLID 4\Launcher\launcher.exe" eu -lan en -selfregion EU -resolution 0 -launcherpath launcher.exe -ctrltype AUTO -launcherroot  "Z:\Volumes\Crucial X8\SteamLibraryCross\steamapps\common\METAL GEAR SOLID 4\launcher"""#
private let mgs4BareLauncher = #"[2026-08-27 12:16:52] AppID 2492670 adding PID 2372 as a tracked process ""Z:\Volumes\Crucial X8\SteamLibraryCross\steamapps\common\METAL GEAR SOLID 4\Launcher\launcher.exe"""#
private let mgs4CrashHandler = #"[2026-08-27 12:16:53] AppID 2492670 adding PID 2408 as a tracked process ""Z:\Volumes\Crucial X8\SteamLibraryCross\steamapps\common\METAL GEAR SOLID 4\Launcher\UnityCrashHandler64.exe" --attach 2372 58855424""#
private let mgs4ErrorReporter = #"[2026-08-27 12:16:56] AppID 2492670 adding PID 2472 as a tracked process "C:\Program Files (x86)\Steam\steamerrorreporter64.exe -pid=2372""#

/// A clock a test turns: a second each time the wait sleeps.
private final class TurnedClock {
    private(set) var now: Date
    /// Runs after each second, with the new time: where a test has Steam
    /// write, or starts something.
    var onTick: (Date) throws -> Void = { _ in }

    init(_ start: Date) { now = start }

    func tick() throws {
        now = now.addingTimeInterval(1)
        try onTick(now)
    }
}

/// A wait whose Steam record and takeover a test sets, on a clock it turns,
/// keeping every release and when it came.
private final class Probe {
    let clock: TurnedClock
    var steam: ID.SteamRecord = .startedNothing
    var takenOver = false
    var releases: [ID.WindowRelease] = []
    var releasedAt: [Date] = []

    init(_ start: Date) { clock = TurnedClock(start) }

    func wait() -> SteamIdentificationWait {
        SteamIdentificationWait(launchBegan: clock.now,
                                steamRecord: { self.steam },
                                bottleTakenOver: { self.takenOver },
                                releaseWindow: { why in
                                    self.releases.append(why)
                                    self.releasedAt.append(self.clock.now)
                                },
                                now: { self.clock.now },
                                sleep: { try self.clock.tick() })
    }
}

/// A process log in a directory of its own, opened the way getGameTracker
/// opens it: after `seed` was written, so it reads only what follows.
@MainActor
private func followedLog(appID: String, seed: [String]) throws -> (SteamGameProcessLog, URL) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("steamident-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("logs"),
                                            withIntermediateDirectories: true)
    let log = dir.appendingPathComponent("logs/gameprocess_log.txt")
    try seed.map { $0 + "\r\n" }.joined().write(to: log, atomically: true, encoding: .utf8)
    return (SteamGameProcessLog(steamPath: dir.path, steamID: appID), log)
}

/// Steam writes CRLF, so this does too.
private func append(_ lines: [String], to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(lines.map { $0 + "\r\n" }.joined().utf8))
    try handle.close()
}

@Suite("Recognising a Steam title that Steam starts late")
struct SteamLaunchIdentificationWaitTests {

    /// The session that did not close, replayed from the Steam bottle's logs
    /// of 2026-09-15. The command ran at 00:40:29 and Steam started the game at
    /// 00:42:31, after waiting at its ShowInterstitials step. By the code, the
    /// first read of the log a second after the command named the game from
    /// earlier sessions' entries, so the second step began then -- and its
    /// ninety seconds ended before Steam started anything.
    @Test func theLateStartThatDidNotCloseIsStillRecognised() {
        let launch = at("00:40:29")
        let oldLimit = at("00:40:30").addingTimeInterval(ID.patience)
        func step(_ now: String, _ steam: ID.SteamRecord) -> ID.Step {
            ID.step(now: at(now), oldLimit: oldLimit, launchBegan: launch, named: ng3,
                    steam: steam, bottleTakenOver: false)
        }

        // What the old wait did: gave up half a minute before Steam started
        // the game.
        #expect(step("00:42:01", .unwatched) == .giveUp)

        // Steam had started nothing by then, so there was nothing to give up on.
        #expect(step("00:42:01", .startedNothing) == .wait)

        // Once Steam started it, it is looked for again, with the same patience.
        let started = ID.SteamRecord.started(at: at("00:42:31"), executables: [ng3])
        #expect(step("00:42:32", started) == .look)
        #expect(step("00:44:01", started) == .look)
        #expect(step("00:44:02", started) == .giveUp)
    }

    /// The sessions that closed at once: the game started about thirty-five
    /// seconds after the command. Nothing inside the old limit changes, not
    /// even for a name the late part would refuse, nor for a bottle taken
    /// over.
    @Test func aTitleStartedWithinTheOldLimitIsLookedForExactlyAsBefore() {
        let launch = at("00:53:02")
        let oldLimit = at("00:53:03").addingTimeInterval(ID.patience)
        let records: [ID.SteamRecord] = [
            .unwatched, .startedNothing,
            .started(at: at("00:53:37"), executables: [ng3]),
            .started(at: at("00:53:37"), executables: ["launcher.exe", "UnityCrashHandler64.exe"]),
        ]
        for steam in records {
            for named in [ng3, "UnityCrashHandler64.exe", "", nil] as [String?] {
                #expect(ID.step(now: at("00:53:38"), oldLimit: oldLimit, launchBegan: launch, named: named,
                                steam: steam, bottleTakenOver: true) == .look)
            }
        }
    }

    /// A native title has no process log to ask, and waits what it always did.
    @Test func withoutAProcessLogTheWaitIsWhatItWas() {
        let t0 = Date()
        let oldLimit = t0.addingTimeInterval(90)
        #expect(ID.step(now: t0.addingTimeInterval(90), oldLimit: oldLimit, launchBegan: t0, named: ng3,
                        steam: .unwatched, bottleTakenOver: false) == .look)
        #expect(ID.step(now: t0.addingTimeInterval(91), oldLimit: oldLimit, launchBegan: t0, named: ng3,
                        steam: .unwatched, bottleTakenOver: false) == .giveUp)
        // A launch taking the bottle does not turn that into a stand-down.
        #expect(ID.step(now: t0.addingTimeInterval(91), oldLimit: oldLimit, launchBegan: t0, named: ng3,
                        steam: .unwatched, bottleTakenOver: true) == .giveUp)
    }

    /// A title Steam started within seconds gives up when it always did, give
    /// or take those seconds -- and giving up closes nothing.
    @Test func aTitleSteamStartedEarlyGivesUpWhenItAlwaysDid() {
        let t0 = Date()
        let oldLimit = t0.addingTimeInterval(91)
        let steam = ID.SteamRecord.started(at: t0.addingTimeInterval(5), executables: [ng3])
        #expect(ID.step(now: t0.addingTimeInterval(92), oldLimit: oldLimit, launchBegan: t0, named: ng3,
                        steam: steam, bottleTakenOver: false) == .look)
        #expect(ID.step(now: t0.addingTimeInterval(96), oldLimit: oldLimit, launchBegan: t0, named: ng3,
                        steam: steam, bottleTakenOver: false) == .giveUp)
    }

    /// A Steam that never starts the title is not waited on for ever.
    @Test func nothingStartedIsNotWaitedOnForever() {
        let t0 = Date()
        let oldLimit = t0.addingTimeInterval(90)
        #expect(ID.step(now: t0.addingTimeInterval(ID.steamStartLimit), oldLimit: oldLimit, launchBegan: t0,
                        named: ng3, steam: .startedNothing, bottleTakenOver: false) == .wait)
        #expect(ID.step(now: t0.addingTimeInterval(ID.steamStartLimit + 1), oldLimit: oldLimit, launchBegan: t0,
                        named: ng3, steam: .startedNothing, bottleTakenOver: false) == .giveUp)
    }

    /// A newer launch into the bottle ends only the part of the wait the old
    /// code never had. Before the old limit, and once this one has given up,
    /// it changes nothing.
    @Test func aBottleTakenOverEndsOnlyTheLongerWait() {
        let t0 = Date()
        let oldLimit = t0.addingTimeInterval(90)
        func step(_ now: TimeInterval, _ steam: ID.SteamRecord) -> ID.Step {
            ID.step(now: t0.addingTimeInterval(now), oldLimit: oldLimit, launchBegan: t0, named: ng3,
                    steam: steam, bottleTakenOver: true)
        }
        #expect(step(30, .startedNothing) == .look)
        #expect(step(120, .startedNothing) == .standDown)
        #expect(step(120, .started(at: t0.addingTimeInterval(100), executables: [ng3])) == .standDown)
        #expect(step(120, .started(at: t0.addingTimeInterval(10), executables: [ng3])) == .giveUp)
        #expect(step(120, .started(at: t0.addingTimeInterval(100), executables: ["a.exe", ng3])) == .giveUp)
    }

    /// Standing down is not only for a Steam that had started nothing by the
    /// old limit. A title Steam started before it and not yet seen running is
    /// still looked for past it, and a newer launch ends that as well.
    @Test func aTitleSteamStartedBeforeTheOldLimitStandsDownToo() {
        let t0 = Date()
        let steam = ID.SteamRecord.started(at: t0.addingTimeInterval(80), executables: [ng3])
        func step(_ now: TimeInterval, takenOver: Bool) -> ID.Step {
            ID.step(now: t0.addingTimeInterval(now), oldLimit: t0.addingTimeInterval(91), launchBegan: t0,
                    named: ng3, steam: steam, bottleTakenOver: takenOver)
        }
        #expect(step(100, takenOver: false) == .look)
        #expect(step(100, takenOver: true) == .standDown)
        #expect(step(171, takenOver: true) == .giveUp)
    }

    /// The review's case. 14 of MGS4's 44 starts in the Steam bottle end on
    /// its crash handler, so after one of them the whole-file read names
    /// "UnityCrashHandler64.exe". Steam starts launcher.exe before it (43 of
    /// 44 starts; the other begins with the command line), so past the old
    /// limit that name is never what Steam has started alone.
    @Test func aCrashHandlersNameFromAnEarlierSessionIsNotRecognisedLate() throws {
        let t0 = Date()
        let oldLimit = t0.addingTimeInterval(91)
        let name = "UnityCrashHandler64.exe"
        let commandLine = try #require(ID.trackedExecutable(in: mgs4CommandLine, appID: "2492670"))
        func step(_ now: TimeInterval, _ executables: [String]) -> ID.Step {
            ID.step(now: t0.addingTimeInterval(now), oldLimit: oldLimit, launchBegan: t0, named: name,
                    steam: .started(at: t0.addingTimeInterval(150), executables: executables),
                    bottleTakenOver: false)
        }
        #expect(step(151, ["launcher.exe"]) == .giveUp)
        #expect(step(152, ["launcher.exe", name]) == .giveUp)
        #expect(step(152, ["launcher.exe", name, "steamerrorreporter64.exe", commandLine]) == .giveUp)
        #expect(step(151, [commandLine]) == .giveUp)
        // Inside the old limit it is looked for, as it always was. Written
        // down as what the code does, not as something to keep.
        #expect(step(60, ["launcher.exe", name]) == .look)
    }

    /// Titles Steam starts as a chain are left, past the old limit, to the
    /// process log, as they were before whenever Steam was late.
    @Test func aChainIsNotRecognisedLate() {
        let t0 = Date()
        let oldLimit = t0.addingTimeInterval(91)
        func step(_ named: String, _ executables: [String]) -> ID.Step {
            ID.step(now: t0.addingTimeInterval(200), oldLimit: oldLimit, launchBegan: t0, named: named,
                    steam: .started(at: t0.addingTimeInterval(190), executables: executables),
                    bottleTakenOver: false)
        }
        #expect(step("nioh.exe", ["nioh_launcher.exe", "nioh.exe"]) == .giveUp)
        #expect(step("nioh.exe", ["nioh_launcher.exe"]) == .giveUp)
        #expect(step("BeastOfReincarnation-Win64-Shipping.exe",
                     ["BeastOfReincarnation.exe", "BeastOfReincarnation-Win64-Shipping.exe"]) == .giveUp)
        #expect(step("PlayRDR2.exe", ["PlayRDR2.exe", "Launcher.exe"]) == .giveUp)
        // One executable, and it is the name: what the late part is for. A
        // relaunch inside the same Steam logs it twice.
        #expect(step(ng3, [ng3]) == .look)
        #expect(step(ng3, [ng3, ng3]) == .look)
    }

    /// What still passes, written down as what the rule does and not as a rule
    /// to keep: a launcher's name, when an earlier session ran nothing but
    /// the launcher, until Steam logs what the launcher starts.
    @Test func aLauncherThatIsAllSteamHasStartedStillPasses() {
        let t0 = Date()
        #expect(ID.step(now: t0.addingTimeInterval(200), oldLimit: t0.addingTimeInterval(91), launchBegan: t0,
                        named: "nioh_launcher.exe",
                        steam: .started(at: t0.addingTimeInterval(190), executables: ["nioh_launcher.exe"]),
                        bottleTakenOver: false) == .look)
    }

    /// The review's second case. With no name read inside the old limit --
    /// a title with no entry of its own, like Nioh before its first, which
    /// names nioh_launcher.exe -- nothing is looked for past it, whatever
    /// Steam has started and whoever has the bottle. A name read later would
    /// be that launcher's.
    @Test func noNameIsLookedForThatWasNotReadInsideTheOldLimit() {
        let t0 = Date()
        let records: [ID.SteamRecord] = [
            .startedNothing,
            .started(at: t0.addingTimeInterval(120), executables: ["nioh_launcher.exe"]),
            .started(at: t0.addingTimeInterval(120), executables: [ng3]),
        ]
        for steam in records {
            for named in [nil, ""] as [String?] {
                for takenOver in [false, true] {
                    #expect(ID.step(now: t0.addingTimeInterval(121), oldLimit: t0.addingTimeInterval(90),
                                    launchBegan: t0, named: named, steam: steam,
                                    bottleTakenOver: takenOver) == .giveUp)
                }
            }
        }
    }

    /// A first step that read no name ends just past its limit, and the
    /// second then has its own ninety seconds, looking for nothing, before
    /// it gives up -- as the old wait's did.
    @Test func aSecondStepAfterTheFirstReadNoNameGetsItsOwnNinetySeconds() {
        let t0 = Date()
        let probe = Probe(t0)
        let wait = probe.wait()
        wait.beginStep(at: t0)
        #expect(wait.next(named: nil, at: t0.addingTimeInterval(90)) == .look)
        #expect(wait.next(named: nil, at: t0.addingTimeInterval(91)) == .giveUp)
        wait.beginStep(at: t0.addingTimeInterval(91))
        #expect(wait.next(named: "", at: t0.addingTimeInterval(181)) == .look)
        #expect(wait.next(named: "", at: t0.addingTimeInterval(182)) == .giveUp)
        #expect(probe.releases.isEmpty)
    }

    /// A second step begun inside the old limit has its own ninety seconds, as
    /// it always had.
    @Test func aSecondStepBegunInsideTheOldLimitGetsItsOwnNinetySeconds() {
        let t0 = Date()
        let probe = Probe(t0)
        probe.steam = .started(at: t0.addingTimeInterval(10), executables: ["nioh_launcher.exe", "nioh.exe"])
        let wait = probe.wait()
        wait.beginStep(at: t0)
        wait.beginStep(at: t0.addingTimeInterval(50))
        #expect(wait.next(named: "nioh.exe", at: t0.addingTimeInterval(140)) == .look)
        #expect(wait.next(named: "nioh.exe", at: t0.addingTimeInterval(141)) == .giveUp)
    }

    /// The window is released once, at the first wait: the second step past
    /// its ninety seconds, which is when the old wait gave up and released
    /// it. A title that turns up afterwards is still looked for, and the
    /// release getGameTracker makes when the wait comes back empty does not
    /// happen a second time.
    @Test func theWindowIsReleasedOnceWhenTheOldWaitGaveUp() {
        let t0 = Date()
        let probe = Probe(t0)
        let wait = probe.wait()
        wait.beginStep(at: t0)
        // The name, from an earlier session, on the first read.
        wait.beginStep(at: t0.addingTimeInterval(1))

        #expect(wait.next(named: ng3, at: t0.addingTimeInterval(91)) == .look)
        #expect(probe.releases.isEmpty)
        #expect(wait.next(named: ng3, at: t0.addingTimeInterval(92)) == .wait)
        #expect(probe.releases == [.steamHasStartedNothing])
        #expect(wait.releasedTheWindow)
        #expect(wait.next(named: ng3, at: t0.addingTimeInterval(240)) == .wait)
        #expect(probe.releases.count == 1)

        probe.steam = .started(at: t0.addingTimeInterval(250), executables: [ng3])
        #expect(wait.next(named: ng3, at: t0.addingTimeInterval(251)) == .look)
        wait.releaseWindowOnce(.notRecognised)
        #expect(probe.releases == [.steamHasStartedNothing])
    }

    /// A wait that ends without recognising the title releases the window
    /// once, however many times it is asked to.
    @Test func aWaitThatEndsUnrecognisedReleasesTheWindowOnce() {
        let t0 = Date()
        let probe = Probe(t0)
        probe.steam = .started(at: t0.addingTimeInterval(5), executables: ["launcher.exe", "UnityCrashHandler64.exe"])
        let wait = probe.wait()
        wait.beginStep(at: t0.addingTimeInterval(1))
        #expect(wait.next(named: "UnityCrashHandler64.exe", at: t0.addingTimeInterval(200)) == .giveUp)
        #expect(probe.releases.isEmpty)
        wait.releaseWindowOnce(.notRecognised)
        wait.releaseWindowOnce(.notRecognised)
        #expect(probe.releases == [.notRecognised])
    }

    /// A title Steam has started keeps the window until it is recognised or
    /// the wait gives up, and getGameTracker releases it then. That can be
    /// later than the old wait released it: the look goes on for ninety
    /// seconds from when Steam started the title.
    @Test func aTitleSteamStartedKeepsTheWindowUntilTheWaitEnds() {
        let t0 = Date()
        let probe = Probe(t0)
        probe.steam = .started(at: t0.addingTimeInterval(170), executables: [ng3])
        let wait = probe.wait()
        wait.beginStep(at: t0)
        #expect(wait.next(named: ng3, at: t0.addingTimeInterval(200)) == .look)
        #expect(wait.next(named: ng3, at: t0.addingTimeInterval(261)) == .giveUp)
        #expect(probe.releases.isEmpty)
        #expect(wait.releasedTheWindow == false)
    }

    /// Standing down says nothing to the window: it belongs to the newer launch.
    @Test func standingDownNeverReleasesTheWindow() {
        let t0 = Date()
        let probe = Probe(t0)
        probe.takenOver = true
        let wait = probe.wait()
        wait.beginStep(at: t0)
        #expect(wait.next(named: ng3, at: t0.addingTimeInterval(200)) == .standDown)
        #expect(probe.releases.isEmpty)
    }
}

/// The loop both steps run, on a clock the test turns.
@Suite("The wait's loop")
@MainActor
struct SteamIdentificationRunTests {

    /// Replays the late start second by second. Before the old limit it looks
    /// every second; while Steam has started nothing it does not look at all;
    /// once Steam starts the title it looks again and finds it.
    @Test func itDoesNotLookWhileSteamHasStartedNothing() async throws {
        let t0 = Date()
        let probe = Probe(t0)
        probe.clock.onTick = { [unowned probe] now in
            if now >= t0.addingTimeInterval(200) {
                probe.steam = .started(at: t0.addingTimeInterval(200), executables: [ng3])
            }
        }
        var looks = 0
        let outcome: ID.Outcome<String> = try await probe.wait().run(named: ng3) {
            looks += 1
            return probe.clock.now >= t0.addingTimeInterval(205) ? ng3 : nil
        }
        guard case .found(let name) = outcome else { Issue.record("expected found, got \(outcome)"); return }
        #expect(name == ng3)
        // Seconds 1 to 90 inside the old limit, then 200 to 205.
        #expect(looks == 90 + 6)
        // The first second past the old limit, while Steam had started nothing.
        #expect(probe.releases == [.steamHasStartedNothing])
        #expect(probe.releasedAt == [t0.addingTimeInterval(91)])
    }

    @Test func aNameFoundInsideTheOldLimitIsReturnedAtOnce() async throws {
        let probe = Probe(Date())
        var looks = 0
        let outcome: ID.Outcome<String> = try await probe.wait().run(named: nil) {
            looks += 1
            return looks == 3 ? ng3 : nil
        }
        guard case .found(let name) = outcome else { Issue.record("expected found, got \(outcome)"); return }
        #expect(name == ng3)
        #expect(looks == 3)
    }

    @Test func aStepThatRunsOutGivesUp() async throws {
        let probe = Probe(Date())
        probe.steam = .unwatched
        var looks = 0
        let outcome: ID.Outcome<String> = try await probe.wait().run(named: ng3) {
            looks += 1
            return nil
        }
        guard case .gaveUp = outcome else { Issue.record("expected gaveUp, got \(outcome)"); return }
        #expect(looks == 90)
        #expect(probe.releases.isEmpty)
    }

    @Test func aStepTakenOverStandsDownWithoutLookingAgain() async throws {
        let probe = Probe(Date())
        probe.takenOver = true
        var looks = 0
        let outcome: ID.Outcome<String> = try await probe.wait().run(named: ng3) {
            looks += 1
            return nil
        }
        guard case .stoodDown = outcome else { Issue.record("expected stoodDown, got \(outcome)"); return }
        #expect(looks == 90)
        #expect(probe.releases.isEmpty)
    }
}

/// What getGameTracker hands the wait: the process log's record, and the
/// bottle's takeover.
@Suite("What the wait is told")
@MainActor
struct SteamIdentificationSourcesTests {

    /// The record counts only what Steam wrote after the log was opened, and
    /// forgets it when Steam starts again -- which is why an earlier session
    /// cannot answer it the way it answers the name.
    @Test func theRecordIsWhatSteamStartedSinceTheLogWasOpened() throws {
        let (log, url) = try followedLog(appID: "1369760", seed: [ninjaGaiden3Line])
        log.poll()
        #expect(log.identificationRecord == .startedNothing)

        let started = at("00:42:31")
        try append([steamStartedLine, ninjaGaiden3Line], to: url)
        log.poll(now: started)
        #expect(log.identificationRecord == .started(at: started, executables: [ng3]))

        try append(["[2026-09-15 00:45:20] Client version: 1788652215"], to: url)
        log.poll()
        #expect(log.identificationRecord == .startedNothing)

        // What the restarted Steam starts is counted afresh, not added to what
        // the last one started: a title started twice would otherwise look
        // like a chain.
        let restarted = at("00:45:25")
        try append([ninjaGaiden3Line.replacingOccurrences(of: "PID 1452", with: "PID 1400")], to: url)
        log.poll(now: restarted)
        #expect(log.identificationRecord == .started(at: restarted, executables: [ng3]))
    }

    /// Named the way the observer's name is read, in order, from MGS4's own
    /// lines -- so the late part can tell a crash handler from the only thing
    /// Steam started.
    @Test func everyExecutableIsNamedAsTheNameIs() throws {
        let (log, url) = try followedLog(appID: "2492670", seed: ["seed"])
        let started = Date()
        try append([mgs4BareLauncher, mgs4CrashHandler, mgs4ErrorReporter, mgs4CommandLine], to: url)
        log.poll(now: started)
        let commandLine = try #require(ID.trackedExecutable(in: mgs4CommandLine, appID: "2492670"))
        #expect(log.identificationRecord == .started(
            at: started,
            executables: ["launcher.exe", "UnityCrashHandler64.exe", "steamerrorreporter64.exe", commandLine]))
    }

    /// Without a process log -- a native title -- the wait getGameTracker
    /// builds is told nothing, and gives up at the old limit as it did.
    @Test func withoutAProcessLogTheWaitIsToldNothing() {
        let t0 = Date()
        let wait = SteamIdentificationWait(following: nil, bottleTakenOver: { false }, releaseWindow: { _ in })
        wait.beginStep(at: t0)
        #expect(wait.next(named: ng3, at: t0.addingTimeInterval(91)) == .giveUp)
    }

    /// A newer launch, or a Stop pressed on this generation, takes the bottle;
    /// a Stop is not about a launch made after it.
    @Test func aNewerLaunchOrAStopTakesTheBottle() {
        let generations = LaunchGeneration()
        let bottle = "file:///Users/someone/Library/Application%20Support/RaccoonBot/CXPBottles/Steam-\(UUID().uuidString)/"
        let first = generations.launched(bottle: bottle)
        #expect(generations.takenOver(first, for: bottle) == false)
        generations.stopped(bottle: bottle)
        #expect(generations.takenOver(first, for: bottle))
        let second = generations.launched(bottle: bottle)
        #expect(generations.takenOver(first, for: bottle))
        #expect(generations.takenOver(second, for: bottle) == false)
    }
}

/// SteamLaunchWatcher's two steps, run on a turned clock against a process
/// log written the way Steam writes it, with the wait built the way
/// getGameTracker builds it. Not run: the watcher's own reading of the file
/// and listing of running applications, and which log getGameTracker hands
/// the wait.
@Suite("Both steps, as the watcher runs them")
@MainActor
struct SteamIdentificationBothStepsTests {

    /// What a run did to the window, how often it read the log, and when it
    /// ended.
    private final class Witness {
        var releases: [ID.WindowRelease] = []
        var releasedAt: [Date] = []
        var reads = 0
        var ended: Date?
    }

    /// Runs both steps from `start`. Steam writes `writes` into the log at
    /// the second after `start` each is keyed by, and `running` names what is
    /// running at each second.
    private func recognise(appID: String, seed: [String], start: Date,
                           writes: [TimeInterval: [String]],
                           running: @escaping (Date) -> [String]) async throws -> (ID.Identification, Witness) {
        let (processLog, url) = try followedLog(appID: appID, seed: seed)
        let clock = TurnedClock(start)
        let witness = Witness()
        clock.onTick = { now in
            if let lines = writes[now.timeIntervalSince(start)] { try append(lines, to: url) }
            // What getGameTracker's process-log watch does every second.
            processLog.poll(now: now)
        }
        let wait = SteamIdentificationWait(following: processLog,
                                           bottleTakenOver: { false },
                                           releaseWindow: { why in
                                               witness.releases.append(why)
                                               witness.releasedAt.append(clock.now)
                                           },
                                           now: { clock.now },
                                           sleep: { try clock.tick() })
        let identification = try await wait.recognise(
            appID: appID,
            readLog: {
                witness.reads += 1
                return try? String(contentsOf: url, encoding: .utf8)
            },
            runningExecutables: { running(clock.now) },
            log: { _ in })
        witness.ended = clock.now
        return (identification, witness)
    }

    /// The session that did not close. The log already holds Ninja Gaiden 3
    /// from 2026-08-28, so the first read names the game; Steam comes up at
    /// 00:41:05 and starts the game at 00:42:31. That it shows as running two
    /// seconds later is chosen for the test, not measured.
    @Test func theLateStartThatDidNotCloseIsRecognised() async throws {
        let (identification, witness) = try await recognise(
            appID: "1369760", seed: [earlierNinjaGaiden3Line], start: at("00:40:29"),
            writes: [36: [steamStartedLine], 122: [ninjaGaiden3Line]],
            running: { now in now >= at("00:42:33") ? [ng3] : [] })
        #expect(identification == .found(ng3))
        #expect(witness.ended == at("00:42:33"))
        #expect(witness.reads == 1)
        // Released the second the old wait gave up on the game.
        #expect(witness.releases == [.steamHasStartedNothing])
        #expect(witness.releasedAt == [at("00:42:01")])
    }

    /// MGS4 after a session that ended on its crash handler, so the first
    /// read names "UnityCrashHandler64.exe". Steam starts launcher.exe late,
    /// and in the second before it would log the crash handler, something by
    /// that name is already running -- constructed from the one second
    /// between those two lines in the log, not seen. It is not taken for the
    /// game.
    @Test func aCrashHandlersNameIsNotTakenForTheGameLate() async throws {
        let (identification, witness) = try await recognise(
            appID: "2492670", seed: [mgs4BareLauncher, mgs4CrashHandler], start: at("12:00:00"),
            writes: [120: [steamStartedLine, mgs4BareLauncher]],
            running: { now in now >= at("12:02:00") ? ["launcher.exe", "UnityCrashHandler64.exe"] : [] })
        #expect(identification == .notFound)
        #expect(witness.ended == at("12:02:00"))
        #expect(witness.releases == [.steamHasStartedNothing])
    }

    /// Nioh with no entry of its own yet, and a Steam that starts its launcher
    /// two minutes in. No name was read inside the old limit, so none is read
    /// after it and the launcher is not taken for the game. The wait ends when
    /// the old one did, having read the log for ninety seconds only.
    @Test func aFirstLaunchSteamStartsLateIsNotRecognisedByItsLauncher() async throws {
        let (identification, witness) = try await recognise(
            appID: "485510", seed: [ninjaGaiden3Line], start: at("14:00:00"),
            writes: [120: [steamStartedLine, niohFirstEntry]],
            running: { now in now >= at("14:02:01") ? ["nioh_launcher.exe"] : [] })
        #expect(identification == .notFound)
        #expect(witness.ended == at("14:03:02"))
        #expect(witness.reads == 90)
        // getGameTracker releases the window for a title it did not recognise.
        #expect(witness.releases.isEmpty)
    }

    /// The same title and a Steam that never starts anything: with no name to
    /// look for, the wait does not go on waiting on Steam.
    @Test func aFirstLaunchSteamNeverStartsEndsWhenTheOldWaitDid() async throws {
        let (identification, witness) = try await recognise(
            appID: "485510", seed: [ninjaGaiden3Line], start: at("14:00:00"),
            writes: [:], running: { _ in [] })
        #expect(identification == .notFound)
        #expect(witness.ended == at("14:03:02"))
        #expect(witness.releases.isEmpty)
    }
}

@Suite("The executable named in Steam's process log")
struct TrackedExecutableTests {

    @Test func theBracketedNinjaGaidenPathNamesTheGame() {
        #expect(ID.trackedExecutable(in: ninjaGaiden3Line, appID: "1369760") == ng3)
    }

    /// An entry with arguments after the quoted path, from 2026-08-26.
    @Test func argumentsAfterThePathAreNotPartOfTheName() {
        let line = #"[2026-08-26 21:02:57] AppID 485510 adding PID 1352 as a tracked process ""Z:\Volumes\Crucial X8\SteamLibraryCross\steamapps\common\Nioh\nioh.exe" --disable-d3d-debug""#
        #expect(ID.trackedExecutable(in: line, appID: "485510") == "nioh.exe")
    }

    /// MGS4, from 2026-08-27. Its game is recorded as a command line, and one
    /// form of its launcher's entry carries the same arguments after the path.
    /// Neither yields a name any running application has. That is not every
    /// MGS4 entry: see the next test.
    @Test(arguments: [mgs4CommandLine, mgs4LauncherWithArguments])
    func mgs4sCommandLineEntriesYieldNoRunnableName(_ line: String) throws {
        let name = try #require(ID.trackedExecutable(in: line, appID: "2492670"))
        #expect(name != "launcher.exe")
        #expect(name.contains("-launcherpath"), "got \(name)")
    }

    /// The MGS4 entries that do yield a running application's name: its
    /// launcher logged with no arguments, and its crash handler. Either can be
    /// the whole-file read's answer, when an earlier session ended on it.
    @Test func mgs4sLauncherAndCrashHandlerYieldTheirNames() {
        #expect(ID.trackedExecutable(in: mgs4BareLauncher, appID: "2492670") == "launcher.exe")
        #expect(ID.trackedExecutable(in: mgs4CrashHandler, appID: "2492670") == "UnityCrashHandler64.exe")
        #expect(ID.trackedExecutable(in: mgs4ErrorReporter, appID: "2492670") == "steamerrorreporter64.exe")
    }

    @Test func anotherAppsLineIsNotOurs() {
        #expect(ID.trackedExecutable(in: ninjaGaiden3Line, appID: "485510") == nil)
        // A shorter id that is a prefix of the real one is not a match either.
        #expect(ID.trackedExecutable(in: ninjaGaiden3Line, appID: "136976") == nil)
        #expect(ID.trackedExecutable(in: "[2026-09-15 00:43:03] AppID 1369760 no longer tracking PID 1452, exit code 0",
                                     appID: "1369760") == nil)
    }

    /// The last entry wins, read line by line, CRLF included.
    @Test func theLastEntryInTheLogWins() {
        let log = [
            #"[2026-08-26 21:03:49] AppID 485510 adding PID 1320 as a tracked process ""Z:\Nioh\nioh_launcher.exe"""#,
            #"[2026-08-26 21:03:54] AppID 485510 adding PID 1388 as a tracked process ""Z:\Nioh\nioh.exe" --disable-d3d-debug""#,
            "[2026-08-26 21:10:00] AppID 485510 no longer tracking PID 1388, exit code 0",
        ].joined(separator: "\r\n") + "\r\n"
        #expect(ID.lastTrackedExecutable(inLog: log, appID: "485510") == "nioh.exe")
        #expect(ID.lastTrackedExecutable(inLog: log, appID: "1369760") == nil)
    }

    /// What the whole-file read means on this machine, where the log is
    /// cumulative: an earlier session's entry names the game before Steam has
    /// started anything for this one. Written down as what the code does, not
    /// as a rule to keep -- for Ninja Gaiden 3 it is the same executable, so
    /// the wait for it to be running is what decided the late start.
    @Test func anEarlierSessionsEntryAnswersBeforeSteamHasStartedAnything() {
        let log = """
        [2026-09-15 00:45:20] Client version: 1788652215\r
        [2026-09-15 00:45:25] AppID 1369760 adding PID 1400 as a tracked process ""Z:\\Volumes\\Crucial X8\\SteamLibraryCross\\steamapps\\common\\[NINJA GAIDEN Master Collection] NINJA GAIDEN 3 Razor's Edge\\NINJA GAIDEN 3 Razor's Edge.exe""\r
        [2026-09-15 00:45:52] AppID 1369760 no longer tracking PID 1400, exit code 0\r
        [2026-09-15 00:45:52] Remove 1369760 from running list\r
        [2026-09-15 00:53:32] Client version: 1788652215\r

        """
        #expect(ID.lastTrackedExecutable(inLog: log, appID: "1369760") == ng3)
    }
}
