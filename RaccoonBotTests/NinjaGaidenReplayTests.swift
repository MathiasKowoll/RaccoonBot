//
//  NinjaGaidenReplayTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Steam writes these logs with CRLF, so these tests do too.
private func appendAsSteamWould(_ text: String, to url: URL) throws {
    let crlf = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\n", with: "\r\n")
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(crlf.utf8))
    try handle.close()
}

/// Ninja Gaiden 3, replayed from this machine's own gameprocess_log.
///
/// Steam recorded the game starting and crashing eleven seconds later. The
/// watcher logged the start and the removal and never the crash, so the session
/// never registered as over and the bottle stayed up until somebody closed it
/// by hand. Every unit test passed throughout, because every one of them wrote
/// "\n" while Steam writes "\r\n" -- and in Swift "\r\n" is a single Character,
/// so splitting on "\n" returned the whole block as one line.
@Suite("Ninja Gaiden 3, replayed from the log")
struct NinjaGaidenReplayTests {

    private func watcher() throws -> (SteamGameProcessLog, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ng3-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("logs"),
                                                withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("logs/gameprocess_log.txt")
        try "seed\r\n".write(to: log, atomically: true, encoding: .utf8)
        return (SteamGameProcessLog(steamPath: dir.path, steamID: "1369760"), log)
    }

    /// The four lines as they sit in the file, arriving in one read.
    @Test func theStartTheStopAndTheRemovalAreAllSeen() throws {
        let (w, log) = try watcher()
        try appendAsSteamWould("""
        [2026-08-28 21:30:50] AppID 1369760 adding PID 1320 as a tracked process ""Z:\\Volumes\\Crucial X8\\SteamLibraryCross\\steamapps\\common\\[NINJA GAIDEN Master Collection] NINJA GAIDEN 3 Razor's Edge\\NINJA GAIDEN 3 Razor's Edge.exe"
        [2026-08-28 21:30:50] SSGL: InternalUpdateClientGame indicates change to games list
        [2026-08-28 21:31:01] AppID 1369760 no longer tracking PID 1320, exit code -1073741819
        [2026-08-28 21:31:01] Remove 1369760 from running list

        """, to: log)

        let kinds = w.poll().map { event -> String in
            switch event {
            case .started: return "started"
            case .stopped: return "stopped"
            case .sessionEnded: return "sessionEnded"
            }
        }
        #expect(kinds == ["started", "stopped", "sessionEnded"], "got \(kinds)")
        #expect(w.tracked.isEmpty, "still holding \(w.tracked)")
        #expect(w.emptySince != nil, "the session never registered as over")
        #expect(w.lastExitWasACrash)
    }

    /// The fault itself, at the level it lives on.
    @Test func aBlockOfCRLFLinesIsFourLinesAndNotOne() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("l.txt")
        try "seed\r\n".write(to: f, atomically: true, encoding: .utf8)

        let tail = SteamLogTail(url: f)
        try appendAsSteamWould("a\nb\nc\nd\n", to: f)
        #expect(tail.newLines() == ["a", "b", "c", "d"])
    }

    /// And a log that uses plain newlines still works, since nothing says
    /// Steam will always write CRLF.
    @Test func aBlockOfPlainLinesStillWorks() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("l.txt")
        try "seed\n".write(to: f, atomically: true, encoding: .utf8)

        let tail = SteamLogTail(url: f)
        let handle = try FileHandle(forWritingTo: f)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("a\nb\nc\n".utf8))
        try handle.close()
        #expect(tail.newLines() == ["a", "b", "c"])
    }

    /// A carriage return must not survive into the parsed line, or every
    /// comparison against the end of a line quietly stops matching.
    @Test func noLineCarriesItsCarriageReturnAlong() throws {
        let (w, log) = try watcher()
        try appendAsSteamWould("[..] AppID 1369760 no longer tracking PID 7, exit code 0\n", to: log)
        _ = w.poll()
        #expect(w.lastExitCode == 0)
    }
}

@Suite("Finding the game's executable in Steam's log")
struct GameExeFromLogTests {

    /// The line Ninja Gaiden 3 produces. Splitting the file on "[" broke it in
    /// half: the AppID in one piece, the executable in another, and the game
    /// never identified.
    @Test func aBracketInThePathDoesNotHideTheExecutable() {
        let line = #"[2026-08-28 21:30:50] AppID 1369760 adding PID 1320 as a tracked process ""Z:\Volumes\Crucial X8\SteamLibraryCross\steamapps\common\[NINJA GAIDEN Master Collection] NINJA GAIDEN 3 Razor's Edge\NINJA GAIDEN 3 Razor's Edge.exe""#

        // What the old code did: everything after a "[" is its own entry.
        let byBracket = line.split(separator: "[")
        let entryWithTheAppID = byBracket.first { $0.contains("AppID 1369760 adding PID") }
        #expect(entryWithTheAppID?.contains(".exe") == false,
                "the bracket split hides the executable, which is the bug")

        // What it does now.
        let byLine = line.split(whereSeparator: \.isNewline)
        let entry = byLine.first { $0.contains("AppID 1369760 adding PID") }
        let found = entry?.firstMatch(of: /[^\\]+\.exe/)?.output
        #expect(found.map(String.init) == "NINJA GAIDEN 3 Razor's Edge.exe")
    }
}
