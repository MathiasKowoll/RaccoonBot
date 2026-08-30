//
//  BottleProcessesTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

@Suite("Knowing which processes belong to which bottle")
struct BottleProcessesTests {

    /// The identity comes from the bottle, not from whoever launched into it.
    /// That is what makes leftovers from another CrossOver -- or from an older
    /// run of this one -- findable: they all land in the same directory.
    @Test func theServerDirectoryComesFromTheBottleItself() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bottle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let server = try #require(BottleProcesses.serverDirectory(ofBottleAt: dir))
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        let device = try #require(attrs[.systemNumber] as? Int)
        let inode = try #require(attrs[.systemFileNumber] as? Int)

        #expect(server.lastPathComponent
                == "server-\(String(device, radix: 16))-\(String(inode, radix: 16))")
        #expect(server.deletingLastPathComponent().lastPathComponent == ".wine-\(getuid())")
    }

    /// A process that arrives while the teardown is waiting is not something
    /// that "ignored the request" -- it never got one.
    ///
    /// The one that arrives in practice is a fix installer: it starts a
    /// short-lived wineserver to run `reg.exe add`, and it is allowed to,
    /// because the guard forbidding a write while the bottle is busy is a
    /// one-shot check made before `wineserver -k` emptied the bottle. Killing
    /// it mid-write does not crash anything: `reg.exe` has already returned 0,
    /// so the fix is recorded as applied while some of its keys never reached
    /// user.reg.
    ///
    /// Signals only `/bin/sleep` processes this test started itself. No wine,
    /// no CrossOver, no game, no installer.
    /// A process that arrives while the teardown is waiting never received the
    /// request it is about to be killed for ignoring.
    ///
    /// The one that arrives in practice is a fix installer: it starts a
    /// short-lived wineserver to run `reg.exe add`, and it is allowed to,
    /// because the guard forbidding a write while the bottle is busy is a
    /// one-shot check made before `wineserver -k` emptied the bottle. Killing
    /// it mid-write does not crash anything -- `reg.exe` has already returned
    /// 0, so the fix is recorded as applied while some of its keys never
    /// reached user.reg.
    @Test func onlyWhatWasCondemnedIsKilled() {
        let doomed = [BottleProcesses.Running(pid: 100, name: "Game.exe"),
                      BottleProcesses.Running(pid: 101, name: "wineserver")]
        let now = [BottleProcesses.Running(pid: 100, name: "Game.exe"),      // ignored the request
                   BottleProcesses.Running(pid: 300, name: "wineserver")]    // the installer's
        #expect(BottleProcesses.stillThere(now, of: doomed).map(\.pid) == [100])
    }

    /// A pid the system reused between the two scans is a different process
    /// wearing an old number, and it is not under sentence.
    @Test func aReusedPidIsNotCondemnedForWhoeverHeldItBefore() {
        let doomed = [BottleProcesses.Running(pid: 100, name: "Game.exe")]
        let now = [BottleProcesses.Running(pid: 100, name: "wineserver")]
        #expect(BottleProcesses.stillThere(now, of: doomed).isEmpty)
    }

    /// Everything that was there and stayed is still killed -- the point is to
    /// narrow the second sweep, not to stop it working.
    @Test func whatWasThereAndStayedIsStillEnded() {
        let doomed = [BottleProcesses.Running(pid: 1, name: "a.exe"),
                      BottleProcesses.Running(pid: 2, name: "b.exe")]
        #expect(BottleProcesses.stillThere(doomed, of: doomed).map(\.pid) == [1, 2])
    }

    /// And a bottle that emptied itself during the grace leaves nothing to do.
    @Test func aBottleThatWentQuietLeavesNothing() {
        let doomed = [BottleProcesses.Running(pid: 1, name: "a.exe")]
        #expect(BottleProcesses.stillThere([], of: doomed).isEmpty)
    }

    /// Two bottles never share a server directory, which is why ending one
    /// cannot reach the other.
    @Test func twoBottlesGetDifferentDirectories() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let a = base.appendingPathComponent("bottle-a-\(UUID().uuidString)")
        let b = base.appendingPathComponent("bottle-b-\(UUID().uuidString)")
        for d in [a, b] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }

        #expect(BottleProcesses.serverDirectory(ofBottleAt: a)
                != BottleProcesses.serverDirectory(ofBottleAt: b))
    }

    @Test func aBottleThatIsNotThereHasNoDirectory() {
        #expect(BottleProcesses.serverDirectory(
            ofBottleAt: URL(fileURLWithPath: "/nowhere/at/all")) == nil)
    }

    /// A bottle with no server directory has nothing running, and asking must
    /// not be an error.
    @Test func aBottleWithNoServerIsQuiet() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bottle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(BottleProcesses.running(inBottleAt: dir).isEmpty)
        #expect(BottleProcesses.serverIsAlive(inBottleAt: dir) == false)
    }

    /// Against the real thing: the bottle this application actually uses must
    /// resolve to a directory wine has really made, or the scoping is fiction.
    @Test func therealBottleResolvesToADirectoryWineMade() throws {
        let bottle = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/RaccoonBot/CXPBottles/Steam")
        try #require(FileManager.default.fileExists(atPath: bottle.path))
        let server = try #require(BottleProcesses.serverDirectory(ofBottleAt: bottle))
        #expect(FileManager.default.fileExists(atPath: server.path))
    }
}
