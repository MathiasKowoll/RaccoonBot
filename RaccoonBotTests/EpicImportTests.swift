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
}
