//
//  SteamAppStateTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

private final class Fired: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); defer { lock.unlock() }; value = true }
    var didFire: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

/// A bottle holding nothing but a Steam app key, written the way wine writes it.
private func makeBottle(appID: Int, running: Int) throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("steamstate-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try writeRegistry(in: dir, appID: appID, running: running)
    return dir
}

private func writeRegistry(in dir: URL, appID: Int, running: Int) throws {
    let text = #"""
    WINE REGISTRY Version 2
    ;; All keys relative to \\User\\S-1-5-21-0-0-0-1000

    [Software\\Valve\\Steam\\Apps\\APPID] 1787925836
    #time=1dd36f610eb0764
    "Installed"=dword:00000001
    "Name"="A Game With A Launcher"
    "Running"=dword:RUNNING
    "Updating"=dword:00000000

    """#
        .replacingOccurrences(of: "APPID", with: String(appID))
        .replacingOccurrences(of: "RUNNING", with: String(format: "%08x", running))
    try text.write(to: dir.appendingPathComponent("user.reg"), atomically: true, encoding: .utf8)
}

@Suite("Steam's own account of a game session")
struct SteamAppStateTests {

    @Test func theKeyPathIsSpelledTheWayWineWritesIt() {
        #expect(SteamAppState.appKeyPath(485510) == #"Software\\Valve\\Steam\\Apps\\485510"#)
    }

    @Test func aRunningGameReadsAsRunning() throws {
        let dir = try makeBottle(appID: 485510, running: 1)
        #expect(SteamAppState(bottleDirectory: dir).liveness(ofAppID: 485510) == .running)
    }

    @Test func aStoppedGameReadsAsStopped() throws {
        let dir = try makeBottle(appID: 485510, running: 0)
        #expect(SteamAppState(bottleDirectory: dir).liveness(ofAppID: 485510) == .notRunning)
    }

    /// An app Steam has never recorded must not read as finished, or the first
    /// launch of a title would tear its own bottle down.
    @Test func anAppSteamNeverRecordedIsUnknownRatherThanStopped() throws {
        let dir = try makeBottle(appID: 485510, running: 1)
        #expect(SteamAppState(bottleDirectory: dir).liveness(ofAppID: 2492670) == .unknown)
    }

    @Test func aMissingRegistryIsUnknownRatherThanStopped() {
        let nowhere = URL(fileURLWithPath: "/nowhere/at/all")
        #expect(SteamAppState(bottleDirectory: nowhere).liveness(ofAppID: 485510) == .unknown)
    }

    /// The property everything else rests on. A registry that has not caught up
    /// yet reads as not-running, and tearing the bottle down on that would kill
    /// the game during startup -- which is the bug this replaced.
    @Test func aZeroOnItsOwnIsNotASessionEnding() async throws {
        let dir = try makeBottle(appID: 485510, running: 0)
        let fired = Fired()
        let task = Task {
            await watchSteamSession(SteamAppState(bottleDirectory: dir),
                                    appID: 485510,
                                    every: 20_000_000) { _ in fired.set() }
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        task.cancel()
        #expect(fired.didFire == false)
    }

    @Test func aOneThatBecomesZeroIsASessionEnding() async throws {
        let dir = try makeBottle(appID: 485510, running: 1)
        let fired = Fired()
        let task = Task {
            await watchSteamSession(SteamAppState(bottleDirectory: dir),
                                    appID: 485510,
                                    every: 20_000_000) { _ in fired.set() }
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        try writeRegistry(in: dir, appID: 485510, running: 0)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        task.cancel()
        #expect(fired.didFire == true)
    }

    /// Against the real thing: proves the key path matches what wine actually
    /// wrote, which a synthetic file cannot.
    @Test func arealBottleAnswersDefinitelyForAnInstalledApp() throws {
        let bottle = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/RaccoonBot/CXPBottles/Steam")
        try #require(FileManager.default.fileExists(atPath: bottle.appendingPathComponent("user.reg").path))
        let state = SteamAppState(bottleDirectory: bottle)
        // Nioh, the title this whole change came from.
        #expect(state.liveness(ofAppID: 485510) != .unknown)
        #expect(state.name(ofAppID: 485510)?.contains("Nioh") == true)
    }
}
