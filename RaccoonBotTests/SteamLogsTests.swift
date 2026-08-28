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
        let events = w.newEvents()
        #expect(events.count == 1)
        guard case .started(let pid, let path) = events[0] else { Issue.record("not a start"); return }
        #expect(pid == 1304)
        #expect(path.hasSuffix("game.exe"))
    }

    @Test func anExitCodeSurvivesBeingNegative() throws {
        let (w, log) = try watcher()
        try append("[2026-08-28 11:10:25] AppID 1340990 no longer tracking PID 1308, exit code -1073741819\n", to: log)
        let events = w.newEvents()
        guard case .stopped(let pid, let code) = events.first else { Issue.record("not a stop"); return }
        #expect(pid == 1308)
        #expect(code == -1073741819)
        #expect(describeExit(code: code).contains("access violation"))
    }

    /// The line that means the session is over, and the reason this works for a
    /// game with a launcher: it names no executable.
    @Test func removalFromTheRunningListEndsTheSession() throws {
        let (w, log) = try watcher()
        try append("[2026-08-28 11:17:20] Remove 1340990 from running list\n", to: log)
        guard case .sessionEnded = w.newEvents().first else { Issue.record("not a session end"); return }
    }

    @Test func anotherGameIsNotOurs() throws {
        let (w, log) = try watcher()
        try append("[2026-08-28 11:17:20] AppID 485510 adding PID 99 as a tracked process \"\"C:\\nioh.exe\"\n", to: log)
        try append("[2026-08-28 11:17:20] Remove 485510 from running list\n", to: log)
        #expect(w.newEvents().isEmpty)
    }

    /// A launcher exiting is a stop, never a session end -- the distinction the
    /// whole change rests on.
    @Test func aLauncherExitingIsNotTheSessionEnding() throws {
        let (w, log) = try watcher()
        try append("[2026-08-28 11:15:11] AppID 1340990 adding PID 100 as a tracked process \"\"Z:\\launcher.exe\"\n", to: log)
        try append("[2026-08-28 11:15:12] AppID 1340990 no longer tracking PID 100, exit code 0\n", to: log)
        try append("[2026-08-28 11:15:13] AppID 1340990 adding PID 200 as a tracked process \"\"Z:\\game.exe\"\n", to: log)
        let events = w.newEvents()
        #expect(events.count == 3)
        #expect(!events.contains { if case .sessionEnded = $0 { return true } else { return false } })
    }
}
