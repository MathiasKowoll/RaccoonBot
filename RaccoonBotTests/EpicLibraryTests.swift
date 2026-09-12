//
//  EpicLibraryTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// The Epic launcher's records, read the way the design note says to.
struct EpicLibraryTests {

    private func manifest(_ fields: [String: Any]) throws -> EpicManifest {
        var d: [String: Any] = ["AppName": "abc"]
        d.merge(fields) { _, new in new }
        return try JSONDecoder().decode(EpicManifest.self, from: JSONSerialization.data(withJSONObject: d))
    }

    /// Real manifests carry keys no template knows and sometimes lack ones a
    /// template expects. Only the name is required.
    @Test func decodesWithOnlyTheNameAndIgnoresStrangers() throws {
        let m = try manifest(["SomethingNew": 42, "AnotherNew": ["x"]])
        #expect(m.AppName == "abc")
        #expect(m.DisplayName == nil)
        #expect(m.isGame == false)
    }

    /// Base games carry an EMPTY MainGameAppName in real data. "main == self"
    /// would drop every base game; "main non-empty and not self" is DLC.
    @Test func dlcIsAMainGameThatIsNotItself() throws {
        #expect(try manifest(["MainGameAppName": ""]).isDLC == false)
        #expect(try manifest(["MainGameAppName": "abc"]).isDLC == false)
        #expect(try manifest(["MainGameAppName": "other"]).isDLC == true)
    }

    @Test func onlyCompleteGamesAreListed() throws {
        let game: [String: Any] = ["AppCategories": ["public", "games", "applications"]]
        #expect(EpicLibrary.isListable(try manifest(game)))
        #expect(!EpicLibrary.isListable(try manifest(["AppCategories": ["public", "applications"]])), "not a game")
        #expect(!EpicLibrary.isListable(try manifest(game.merging(["bIsIncompleteInstall": true]) { $1 })))
        #expect(!EpicLibrary.isListable(try manifest(game.merging(["MainGameAppName": "base"]) { $1 })), "DLC")
    }

    /// The identity is the three-part form the launcher's URL scheme uses,
    /// tagged with the store. Never the bare AppName, never the file name.
    @Test func theIDIsTheTaggedTriple() throws {
        let m = try manifest(["CatalogNamespace": "ns", "CatalogItemId": "item"])
        #expect(m.tripleID == "epic:ns:item:abc")
    }

    /// A bottle on disk: dosdevices with z: -> /, a game folder, a manifest
    /// with mixed separators the way the launcher really writes them.
    @Test func readsAGameThroughTheBottlesDriveLetters() throws {
        let f = FileManager.default
        let root = f.temporaryDirectory.appendingPathComponent("epiclib-\(UUID().uuidString)")
        let bottle = root.appendingPathComponent("Epic")
        let dos = bottle.appendingPathComponent("dosdevices")
        try f.createDirectory(at: dos, withIntermediateDirectories: true)
        try f.createSymbolicLink(at: dos.appendingPathComponent("z:"), withDestinationURL: URL(fileURLWithPath: "/"))
        try f.createSymbolicLink(at: dos.appendingPathComponent("c:"), withDestinationURL: bottle.appendingPathComponent("drive_c"))
        let game = root.appendingPathComponent("Games/Venus")
        try f.createDirectory(at: game, withIntermediateDirectories: true)
        try "x".write(to: game.appendingPathComponent("Borderlands4.exe"), atomically: true, encoding: .utf8)
        let manifests = bottle.appendingPathComponent("drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests")
        try f.createDirectory(at: manifests, withIntermediateDirectories: true)
        // Z:\<root>/Games/Venus, with the launcher's habit of mixing separators.
        let winRoot = "Z:" + root.path(percentEncoded: false).replacingOccurrences(of: "/", with: "\\")
        let item: [String: Any] = [
            "AppName": "ea5f", "DisplayName": "Borderlands®4",
            "CatalogNamespace": "4e00", "CatalogItemId": "6a55",
            "InstallLocation": winRoot + "\\Games/Venus",
            "LaunchExecutable": "Borderlands4.exe",
            "AppCategories": ["public", "games", "applications"],
            "bIsIncompleteInstall": false, "AppVersionString": "Oak2",
        ]
        try JSONSerialization.data(withJSONObject: item).write(to: manifests.appendingPathComponent("2B1B.item"))
        // And a DLC beside it, which must not appear.
        var dlc = item; dlc["AppName"] = "dlc1"; dlc["MainGameAppName"] = "ea5f"; dlc["AppCategories"] = ["public", "applications"]
        try JSONSerialization.data(withJSONObject: dlc).write(to: manifests.appendingPathComponent("AAAA.item"))
        // No registry: the conventional data path is used.
        let list = EpicLibrary.read(bottle: bottle)
        #expect(list.count == 1)
        let bl = try #require(list.first)
        #expect(bl.title == "Borderlands®4")
        #expect(bl.id == "epic:4e00:6a55:ea5f")
        #expect(bl.presence == .installed)
        #expect(bl.folder.path(percentEncoded: false).hasSuffix("/Games/Venus"))
        #expect(bl.executable?.lastPathComponent == "Borderlands4.exe")
    }

    /// The data path from the registry, unescaped and without its trailing
    /// backslash. This is the first REG_SZ path ever read through the parser.
    @Test func readsTheDataPathFromTheRegistry() throws {
        let f = FileManager.default
        let bottle = f.temporaryDirectory.appendingPathComponent("epicreg-\(UUID().uuidString)")
        try f.createDirectory(at: bottle, withIntermediateDirectories: true)
        let reg = """
        WINE REGISTRY Version 2
        ;; All keys relative to \\\\Machine

        [Software\\\\Wow6432Node\\\\Epic Games\\\\EpicGamesLauncher] 1700000000
        #time=1da0000000000000
        "AppDataPath"="D:\\\\Epic\\\\Data\\\\"

        """
        try reg.write(to: bottle.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
        #expect(EpicLibrary.dataPath(inBottle: bottle) == #"D:\Epic\Data"#)
    }

    @Test func noRegistryMeansTheConventionalPath() {
        let bottle = FileManager.default.temporaryDirectory.appendingPathComponent("epicnoreg-\(UUID().uuidString)")
        #expect(EpicLibrary.dataPath(inBottle: bottle) == EpicLibrary.defaultDataPath)
    }

    /// A game on a drive that maps but is not mounted is kept, and said so.
    @Test func anUnmountedDriveIsOfflineNotGone() throws {
        let f = FileManager.default
        let bottle = f.temporaryDirectory.appendingPathComponent("epicoff-\(UUID().uuidString)")
        let dos = bottle.appendingPathComponent("dosdevices")
        try f.createDirectory(at: dos, withIntermediateDirectories: true)
        try f.createSymbolicLink(at: dos.appendingPathComponent("d:"), withDestinationURL: URL(fileURLWithPath: "/Volumes/NotHere-\(UUID().uuidString)"))
        let m = try manifest(["InstallLocation": #"D:\Games\X"#, "DisplayName": "X",
                              "AppCategories": ["games"], "LaunchExecutable": "x.exe"])
        let located = try #require(EpicLibrary.locate(m, drives: BottleDrives(bottle: bottle)))
        #expect(located.presence == .volumeOffline)
        #expect(located.executable?.lastPathComponent == "x.exe")
    }
}
