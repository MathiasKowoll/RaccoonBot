//
//  UnrealConfigTests.swift
//  RaccoonBotTests
//
//  Which Steam launches get an Engine.ini. A Steam launch carries no
//  executable, so the install folder is what says whether the title is Unreal
//  at all; a cloud-save path shaped like Unreal's is not enough. Granblue
//  Fantasy: Relink records `GBFR/Saved/SaveGames` and was handed an Engine.ini
//  it never reads.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct UnrealConfigTests {

    /// A bottle with Steam in it, one library on C:, and an appinfo.vdf whose
    /// only record carries a WinAppDataLocal cloud-save path for `appID`.
    private struct Fixture {
        let bottle: URL
        let steamRoot: URL
        let appID = "881020"

        init(cloudProject: String, installdir: String) throws {
            let f = FileManager.default
            bottle = f.temporaryDirectory.appendingPathComponent("unrealconfig-\(UUID().uuidString)")
            steamRoot = bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam")
            try f.createDirectory(at: steamRoot.appendingPathComponent("appcache"), withIntermediateDirectories: true)
            try f.createDirectory(at: steamRoot.appendingPathComponent("config"), withIntermediateDirectories: true)
            try f.createDirectory(at: bottle.appendingPathComponent("drive_c/users/crossover/AppData/Local"),
                                  withIntermediateDirectories: true)

            try """
            "libraryfolders"
            {
            \t"0"
            \t{
            \t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"
            \t}
            }
            """.write(to: steamRoot.appendingPathComponent("config/libraryfolders.vdf"),
                      atomically: true, encoding: .utf8)
            try """
            "AppState"
            {
            \t"appid"\t\t"\(appID)"
            \t"installdir"\t\t"\(installdir)"
            }
            """.write(to: steamRoot.appendingPathComponent("steamapps/appmanifest_\(appID).acf")
                        .creatingParent(), atomically: true, encoding: .utf8)

            func u32(_ v: UInt32) -> [UInt8] { [0, 8, 16, 24].map { UInt8((v >> $0) & 0xFF) } }
            let blob = Array("root\0WinAppDataLocal\0path\0\(cloudProject)/Saved/SaveGames\0".utf8)
            var file: [UInt8] = u32(0x07564429) + u32(1)
            file += u32(UInt32(appID)!) + u32(UInt32(blob.count)) + blob
            file += u32(0)
            try Data(file).write(to: steamRoot.appendingPathComponent("appcache/appinfo.vdf"))
        }

        var game: URL { steamRoot.appendingPathComponent("steamapps/common") }

        func engineIni(project: String) -> URL {
            UnrealConfig.configDirectory(bottle: bottle, project: project).appendingPathComponent("Engine.ini")
        }

        func launch() {
            UnrealConfig.applyAtLaunch(bottle: bottle, steamAppID: appID, steamRoot: steamRoot)
        }
    }

    @Test func aCloudPathAloneDoesNotMakeATitleUnreal() throws {
        // GBFR's shape: the executable at the top of the install folder.
        let fx = try Fixture(cloudProject: "GBFR", installdir: "Granblue Fantasy Relink")
        defer { try? FileManager.default.removeItem(at: fx.bottle) }
        let folder = fx.game.appendingPathComponent("Granblue Fantasy Relink")
        try Data().write(to: folder.appendingPathComponent("granblue_fantasy_relink.exe").creatingParent())

        #expect(SteamAppInfo.savedGamesProject(appID: fx.appID, steamRoot: fx.steamRoot) == "GBFR")
        #expect(!SteamLibrary.isUnrealInstall(appID: fx.appID, steamRoot: fx.steamRoot, bottle: fx.bottle))
        fx.launch()
        #expect(!FileManager.default.fileExists(atPath: fx.engineIni(project: "GBFR").path))
    }

    @Test func anUnrealLayoutStillGetsItsEngineIni() throws {
        let fx = try Fixture(cloudProject: "Dawnwalker", installdir: "The Blood of Dawnwalker")
        defer { try? FileManager.default.removeItem(at: fx.bottle) }
        let win64 = fx.game.appendingPathComponent("The Blood of Dawnwalker/Dawnwalker/Binaries/Win64")
        try Data().write(to: win64.appendingPathComponent("Dawnwalker-Win64-Shipping.exe").creatingParent())

        fx.launch()
        let written = try String(contentsOf: fx.engineIni(project: "Dawnwalker"), encoding: .utf8)
        #expect(written.contains("r.WarnOfBadDrivers=0"))
    }

    @Test func severalPlainExecutablesAreStillUnreal() throws {
        // unrealExecutable cannot pick one of these, but the layout is Unreal's
        // and the cloud path names the project, so the title is covered.
        let fx = try Fixture(cloudProject: "Proj", installdir: "Some Game")
        defer { try? FileManager.default.removeItem(at: fx.bottle) }
        let win64 = fx.game.appendingPathComponent("Some Game/Binaries/Win64")
        for name in ["Proj.exe", "Launcher.exe"] {
            try Data().write(to: win64.appendingPathComponent(name).creatingParent())
        }

        #expect(SteamLibrary.unrealExecutable(appID: fx.appID, steamRoot: fx.steamRoot, bottle: fx.bottle) == nil)
        fx.launch()
        #expect(FileManager.default.fileExists(atPath: fx.engineIni(project: "Proj").path))
    }

    @Test func aTitleThatIsNotInstalledGetsNothing() throws {
        let fx = try Fixture(cloudProject: "Ghost", installdir: "Not Here")
        defer { try? FileManager.default.removeItem(at: fx.bottle) }

        fx.launch()
        #expect(!FileManager.default.fileExists(atPath: fx.engineIni(project: "Ghost").path))
    }
}

private extension URL {
    /// Creates the parent directory and hands the URL back, for one-line writes.
    func creatingParent() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}
