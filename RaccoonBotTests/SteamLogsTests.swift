//
//  SteamLogsTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

private func tempLog(_ contents: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("steamlog-\(UUID().uuidString).txt")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func append(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
    try handle.close()
}

@Suite("Reading Steam's logs forward")
struct SteamLogTailTests {

    /// The whole bug in one test: the log already contains a successful sync
    /// from an earlier game, and that must not count as this one's.
    @Test func whatWasAlreadyThereIsNotNews() throws {
        let url = try tempLog("[AppID 485510] Successfully synced to ChangeNumber 3\n")
        let tail = SteamLogTail(url: url)
        #expect(tail.newLines().isEmpty)
    }

    @Test func linesWrittenAfterwardsAreRead() throws {
        let url = try tempLog("old line\n")
        let tail = SteamLogTail(url: url)
        try append("first\nsecond\n", to: url)
        #expect(tail.newLines() == ["first", "second"])
    }

    @Test func nothingIsDeliveredTwice() throws {
        let url = try tempLog("old\n")
        let tail = SteamLogTail(url: url)
        try append("once\n", to: url)
        #expect(tail.newLines() == ["once"])
        #expect(tail.newLines().isEmpty)
    }

    /// Steam writes a line at a time, and half a line has fooled this code
    /// before. An unterminated line waits for its newline.
    @Test func aHalfWrittenLineWaits() throws {
        let url = try tempLog("old\n")
        let tail = SteamLogTail(url: url)
        try append("complete\nhalf of a li", to: url)
        #expect(tail.newLines() == ["complete"])
        try append("ne\n", to: url)
        #expect(tail.newLines() == ["half of a line"])
    }

    /// Steam rotates its logs when it restarts.
    @Test func aRotatedLogIsReadFromTheStart() throws {
        let url = try tempLog("plenty of old content here to make the file long\n")
        let tail = SteamLogTail(url: url)
        try "fresh\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(tail.newLines() == ["fresh"])
    }

    @Test func aMissingLogIsQuietRatherThanFatal() {
        let tail = SteamLogTail(url: URL(fileURLWithPath: "/nowhere/at/all.txt"))
        #expect(tail.newLines().isEmpty)
    }
}

@Suite("What Steam says it started and stopped")
struct SteamGameProcessLogTests {

    private func watcher(_ seed: String = "seed\n") throws -> (SteamGameProcessLog, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("steamproc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("logs"),
                                                withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("logs/gameprocess_log.txt")
        try seed.write(to: log, atomically: true, encoding: .utf8)
        return (SteamGameProcessLog(steamPath: dir.path, steamID: "1340990"), log)
    }

    @Test func aStartedProcessIsReportedWithItsPath() throws {
        let (w, log) = try watcher()
        try append(#"[2026-08-28 11:15:11] AppID 1340990 adding PID 1304 as a tracked process ""Z:\Volumes\X8\common\Ronin\game.exe""#  + "\n", to: log)
        let events = w.poll()
        #expect(events.count == 1)
        guard case .started(let pid, let path) = events[0] else { Issue.record("not a start"); return }
        #expect(pid == 1304)
        #expect(path.hasSuffix("game.exe"))
    }

    @Test func anExitCodeSurvivesBeingNegative() throws {
        let (w, log) = try watcher()
        try append("[2026-08-28 11:10:25] AppID 1340990 no longer tracking PID 1308, exit code -1073741819\n", to: log)
        let events = w.poll()
        guard case .stopped(let pid, let code) = events.first else { Issue.record("not a stop"); return }
        #expect(pid == 1308)
        #expect(code == -1073741819)
        #expect(describeExit(code: code).contains("access violation"))
    }

    /// Reported, but never acted on.
    @Test func removalFromTheRunningListIsReported() throws {
        let (w, log) = try watcher()
        try append("[2026-08-28 11:17:20] Remove 1340990 from running list\n", to: log)
        guard case .sessionEnded = w.poll().first else { Issue.record("not a session end"); return }
    }

    @Test func anotherGameIsNotOurs() throws {
        let (w, log) = try watcher()
        try append("[2026-08-28 11:17:20] AppID 485510 adding PID 99 as a tracked process \"\"C:\\nioh.exe\"\n", to: log)
        try append("[2026-08-28 11:17:20] Remove 485510 from running list\n", to: log)
        #expect(w.poll().isEmpty)
    }

    /// A launcher exiting is a stop, never a session end -- the distinction the
    /// whole change rests on.
    @Test func aLauncherExitingIsNotTheSessionEnding() throws {
        let (w, log) = try watcher()
        try append("[2026-08-28 11:15:11] AppID 1340990 adding PID 100 as a tracked process \"\"Z:\\launcher.exe\"\n", to: log)
        try append("[2026-08-28 11:15:12] AppID 1340990 no longer tracking PID 100, exit code 0\n", to: log)
        try append("[2026-08-28 11:15:13] AppID 1340990 adding PID 200 as a tracked process \"\"Z:\\game.exe\"\n", to: log)
        let events = w.poll()
        #expect(events.count == 3)
        #expect(!events.contains { if case .sessionEnded = $0 { return true } else { return false } })
    }

    /// Red Dead Redemption 2, replayed from this machine's own log. The whole
    /// Rockstar chain exits, Steam declares the app gone, and one second later
    /// it starts again -- with the game itself forty-four seconds further on.
    /// A teardown anywhere in that window kills a launching game.
    @Test func aLauncherChainThatRestartsIsNotASessionEnding() throws {
        let (w, log) = try watcher()
        let t0 = Date()
        try append("""
        [2026-06-22 16:25:40] AppID 1340990 adding PID 2136 as a tracked process ""Z:\\PlayRDR2.exe"
        [2026-06-22 16:25:42] AppID 1340990 adding PID 2148 as a tracked process ""C:\\Launcher.exe"
        [2026-06-22 16:26:05] AppID 1340990 no longer tracking PID 2148, exit code 0
        [2026-06-22 16:26:05] AppID 1340990 no longer tracking PID 2136, exit code 0
        [2026-06-22 16:26:05] Remove 1340990 from running list

        """, to: log)
        w.poll(now: t0)
        #expect(w.tracked.isEmpty)
        #expect(w.emptySince != nil)                        // the question is asked
        #expect(w.hasBeenIdle(for: 120, now: t0.addingTimeInterval(44)) == false)  // and not yet answered

        // One second later the chain restarts, as it really does.
        try append("[2026-06-22 16:26:06] AppID 1340990 adding PID 2384 as a tracked process \"\"C:\\Launcher.exe\"\n", to: log)
        w.poll(now: t0.addingTimeInterval(1))
        #expect(w.emptySince == nil)                        // cancelled
        #expect(w.hasBeenIdle(for: 120, now: t0.addingTimeInterval(600)) == false)
    }

    @Test func aRealEndingSurvivesTheWait() throws {
        let (w, log) = try watcher()
        let t0 = Date()
        try append("[..] AppID 1340990 adding PID 100 as a tracked process \"\"Z:\\game.exe\"\n", to: log)
        w.poll(now: t0)
        try append("[..] AppID 1340990 no longer tracking PID 100, exit code 0\n", to: log)
        w.poll(now: t0.addingTimeInterval(60))
        #expect(w.hasBeenIdle(for: 120, now: t0.addingTimeInterval(100)) == false)
        #expect(w.hasBeenIdle(for: 120, now: t0.addingTimeInterval(181)) == true)
    }

    /// Before anything has started, an empty set means "not yet", not "over".
    @Test func nothingHavingStartedIsNotIdleness() throws {
        let (w, _) = try watcher()
        w.poll()
        #expect(w.emptySince == nil)
        #expect(w.hasBeenIdle(for: 0) == false)
    }

    /// Steam restarting voids everything it knew.
    @Test func aSteamRestartClearsWhatItKnew() throws {
        let (w, log) = try watcher()
        try append("[..] AppID 1340990 adding PID 100 as a tracked process \"\"Z:\\game.exe\"\n", to: log)
        w.poll()
        #expect(w.tracked == [100])
        try append("[..] Client version: 1234567890\n", to: log)
        w.poll()
        #expect(w.tracked.isEmpty)
        #expect(w.emptySince == nil)
    }

    /// The bottle is shared. A teardown decided for a game that finished must
    /// not take down a game that has not.
    @Test func anotherGameUsingTheBottleIsVisible() throws {
        let (w, log) = try watcher()
        try append("[..] AppID 1340990 adding PID 100 as a tracked process \"\"Z:\\ours.exe\"\n", to: log)
        try append("[..] AppID 485510 adding PID 200 as a tracked process \"\"Z:\\theirs.exe\"\n", to: log)
        w.poll()
        #expect(w.tracked == [100])
        #expect(w.otherAppRunning == "485510")

        // Ours finishes; theirs is still playing.
        try append("[..] AppID 1340990 no longer tracking PID 100, exit code 0\n", to: log)
        w.poll()
        #expect(w.tracked.isEmpty)
        #expect(w.otherAppRunning == "485510")   // so: do not touch the bottle

        // Theirs finishes too.
        try append("[..] AppID 485510 no longer tracking PID 200, exit code 0\n", to: log)
        w.poll()
        #expect(w.otherAppRunning == nil)
    }

    /// Another game's processes must not keep our own idle clock from starting.
    @Test func anotherGamesProcessesDoNotCountAsOurs() throws {
        let (w, log) = try watcher()
        let t0 = Date()
        try append("[..] AppID 1340990 adding PID 100 as a tracked process \"\"Z:\\ours.exe\"\n", to: log)
        w.poll(now: t0)
        try append("[..] AppID 1340990 no longer tracking PID 100, exit code 0\n", to: log)
        try append("[..] AppID 485510 adding PID 200 as a tracked process \"\"Z:\\theirs.exe\"\n", to: log)
        w.poll(now: t0)
        #expect(w.emptySince != nil)
        #expect(w.hasBeenIdle(for: 120, now: t0.addingTimeInterval(200)) == true)
        #expect(w.otherAppRunning == "485510")
    }

    /// Starting and closing are different problems. A launcher chain cycling
    /// belongs to starting, and every one on this machine happened inside the
    /// first sixty-three seconds. A game that ran and then stopped has stopped.
    @Test func aLongSessionIsNotWaitedOnLikeAShortOne() {
        #expect(steamIdleGrace(forSessionLasting: 62) == 120)      // the worst dip seen
        #expect(steamIdleGrace(forSessionLasting: 5 * 60) == 120)  // still cautious
        #expect(steamIdleGrace(forSessionLasting: 20 * 60) == 15)  // plainly a session
        #expect(steamIdleGrace(forSessionLasting: 3 * 3600) == 15)
    }

    @Test func theSessionIsMeasuredFromTheFirstProcessToTheLast() throws {
        let (w, log) = try watcher()
        let t0 = Date()
        try append("[..] AppID 1340990 adding PID 100 as a tracked process \"\"Z:\\game.exe\"\n", to: log)
        w.poll(now: t0)
        #expect(w.sessionLength == 0)          // nothing has stopped yet

        try append("[..] AppID 1340990 no longer tracking PID 100, exit code 0\n", to: log)
        w.poll(now: t0.addingTimeInterval(3600))
        #expect(w.sessionLength == 3600)
        #expect(steamIdleGrace(forSessionLasting: w.sessionLength) == 15)
    }

    /// A game that dies seconds after starting gets the careful treatment.
    @Test func aGameThatDiesOnStartupIsStillWaitedOn() throws {
        let (w, log) = try watcher()
        let t0 = Date()
        try append("[..] AppID 1340990 adding PID 100 as a tracked process \"\"Z:\\launcher.exe\"\n", to: log)
        w.poll(now: t0)
        try append("[..] AppID 1340990 no longer tracking PID 100, exit code 0\n", to: log)
        w.poll(now: t0.addingTimeInterval(25))
        #expect(steamIdleGrace(forSessionLasting: w.sessionLength) == 120)
    }

    /// Counted from this machine's cloud logs. The one that was missed --
    /// "Upload complete, result OK" -- cost three minutes of waiting after a
    /// six-second upload had already finished.
    @Test(arguments: [
        "[2026-08-28 16:34:14] [AppID 1340990] Upload complete, result OK",
        "[2026-08-28 14:43:48] [AppID 1340990] Upload complete in build list",
        "[2026-08-28 11:15:09] [AppID 1340990] Successfully synced to ChangeNumber 0",
        "[2026-08-28 11:17:20] [AppID 1340990] Failed sync for 'AC Exit,Sync Disabled,' [login=false]",
    ])
    func everyEndingSteamActuallyWritesIsRecognised(_ line: String) {
        #expect(SteamCloudSyncWatcher.isTerminalForTesting(line))
    }

    /// These sit in the middle of a sync. Treating them as the end would let
    /// the teardown start while files were still going up.
    @Test(arguments: [
        "[..] [AppID 1340990] AutoCloud complete",
        "[..] [AppID 1340990] Need to upload file KoeiTecmo/Ronin/Savedata/x/SAVEDATA.BIN",
        "[..] [AppID 1340990] Starting sync (up,AC Exit,)",
        "[..] [AppID 1340990] Running AutoCloud on exit. Looking for new and updated files",
    ])
    func theMiddleOfASyncIsNotTheEnd(_ line: String) {
        #expect(SteamCloudSyncWatcher.isTerminalForTesting(line) == false)
    }

    /// The exit codes that actually appear in this machine's log. Every
    /// launcher handoff ended 0, 1 or 3; every crash is a Windows exception.
    @Test(arguments: [
        (-1073741819, true),   // 0xC0000005 access violation
        (-1073740972, true),   // 0xC0000374 heap corruption
        (-1073740791, true),   // 0xC0000409 stack buffer overrun
        (-2147483392, true),
        (0, false), (1, false), (3, false),
    ])
    func aCrashIsToldApartFromAnOrdinaryExit(_ c: (code: Int, isCrash: Bool)) throws {
        let (w, log) = try watcher()
        try append("[..] AppID 1340990 adding PID 100 as a tracked process \"\"Z:\\game.exe\"\n", to: log)
        w.poll()
        try append("[..] AppID 1340990 no longer tracking PID 100, exit code \(c.code)\n", to: log)
        w.poll()
        #expect(w.lastExitWasACrash == c.isCrash)
    }

    /// The case Mathias asked about: a game that falls over two minutes in
    /// still closes promptly, because a crash is not a handoff.
    @Test func aGameThatCrashesEarlyDoesNotWaitLikeALauncher() {
        #expect(steamIdleGrace(forSessionLasting: 120, crashed: false) == 120)
        #expect(steamIdleGrace(forSessionLasting: 120, crashed: true) == 15)
        #expect(steamIdleGrace(forSessionLasting: 5, crashed: true) == 15)
    }

    /// A new process starting clears the last verdict: what matters is how the
    /// current session ended, not the one before it.
    @Test func startingAgainForgetsHowTheLastOneEnded() throws {
        let (w, log) = try watcher()
        try append("[..] AppID 1340990 adding PID 100 as a tracked process \"\"Z:\\game.exe\"\n", to: log)
        try append("[..] AppID 1340990 no longer tracking PID 100, exit code -1073741819\n", to: log)
        w.poll()
        #expect(w.lastExitWasACrash)
        try append("[..] AppID 1340990 adding PID 200 as a tracked process \"\"Z:\\game.exe\"\n", to: log)
        w.poll()
        #expect(w.lastExitWasACrash == false)
    }

    /// The line that made MGS4 invisible. Steam uses it when it takes an app
    /// down itself, and not understanding it left the tracked set holding
    /// processes that were already dead.
    @Test func theOtherWaySteamSaysAProcessEndedIsUnderstood() throws {
        let (w, log) = try watcher()
        try append("[..] AppID 1340990 adding PID 1664 as a tracked process \"\"Z:\\launcher.exe\"\n", to: log)
        try append("[..] AppID 1340990 adding PID 1684 as a tracked process \"\"Z:\\helper.exe\"\n", to: log)
        w.poll()
        #expect(w.tracked == [1664, 1684])

        try append("[..] Game 1340990 going away; no longer tracking PID 1664\n", to: log)
        try append("[..] Game 1340990 going away; no longer tracking PID 1684\n", to: log)
        w.poll()
        #expect(w.tracked.isEmpty)
        #expect(w.emptySince != nil)
    }

    @Test func anotherGameGoingAwayIsNotOurs() throws {
        let (w, log) = try watcher()
        try append("[..] AppID 1340990 adding PID 100 as a tracked process \"\"Z:\\ours.exe\"\n", to: log)
        try append("[..] Game 485510 going away; no longer tracking PID 999\n", to: log)
        w.poll()
        #expect(w.tracked == [100])
    }
}

@Suite("Telling a game apart from the furniture")
struct BottleFurnitureTests {

    /// Named from what actually runs in this bottle. Everything not on the
    /// list is somebody's game, which is the only way to ask "is anyone
    /// playing?" without keeping a list per title.
    @Test(arguments: [
        "wineserver", "services.exe", "plugplay.exe", "rpcss.exe",
        "explorer.exe", "svchost.exe", "winedevice.exe", "winewrapper.exe",
        "steam.exe", "steamwebhelper.exe", "steamservice.exe",
        "steamerrorreporter64.exe",
    ])
    func wineAndSteamsOwnProcessesAreNotGames(_ name: String) {
        #expect(BottleProcesses.infrastructure.contains(name))
    }

    @Test(arguments: ["Ronin.exe", "nioh.exe", "launcher.exe", "RDR2.exe",
                      "UnityCrashHandler64.exe", "MGSRVersion.exe"])
    func anythingElseCountsAsSomebodyPlaying(_ name: String) {
        #expect(BottleProcesses.infrastructure.contains(name.lowercased()) == false)
    }
}
