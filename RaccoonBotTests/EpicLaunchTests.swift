//
//  EpicLaunchTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Where the Epic Games Launcher is, and whether it is there.
struct EpicLaunchTests {

    private let steam = "file:///Users/someone/Library/Application%20Support/RaccoonBot/CXPBottles/Steam"

    /// On this machine nobody set an Epic bottle; the launcher lives in the
    /// Steam one. Unset falls back to the selected bottle, not to nothing.
    @Test func anUnsetEpicBottleFallsBackToTheSelectedOne() throws {
        let t = try #require(EpicLaunch.target(settings: StoreSettings(), selectedBottle: steam))
        #expect(t.bottle == steam)
        #expect(t.clientPath == Store.epic.defaultClientPath)
    }

    @Test func aSetEpicBottleWins() throws {
        var s = StoreSettings()
        s.bottle = "file:///Users/someone/CXPBottles/Epic"
        s.clientPath = #"C:\Games\Epic\EpicGamesLauncher.exe"#
        let t = try #require(EpicLaunch.target(settings: s, selectedBottle: steam))
        #expect(t.bottle == s.bottle)
        #expect(t.clientPath == s.clientPath)
    }

    @Test func nothingConfiguredAnywhereIsNoTarget() {
        #expect(EpicLaunch.target(settings: StoreSettings(), selectedBottle: "") == nil)
    }

    /// The Windows path Epic's installer writes, mapped under drive_c.
    @Test func theClientPathMapsUnderDriveC() throws {
        let unix = try #require(EpicLaunch.unixPath(of: Store.epic.defaultClientPath, inBottle: steam))
        #expect(unix.hasSuffix("/CXPBottles/Steam/drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe"))
        #expect(!unix.contains("\\"))
    }

    /// Only drive C is mapped. Anything else is an honest nil, not a guess.
    @Test func anotherDriveLetterIsNotGuessed() {
        #expect(EpicLaunch.unixPath(of: #"D:\Epic\EpicGamesLauncher.exe"#, inBottle: steam) == nil)
    }

    /// Installed means the file is there, which is what decides whether a
    /// button appears.
    @Test func installedMeansTheFileExists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("epic-\(UUID().uuidString)")
            .appendingPathComponent("Steam")
        let exe = dir.appendingPathComponent("drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bottle = dir.absoluteString
        let target = try #require(EpicLaunch.target(settings: StoreSettings(), selectedBottle: bottle))
        #expect(EpicLaunch.isInstalled(target) == false)
        try "x".write(to: exe, atomically: true, encoding: .utf8)
        #expect(EpicLaunch.isInstalled(target) == true)
    }
}

/// Never open a bottle with an engine older than the one that made it.
struct BottleVersionGuardTests {
    @Test func newerBottleIsRefused() {
        #expect(EpicLaunch.bottleIsNewer(bottleVersion: "27.0.0.40921", engineVersion: "26.3.0.39832"))
    }
    @Test func sameOrOlderIsFine() {
        #expect(!EpicLaunch.bottleIsNewer(bottleVersion: "26.3.0.39832", engineVersion: "26.3.0.39832"))
        #expect(!EpicLaunch.bottleIsNewer(bottleVersion: "26.2.1", engineVersion: "26.3.0.39832"))
    }
    @Test func comparesNumericallyNotLexically() {
        #expect(EpicLaunch.bottleIsNewer(bottleVersion: "26.10", engineVersion: "26.9"))
    }
    @Test func readsTheVersionFromTheConf() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("conf-\(UUID().uuidString)").appendingPathComponent("Epic")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "  ;; comment\n\"Template\" = \"win10_64\"\n\"Version\" = \"27.0.0.40921\"\n".write(to: dir.appendingPathComponent("cxbottle.conf"), atomically: true, encoding: .utf8)
        #expect(EpicLaunch.bottleVersion(of: dir.absoluteString) == "27.0.0.40921")
    }
}

/// A self-updated launcher carries a Win64 build, and that is the one to run.
struct EpicLaunchWin64Tests {
    @Test func prefersWin64WhenItIsThere() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("epic64-\(UUID().uuidString)")
            .appendingPathComponent("Steam")
        let bin = dir.appendingPathComponent("drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries")
        try FileManager.default.createDirectory(at: bin.appendingPathComponent("Win64"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin.appendingPathComponent("Win32"), withIntermediateDirectories: true)
        try "x".write(to: bin.appendingPathComponent("Win32/EpicGamesLauncher.exe"), atomically: true, encoding: .utf8)
        let before = try #require(EpicLaunch.target(settings: StoreSettings(), selectedBottle: dir.absoluteString))
        #expect(before.clientPath.contains("\\Win32\\"), "only Win32 there: use it")
        try "x".write(to: bin.appendingPathComponent("Win64/EpicGamesLauncher.exe"), atomically: true, encoding: .utf8)
        let after = try #require(EpicLaunch.target(settings: StoreSettings(), selectedBottle: dir.absoluteString))
        #expect(after.clientPath.contains("\\Win64\\"))
    }

    @Test func anExplicitClientPathIsNotSecondGuessed() throws {
        var s = StoreSettings(); s.clientPath = #"C:\Somewhere\Else.exe"#
        let t = try #require(EpicLaunch.target(settings: s, selectedBottle: "file:///tmp/x"))
        #expect(t.clientPath == s.clientPath)
    }
}
