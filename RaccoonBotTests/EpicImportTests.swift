//
//  EpicImportTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Games on the disk, resolved against the catalogue and written as the
/// launcher's records.
struct EpicImportTests {

    private func tempDir() throws -> URL {
        let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("epicimport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func catalog(_ items: [[String: Any]]) throws -> EpicCatalog {
        let json = try JSONSerialization.data(withJSONObject: items)
        return try #require(EpicCatalog.decode(Data(json.base64EncodedString().utf8)))
    }

    private func game(_ id: String, title: String, app: String, folder: String, dlcOf: (String, String)? = nil) -> [String: Any] {
        var d: [String: Any] = ["id": id, "namespace": "ns", "title": title,
                                "categories": [["path": "public"], ["path": "games"], ["path": "applications"]],
                                "mainGameItem": ["namespace": dlcOf?.0 ?? "", "id": dlcOf?.1 ?? ""],
                                "releaseInfo": [["appId": app]],
                                "customAttributes": ["FolderName": ["value": folder], "CanRunOffline": ["value": "true"]]]
        if dlcOf != nil { d["categories"] = [["path": "public"], ["path": "applications"]] }
        return d
    }

    @discardableResult
    private func manifest(in folder: URL, guid: String, app: String, version: String = "1.0", exe: String = "Game.exe") throws -> URL {
        let eg = folder.appendingPathComponent(".egstore")
        try FileManager.default.createDirectory(at: eg, withIntermediateDirectories: true)
        let url = eg.appendingPathComponent(guid + ".manifest")
        try EpicBuildManifestTests.file(body: EpicBuildManifestTests.body(appName: app, version: version, exe: exe)).write(to: url)
        return url
    }

    /// A DLC joins by its own AppName; the base game by the catalogue's
    /// FolderName, since its manifest may carry another build id.
    @Test func baseByFolderNameAndDLCByAppName() throws {
        let lib = try tempDir(); defer { try? FileManager.default.removeItem(at: lib) }
        let folder = lib.appendingPathComponent("YsIX")
        try manifest(in: folder, guid: "AAAA", app: "build-id-not-in-catalogue", version: "1.1.3", exe: "ys9.exe")
        try manifest(in: folder, guid: "BBBB", app: "dlc-app", version: "1.0.5", exe: "")
        let cat = try catalog([game("base", title: "Ys IX", app: "base-app", folder: "YsIX"),
                               game("dlc", title: "Ys IX - Bonus", app: "dlc-app", folder: "YsIX", dlcOf: ("ns", "base"))])
        let found = EpicImport.scan(library: lib, catalog: cat, registered: [])
        #expect(found.map(\.title) == ["Ys IX", "Ys IX - Bonus"])
        #expect(found[0].kind == .game && found[0].appName == "base-app" && found[0].installationGuid == "AAAA")
        #expect(found[1].kind == .dlc && found[1].mainGameAppName == "base-app")
        #expect(found.allSatisfy { $0.status == .ready })
    }

    /// Two builds of the same app in one folder: the one the catalogue names
    /// is the installed one, and the choice is said.
    @Test func twoBuildsTheNamedOneWins() throws {
        let lib = try tempDir(); defer { try? FileManager.default.removeItem(at: lib) }
        let folder = lib.appendingPathComponent("AWR")
        try manifest(in: folder, guid: "OLD1", app: "other-build", version: "34885")
        try manifest(in: folder, guid: "CUR1", app: "awr-app", version: "1.33")
        let cat = try catalog([game("awr", title: "Alan Wake Remastered", app: "awr-app", folder: "AWR")])
        let found = EpicImport.scan(library: lib, catalog: cat, registered: [])
        #expect(found.count == 1)
        #expect(found[0].installationGuid == "CUR1")
        #expect(found[0].note?.contains("2 builds") == true)
    }

    @Test func registeredAndUnknownAreMarked() throws {
        let lib = try tempDir(); defer { try? FileManager.default.removeItem(at: lib) }
        try manifest(in: lib.appendingPathComponent("Known"), guid: "K1", app: "k-app")
        try manifest(in: lib.appendingPathComponent("Mystery"), guid: "M1", app: "m-app")
        let cat = try catalog([game("k", title: "Known", app: "k-app", folder: "Known")])
        let found = EpicImport.scan(library: lib, catalog: cat, registered: ["K1"])
        #expect(found.first { $0.installationGuid == "K1" }?.status == .registered)
        #expect(found.first { $0.installationGuid == "M1" }?.status == .unknownTitle)
        #expect(found.first { $0.installationGuid == "M1" }?.title == "Mystery", "the folder's name stands in")
    }

    @Test func foldersWithoutAnEgstoreAreNotGames() throws {
        let lib = try tempDir(); defer { try? FileManager.default.removeItem(at: lib) }
        try FileManager.default.createDirectory(at: lib.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        #expect(EpicImport.scan(library: lib, catalog: nil, registered: []).isEmpty)
    }

    @Test func theRevisionIsTheHelpersEncoding() {
        #expect(EpicImport.revisionString(ticks: 639_239_824_316_330_510, number: 3) == "08DF093BBEA8720E0000000000000003")
        #expect(EpicImport.dotNetTicks(Date(timeIntervalSince1970: 0)) == 621_355_968_000_000_000)
    }

    @Test func windowsPathsGoThroughZ() {
        #expect(EpicImport.windowsPath(URL(fileURLWithPath: "/Volumes/Crucial X8/EpicGogGames/AlanWake2")) == #"Z:\Volumes\Crucial X8\EpicGogGames\AlanWake2"#)
    }

    /// The records, written into a bottle: an .item the launcher reads, an
    /// .egi the helper reports, the revision bumped, the installed list kept.
    @Test func applyWritesBothRecordsAndBumpsTheRevision() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let bottle = root.appendingPathComponent("bottle"); let lib = root.appendingPathComponent("lib")
        let places = EpicImport.Places(bottle: bottle)
        try FileManager.default.createDirectory(at: places.manifests, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: places.installedItems, withIntermediateDirectories: true)
        try Data(#"{"timestamp":1,"number":6}"#.utf8).write(to: places.installedItems.appendingPathComponent("Revision.json"))
        try manifest(in: lib.appendingPathComponent("AW2"), guid: "4FC8", app: "aw2-app", version: "1.2.8", exe: "AlanWake2.exe")
        let cat = try catalog([game("aw2", title: "Alan Wake 2", app: "aw2-app", folder: "AW2")])
        let found = EpicImport.scan(library: lib, catalog: cat, registered: EpicImport.registered(in: bottle))
        let applied = try EpicImport.apply(found, bottle: bottle, now: Date(timeIntervalSince1970: 0))
        #expect(applied.registered == ["Alan Wake 2"])
        #expect(applied.revision == "089F7FF5F7B58000" + "0000000000000007", "1970 in .NET ticks, then the number")

        let item = try JSONSerialization.jsonObject(with: Data(contentsOf: places.manifests.appendingPathComponent("4FC8.item"))) as! [String: Any]
        #expect(item["AppName"] as? String == "aw2-app")
        #expect(item["DisplayName"] as? String == "Alan Wake 2")
        // The scan hands back resolved paths and the temp dir is a symlink here
        // (/var -> /private/var), so the head of the path is the machine's;
        // the tail and the drive are what the launcher reads.
        let loc = item["InstallLocation"] as? String ?? ""
        #expect(loc.hasPrefix("Z:\\") && loc.hasSuffix("\\" + root.lastPathComponent + "\\lib\\AW2"), Comment(rawValue: loc))
        #expect(item["LaunchExecutable"] as? String == "AlanWake2.exe")
        #expect(item["bIsIncompleteInstall"] as? Bool == false)
        #expect(item["MandatoryAppFolderName"] as? String == "AW2")

        let egi = (try JSONSerialization.jsonObject(with: Data(contentsOf: places.installedItems.appendingPathComponent("4FC8.egi"))) as! [String: Any])["v4"] as! [String: Any]
        #expect(egi["state"] as? String == "Installed")
        #expect(egi["revision"] as? String == applied.revision)
        #expect(egi["artifactId"] as? String == "aw2-app")
        #expect((egi["manifestData"] as? [String: Any])?["version"] as? String == "1.2.8")

        let rev = try JSONSerialization.jsonObject(with: Data(contentsOf: places.installedItems.appendingPathComponent("Revision.json"))) as! [String: Any]
        #expect(rev["number"] as? Int == 7)
        let dat = try JSONSerialization.jsonObject(with: Data(contentsOf: places.launcherInstalled)) as! [String: Any]
        #expect((dat["InstallationList"] as? [[String: Any]])?.count == 1)

        // Registered now: a second scan finds nothing to do.
        let again = EpicImport.scan(library: lib, catalog: cat, registered: EpicImport.registered(in: bottle))
        #expect(again.first?.status == .registered)
        #expect(throws: EpicImport.Failure.nothingToRegister) { try EpicImport.apply(again, bottle: bottle) }
    }

    @Test func aBottleWithoutTheLauncherIsRefused() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("lib")
        try manifest(in: lib.appendingPathComponent("G"), guid: "G1", app: "g-app")
        let cat = try catalog([game("g", title: "G", app: "g-app", folder: "G")])
        let found = EpicImport.scan(library: lib, catalog: cat, registered: [])
        #expect(throws: EpicImport.Failure.noLauncher) { try EpicImport.apply(found, bottle: root.appendingPathComponent("nobottle")) }
    }

    /// The name that made the join is the one registered, not the item's
    /// first release.
    @Test func anItemWithTwoReleasesRegistersTheOneOnDisk() throws {
        let lib = try tempDir(); defer { try? FileManager.default.removeItem(at: lib) }
        try manifest(in: lib.appendingPathComponent("X"), guid: "X1", app: "x-b")
        var item = game("x", title: "X", app: "x-a", folder: "X")
        item["releaseInfo"] = [["appId": "x-a"], ["appId": "x-b"]]
        let found = EpicImport.scan(library: lib, catalog: try catalog([item]), registered: [])
        #expect(found.first?.appName == "x-b")
    }

    /// Two catalogue items share a folder name; the launcher's own .mancpn
    /// says which one it installed, and outranks the folder.
    @Test func theMancpnOutranksTheFolderName() throws {
        let lib = try tempDir(); defer { try? FileManager.default.removeItem(at: lib) }
        let folder = lib.appendingPathComponent("Shared")
        try manifest(in: folder, guid: "S1", app: "build-not-listed")
        let mancpn = ["FormatVersion": 0, "CatalogNamespace": "ns", "CatalogItemId": "second", "AppName": "second-app"] as [String: Any]
        try JSONSerialization.data(withJSONObject: mancpn).write(to: folder.appendingPathComponent(".egstore/S1.mancpn"))
        let cat = try catalog([game("first", title: "First", app: "first-app", folder: "Shared"),
                               game("second", title: "Second", app: "second-app", folder: "Shared")])
        let found = EpicImport.scan(library: lib, catalog: cat, registered: [])
        #expect(found.first?.catalogItemId == "second" && found.first?.appName == "second-app")
    }

    /// Two builds both named by the catalogue: the launcher's own record,
    /// when it has one, is the build shown as known.
    @Test func theRegisteredBuildWinsAmongNamedOnes() throws {
        let lib = try tempDir(); defer { try? FileManager.default.removeItem(at: lib) }
        let folder = lib.appendingPathComponent("G")
        try manifest(in: folder, guid: "NEW1", app: "g-app", version: "2.0")
        try manifest(in: folder, guid: "OLD1", app: "g-app", version: "1.0")
        let cat = try catalog([game("g", title: "G", app: "g-app", folder: "G")])
        let found = EpicImport.scan(library: lib, catalog: cat, registered: ["OLD1"])
        #expect(found.first?.installationGuid == "OLD1" && found.first?.status == .registered)
    }

    /// Known by AppName too: the launcher holds the game under another guid.
    @Test func aGameTheLauncherHoldsUnderAnotherGuidIsKnown() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let bottle = root.appendingPathComponent("bottle"); let lib = root.appendingPathComponent("lib")
        let places = EpicImport.Places(bottle: bottle)
        try FileManager.default.createDirectory(at: places.manifests, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["AppName": "g-app", "InstallationGuid": "OTHER"]).write(to: places.manifests.appendingPathComponent("OTHER.item"))
        try manifest(in: lib.appendingPathComponent("G"), guid: "MINE", app: "g-app")
        let cat = try catalog([game("g", title: "G", app: "g-app", folder: "G")])
        let found = EpicImport.scan(library: lib, catalog: cat, registered: EpicImport.registered(in: bottle))
        #expect(found.first?.status == .registered)
        #expect(throws: EpicImport.Failure.nothingToRegister) { try EpicImport.apply(found, bottle: bottle) }
    }

