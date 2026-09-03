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

    /// No phrase is known yet, and none is guessed: a guess would be read
    /// back as a measurement.
    @Test func noTerminalPhraseIsClaimed() {
        #expect(!EpicSettle.isTerminal("LogCloudSaves: Upload complete"))
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
}
