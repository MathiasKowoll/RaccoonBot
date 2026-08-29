//
//  ConfiguredBottlesTests.swift
//  RaccoonBotTests
//

import Foundation
import Testing
@testable import RaccoonBot

struct ConfiguredBottlesTests {

    /// A bottle shaped enough to be recognised: what makes a directory a bottle
    /// here is drive_c, which is also what MGVF's own installers test for.
    private func bottle(named name: String, under root: URL) throws -> URL {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("drive_c"),
                                                withIntermediateDirectories: true)
        return dir
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bottles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: what the configuration says

    /// The decision, pinned. ARM is out until somebody turns it on deliberately,
    /// and turning it on should break this test rather than surprise anybody.
    @Test func theArmBottleIsOutForNow() {
        #expect(ConfiguredBottles.armIncluded == false)
        let refs = ConfiguredBottles.configured(
            selected: "file:///Users/x/Library/Application%20Support/RaccoonBot/CXPBottles/Steam/",
            arm: "file:///Users/x/Library/Application%20Support/RaccoonBot/CXPBottles/SteamArm/")
        #expect(refs.count == 1)
        #expect(refs.first?.name == "Steam")
    }

    /// The stored shape is a percent-encoded file URL, and it is parsed rather
    /// than pattern-matched. Handing that string on as a bottle NAME is what
    /// once put `file:///...` in front of wine behind a Fatal Error dialog.
    @Test func theStoredFileURLBecomesANameAndARoot() throws {
        let refs = ConfiguredBottles.configured(
            selected: "file:///Users/x/Library/Application%20Support/RaccoonBot/CXPBottles/Steam/",
            arm: "")
        let one = try #require(refs.first)
        #expect(one.name == "Steam")
        #expect(one.root == "/Users/x/Library/Application Support/RaccoonBot/CXPBottles")
        #expect(one.root.contains("%20") == false)
    }

    @Test func anUnsetEntryIsNotABottleNamedNothing() {
        #expect(ConfiguredBottles.configured(selected: "", arm: "").isEmpty)
        #expect(ConfiguredBottles.configured(selected: "   ", arm: "").isEmpty)
    }

    // MARK: what the disk says

    /// Epic arrives this week, and stock CrossOver already carries a bottle
    /// named `Epic Games Store`. Matching by name would pick precisely the
    /// neighbour we must never write into, so the path is what decides.
    @Test func aBottleIsMatchedByItsPathNotByItsName() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ours = try bottle(named: "Epic Games Store", under: root.appendingPathComponent("ours"))
        _ = try bottle(named: "Epic Games Store", under: root.appendingPathComponent("theirs"))

        let selection = ConfiguredBottles.onDisk(
            ConfiguredBottles.configured(selected: ours.absoluteString, arm: ""))
        #expect(selection.usable.count == 1)
        #expect(selection.usable.first?.directory?.path(percentEncoded: false)
                == ours.path(percentEncoded: false))
        #expect(selection.usable.first?.root.hasSuffix("/ours") == true)
    }

    /// A directory that is not a bottle is not one just because it is named
    /// like one.
    @Test func aDirectoryWithNoDriveCIsNotABottle() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = root.appendingPathComponent("Steam", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let selection = ConfiguredBottles.onDisk(
            ConfiguredBottles.configured(selected: empty.absoluteString, arm: ""))
        #expect(selection.usable.isEmpty)
        #expect(selection.missing == ["Steam"])
    }

    /// A bare name carries no root, so there is no way to check which of the
    /// same-named bottles it meant. Counted as missing rather than trusted.
    @Test func aBareNameCannotBeCheckedAndIsNotTakenOnTrust() {
        let selection = ConfiguredBottles.onDisk(
            ConfiguredBottles.configured(selected: "Steam", arm: ""))
        #expect(selection.usable.isEmpty)
        #expect(selection.missing == ["Steam"])
    }

    // MARK: what a patch is allowed to touch

    @Test func nothingConfiguredThrowsRatherThanReturningAnEmptyList() {
        #expect(throws: ConfiguredBottles.Failure.noneConfigured) {
            try ConfiguredBottles.forPatching(selected: "", arm: "")
        }
    }

    @Test func everythingConfiguredButAbsentThrowsAndNamesWhat() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gone = root.appendingPathComponent("SteamArm", isDirectory: true)
        #expect(throws: ConfiguredBottles.Failure.noneOnDisk(["SteamArm"])) {
            try ConfiguredBottles.forPatching(selected: gone.absoluteString, arm: "")
        }
    }

    /// Epic configured before its bottle exists must not stop Steam being
    /// patched -- but it must not be silently passed over either.
    @Test func oneMissingBottleIsReportedWhileTheRestAreStillUsable() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let there = try bottle(named: "Steam", under: root)
        let notThere = root.appendingPathComponent("Epic", isDirectory: true)

        let selection = ConfiguredBottles.onDisk([
            BottleReference(there.absoluteString)!,
            BottleReference(notThere.absoluteString)!,
        ])
        #expect(selection.usable.map(\.name) == ["Steam"])
        #expect(selection.missing == ["Epic"])
    }

    /// Configuration order is kept, so what a log says was patched first is
    /// what was configured first.
    @Test func theOrderIsTheOrderItWasConfiguredIn() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let steam = try bottle(named: "Steam", under: root)
        let epic = try bottle(named: "Epic", under: root)
        let selection = ConfiguredBottles.onDisk([
            BottleReference(epic.absoluteString)!,
            BottleReference(steam.absoluteString)!,
        ])
        #expect(selection.usable.map(\.name) == ["Epic", "Steam"])
    }
}
