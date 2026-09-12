//
//  EpicSessionTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// The end of an Epic session: when the launcher is taken to be done, and
/// what the census counts as a game.
struct EpicSessionTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    /// The launcher writes its exit sync in one burst; silence after it is
    /// the end, whatever words it finished with.
    @Test func quietAfterHearingIsSettled() {
        var s = EpicSettle(started: t0)
        s.observe(line: "LogSomething: uploading", at: at(1))
        s.observe(line: "LogSomething: done", at: at(3))
        #expect(s.verdict(at: at(4)) == .waiting)
        #expect(s.verdict(at: at(7)) == .waiting, "four seconds of quiet is not five")
        #expect(s.verdict(at: at(8.1)) == .settled("the launcher has been quiet for 5s after 2 lines"))
    }

    /// Nothing said at all: cloud saves off, or not signed in. The full
    /// deadline would only delay the teardown.
    @Test func silenceFromTheStartRunsOutOfPatience() {
        let s = EpicSettle(started: t0)
        #expect(s.verdict(at: at(14)) == .waiting)
        #expect(s.verdict(at: at(15)) == .settled("the launcher said nothing for 15s; no exit sync is coming"))
    }

    /// A launcher that never stops talking -- verifying a game, say -- is
    /// not waited for past the deadline.
    @Test func theDeadlineHolds() {
        var s = EpicSettle(started: t0)
        for i in 0..<59 { s.observe(line: "chatter", at: at(Double(i))) }
        #expect(s.verdict(at: at(59.5)) == .waiting)
        #expect(s.verdict(at: at(60)) == .settled("the launcher was given 60s"))
    }

    /// The phrase, as the launcher actually writes it. These two lines are
    /// verbatim from this machine's own sessions on 2026-09-03 -- the pair it
    /// writes around a save sync -- with the ids left in place, since that is
    /// what the line looks like when this has to recognise it.
    @Test func theSyncIsOverWhenTheLauncherSaysItIsExiting() {
        let started = "[2026.09.03-16.56.27:229][567]LogCloudSync: Cloud Sync: Sync Started for c4763f236d08423eb47b4c3008779c84:93f2a8c3547846eda966cb3c152a026e:dc9d2e595d0e4650b35d659f90d41059"
        let ended = "[2026.09.03-16.56.34:282][668]LogCloudSync: Cloud Sync: Exiting Cloud Sync - SUCCESS - AppName: c4763f236d08423eb47b4c3008779c84:93f2a8c3547846eda966cb3c152a026e:dc9d2e595d0e4650b35d659f90d41059"
        #expect(!EpicSettle.isTerminal(started), "a sync that started has not ended")
        #expect(EpicSettle.isTerminal(ended))
    }

    /// A sync that failed has still finished, and waiting past it buys
    /// nothing -- the same rule the Steam watcher applies to "Failed sync
    /// for". Only the outcome is different, and the outcome is not what is
    /// being asked.
    @Test func aSyncThatEndedBadlyHasStillEnded() {
        #expect(EpicSettle.isTerminal("LogCloudSync: Cloud Sync: Exiting Cloud Sync - FAILURE - AppName: ns:item:app"))
    }

    @Test func ordinaryLauncherChatterIsNotTheEndOfASync() {
        #expect(!EpicSettle.isTerminal("LogCloudSync: Verbose: Cloud Sync: Retreived DSS Access Links  2026.06.09-22.03.07.manifest"))
        #expect(!EpicSettle.isTerminal("LogBPSInstallerConfig: Build Config: CloudDirectories: http://epicgames-download1.akamaized.net/"))
    }

    /// The launcher's own record of starting a title: the only party that
    /// knows the executable's name, since it is the launcher that starts it.
    /// Verbatim from a real session.
    @Test func theLaunchLineNamesTheExecutable() {
        let line = "[2026.09.03-16.46.50:506][264]FCommunityPortalLaunchAppTask: Launching app 'Z:/Volumes/Crucial X8/EpicGogGames/AlanWake2/AlanWake2.exe' with commandline ' -AUTH_LOGIN=unused -AUTH_PASSWORD=403548a8"
        #expect(EpicLauncherLogWatcher.launchedExecutable(in: line) == "AlanWake2.exe")
    }

    /// "Preparing to launch" comes first and means it may still fail. Taking
    /// it would start the clock on a launch that never happened.
    @Test func preparingToLaunchIsNotLaunching() {
        let line = "[2026.09.03-16.46.50:504][264]FCommunityPortalLaunchAppTask: Preparing to launch app 'Z:/Volumes/Crucial X8/EpicGogGames/AlanWake2/AlanWake2.exe' with commandline ' -AUTH_LOGIN=unused"
        #expect(EpicLauncherLogWatcher.launchedExecutable(in: line) == nil)
    }

    @Test func aPathWithBackslashesIsReadToo() {
        let line = #"FCommunityPortalLaunchAppTask: Launching app 'Z:\Volumes\Crucial X8\EpicGogGames\AlanWakeRemastered\Game_f_x64_EOS.exe' with commandline ''"#
        #expect(EpicLauncherLogWatcher.launchedExecutable(in: line) == "Game_f_x64_EOS.exe")
    }

    @Test func anythingElseNamesNothing() {
        #expect(EpicLauncherLogWatcher.launchedExecutable(in: "LogInit: Command Line: something") == nil)
        #expect(EpicLauncherLogWatcher.launchedExecutable(in: "FCommunityPortalLaunchAppTask: Launching app with no quotes") == nil)
        #expect(EpicLauncherLogWatcher.launchedExecutable(in: "") == nil)
    }

    /// The launcher, its helper and the EOS service are found where the
    /// launcher is installed, so the teardown does not mistake them for a
    /// game and refuse forever.
    @Test func theLaunchersExecutablesAreKnown() throws {
        let bottle = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bottle-\(UUID().uuidString)")
        let bin = bottle.appendingPathComponent("drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["EpicGamesLauncher.exe", "EpicWebHelper.exe", "readme.txt"] {
            FileManager.default.createFile(atPath: bin.appendingPathComponent(name).path, contents: Data())
        }
        defer { try? FileManager.default.removeItem(at: bottle) }
        let names = BottleProcesses.launchersOwnExecutables(inBottleAt: bottle)
        #expect(names == ["epicgameslauncher.exe", "epicwebhelper.exe"])
    }

    @Test func aBottleWithoutTheLauncherKnowsNone() {
        let bottle = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nobottle-\(UUID().uuidString)")
        #expect(BottleProcesses.launchersOwnExecutables(inBottleAt: bottle).isEmpty)
    }

    @Test func theLogIsWhereTheLauncherWritesIt() {
        let bottle = URL(fileURLWithPath: "/b")
        #expect(EpicLauncherLogWatcher.logURL(inBottleAt: bottle).path
                == "/b/drive_c/users/crossover/AppData/Local/EpicGamesLauncher/Saved/Logs/EpicGamesLauncher.log")
    }

    /// The save that would have been lost.
    ///
    /// The launcher syncs twice around a session -- pulling before it starts
    /// a title, pushing after it exits -- and both write the same "Exiting
    /// Cloud Sync". Reading the log from a file that already holds the PULL's
    /// line, the teardown's wait would be satisfied by it at once and the
    /// launcher asked to leave mid-upload. Draining at the moment the game
    /// starts is what separates the two.
    @Test func thePullSyncIsNotMistakenForThePushSync() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("epiclog-\(UUID().uuidString)")
        let logs = dir.appendingPathComponent("drive_c/users/crossover/AppData/Local/EpicGamesLauncher/Saved/Logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent("EpicGamesLauncher.log")
        defer { try? FileManager.default.removeItem(at: dir) }

        // The launcher is already running and has already pulled the saves
        // and started the title by the time the watcher is built.
        try """
        LogCloudSync: Cloud Sync: Sync Started for ns:item:app
        LogCloudSync: Cloud Sync: Exiting Cloud Sync - SUCCESS - AppName: ns:item:app
        FCommunityPortalLaunchAppTask: Launching app 'Z:/Games/Thing/Thing.exe' with commandline ''

        """.write(to: log, atomically: true, encoding: .utf8)

        // Built after those lines exist: the tail starts at the end of the
        // file, so it sees none of them -- which is the case this drain is
        // for, and the reason the drain is harmless when there is nothing to
        // drain.
        let watcher = EpicLauncherLogWatcher(bottle: dir)
        watcher.drainPastLaunch()

        // Now the title exits and the launcher pushes.
        try (try String(contentsOf: log, encoding: .utf8) + """
        LogCloudSync: Cloud Sync: Sync Started for ns:item:app
        LogCloudSync: Cloud Sync: Exiting Cloud Sync - SUCCESS - AppName: ns:item:app

        """).write(to: log, atomically: true, encoding: .utf8)

        let seen = watcher.linesForTesting()
        #expect(seen.contains { EpicSettle.isTerminal($0) }, "the push's line is there to be waited for")
        #expect(seen.filter { EpicSettle.isTerminal($0) }.count == 1,
                "and only that one: the pull's was drained, not counted twice")
    }

    /// A watcher built BEFORE the launcher writes anything sees the pull too,
    /// which is exactly why the drain exists rather than being optional.
    @Test func aDrainAfterTheLaunchLeavesOnlyWhatComesNext() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("epiclog-\(UUID().uuidString)")
        let logs = dir.appendingPathComponent("drive_c/users/crossover/AppData/Local/EpicGamesLauncher/Saved/Logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent("EpicGamesLauncher.log")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "".write(to: log, atomically: true, encoding: .utf8)

        let watcher = EpicLauncherLogWatcher(bottle: dir)
        try """
        LogCloudSync: Cloud Sync: Exiting Cloud Sync - SUCCESS - AppName: ns:item:app
        FCommunityPortalLaunchAppTask: Launching app 'Z:/Games/Thing/Thing.exe' with commandline ''

        """.write(to: log, atomically: true, encoding: .utf8)

        #expect(watcher.launchedExecutableInNewLines() == "Thing.exe")
        watcher.drainPastLaunch()
        #expect(watcher.linesForTesting().isEmpty, "the pull's line went with the drain")
    }

    /// Epic Online Services installs BESIDE the launcher, not inside it, and
    /// its host is a registered wine service that outlives a title. Counted
    /// as the game, it meant an Epic session never read as over: the bottle
    /// stayed up, the loader never released, and the title could not be
    /// played again.
    @Test func theLaunchersOwnIncludesEpicOnlineServices() throws {
        let bottle = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bottle-\(UUID().uuidString)")
        let epic = bottle.appendingPathComponent("drive_c/Program Files (x86)/Epic Games")
        let places = ["Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe",
                      "Epic Online Services/service/EpicOnlineServicesHost.exe",
                      "Epic Online Services/EpicOnlineServicesUserHelper.exe",
                      "DirectXRedist/DXSETUP.exe"]
        for place in places {
            let url = epic.appendingPathComponent(place)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        defer { try? FileManager.default.removeItem(at: bottle) }
        let names = BottleProcesses.launchersOwnExecutables(inBottleAt: bottle)
        #expect(names.contains("epicgameslauncher.exe"))
        #expect(names.contains("epiconlineserviceshost.exe"), "the service that outlives the game")
        #expect(names.contains("epiconlineservicesuserhelper.exe"))
        #expect(names.contains("dxsetup.exe"), "not a game either")
    }

    /// lsof will not report a name longer than its cap, so a long name
    /// compared at full length never matches. Epic ships one:
    /// EOSOverlayRenderer-Win64-Shipping.exe is 37 characters.
    @Test func aNameTooLongForLsofIsStillRecognised() {
        let full = "eosoverlayrenderer-win64-shipping.exe"
        #expect(full.count > BottleProcesses.lsofNameLimit)
        let asLsofReportsIt = String(full.prefix(BottleProcesses.lsofNameLimit))
        #expect(asLsofReportsIt.count == BottleProcesses.lsofNameLimit)
        // The comparison gamesRunning makes, in both directions.
        let known: Set<String> = [full]
        let knownAtLimit = Set(known.map { String($0.prefix(BottleProcesses.lsofNameLimit)) })
        #expect(!known.contains(asLsofReportsIt), "which is why the full-length check alone failed")
        #expect(knownAtLimit.contains(String(asLsofReportsIt.prefix(BottleProcesses.lsofNameLimit))))
    }
}