    /// Between the scan and the click the launcher registered the game
    /// itself; apply checks again and leaves its record alone.
    @Test func applyDoesNotReplaceARecordMadeSinceTheScan() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let bottle = root.appendingPathComponent("bottle"); let lib = root.appendingPathComponent("lib")
        let places = EpicImport.Places(bottle: bottle)
        try FileManager.default.createDirectory(at: places.manifests, withIntermediateDirectories: true)
        try manifest(in: lib.appendingPathComponent("G"), guid: "G1", app: "g-app")
        let cat = try catalog([game("g", title: "G", app: "g-app", folder: "G")])
        let found = EpicImport.scan(library: lib, catalog: cat, registered: [])
        #expect(found.first?.status == .ready)
        let theirs = Data("{\"AppName\":\"g-app\",\"InstallationGuid\":\"G1\",\"BaseURLs\":[\"http://real\"]}".utf8)
        try theirs.write(to: places.manifests.appendingPathComponent("G1.item"))
        #expect(throws: EpicImport.Failure.nothingToRegister) { try EpicImport.apply(found, bottle: bottle) }
        #expect(try Data(contentsOf: places.manifests.appendingPathComponent("G1.item")) == theirs, "untouched")
    }

    /// An installed list that exists but does not decode stops everything
    /// before a record is written, rather than being rewritten from scratch.
    @Test func anUnreadableInstalledListStopsTheWrite() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let bottle = root.appendingPathComponent("bottle"); let lib = root.appendingPathComponent("lib")
        let places = EpicImport.Places(bottle: bottle)
        try FileManager.default.createDirectory(at: places.manifests, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: places.launcherInstalled.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: places.launcherInstalled)
        try manifest(in: lib.appendingPathComponent("G"), guid: "G1", app: "g-app")
        let found = EpicImport.scan(library: lib, catalog: try catalog([game("g", title: "G", app: "g-app", folder: "G")]), registered: [])
        #expect(throws: EpicImport.Failure.launcherInstalledUnreadable) { try EpicImport.apply(found, bottle: bottle) }
        #expect(!FileManager.default.fileExists(atPath: places.manifests.appendingPathComponent("G1.item").path))
    }

    /// An existing installed list keeps its entries.
    @Test func theInstalledListKeepsWhatItHad() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let bottle = root.appendingPathComponent("bottle"); let lib = root.appendingPathComponent("lib")
        let places = EpicImport.Places(bottle: bottle)
        try FileManager.default.createDirectory(at: places.manifests, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: places.launcherInstalled.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing: [String: Any] = ["InstallationList": [["InstallLocation": "Z:\\old", "NamespaceId": "n", "ItemId": "i", "ArtifactId": "old-app", "AppVersion": "1", "AppName": "old-app"]]]
        try JSONSerialization.data(withJSONObject: existing).write(to: places.launcherInstalled)
        try manifest(in: lib.appendingPathComponent("G"), guid: "G1", app: "g-app")
        let found = EpicImport.scan(library: lib, catalog: try catalog([game("g", title: "G", app: "g-app", folder: "G")]), registered: [])
        try EpicImport.apply(found, bottle: bottle)
        let dat = try JSONSerialization.jsonObject(with: Data(contentsOf: places.launcherInstalled)) as! [String: Any]
        let names = (dat["InstallationList"] as? [[String: Any]])?.compactMap { $0["AppName"] as? String }
        #expect(names == ["old-app", "g-app"])
    }

    /// A manifest that cannot be read is said, and the folder is not
    /// mistaken for one without a game.
    @Test func anUnreadableManifestIsReported() throws {
        let lib = try tempDir(); defer { try? FileManager.default.removeItem(at: lib) }
        let eg = lib.appendingPathComponent("Broken/.egstore")
        try FileManager.default.createDirectory(at: eg, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: eg.appendingPathComponent("B1.manifest"))
        var problems: [String] = []
        let found = EpicImport.scan(library: lib, catalog: nil, registered: [], problems: &problems)
        #expect(found.isEmpty)
        #expect(problems.count == 1 && problems[0].hasPrefix("Broken/.egstore/B1.manifest"))
    }
}
