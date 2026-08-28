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
