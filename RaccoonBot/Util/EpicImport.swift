//
//  EpicImport.swift
//  RaccoonBot
//
//  Telling the Epic launcher about games that are already on the disk.
//
//  A game folder the launcher did not install into this bottle -- copied from
//  another machine, from another bottle, restored from a backup -- is
//  invisible to it. Since launcher 5.5 (measured 2026-09-02) two records make
//  a game "installed": an `.item` manifest in Data\Manifests, and a matching
//  record in the Epic Online Services helper's store, one `.egi` per
//  installation with a Revision.json; the launcher deletes any `.item` the
//  helper does not report. Both are synthesized here from what lies beside
//  the game files -- `.egstore/<guid>.manifest`, sometimes a `.mancpn` -- and
//  from the launcher's catalogue cache for names and ids. Given both, the
//  launcher took the eight registered here as its own within the hour: it
//  rewrote the `.item` files with its own extra fields and started an update
//  for one of them, in the right folder.
//
//  Two rules, both measured. A DLC's manifest carries the catalogue's own
//  AppName, so it joins by that. A base game's manifest may carry a different
//  build id (Borderlands 4, Ys IX), so the base joins by the catalogue's
//  FolderName attribute, which is the folder's name on disk. And a folder may
//  hold two builds of the same app (Alan Wake Remastered); the one whose
//  AppName the catalogue lists wins, else the newest, and the choice is said.
//
//  What is written is the minimum the launcher needs; it fills the rest --
//  bIsFab, CompleteManifestPath, its own revision -- at its next start. What
//  cannot be derived here and is left empty: the download BaseURLs, which the
//  launcher fetches again when it updates. Whether an update works from an
//  empty list has NOT been exercised yet; the eight registered here carried
//  URLs copied from another bottle.
//
//  Nothing is ever deleted or rewritten: a game already known to the
//  launcher, by `.item` or by `.egi`, is skipped. And nothing is written while
//  the bottle is up -- the helper holds its store open and the launcher
//  reconciles at start -- so the caller is refused, not raced.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated enum EpicImport {

    /// One game or DLC found on the disk, and what is known about it.
    struct Found: Equatable, Identifiable {
        enum Kind: Equatable { case game, dlc }
        enum Status: Equatable {
            case registered
            case ready
            /// Nothing in the catalogue names it: registering it would give
            /// the launcher a record with no title.
            case unknownTitle
        }
        let folder: URL
        let manifestURL: URL
        let installationGuid: String
        let kind: Kind
        let title: String
        let namespace: String
        let catalogItemId: String
        let appName: String
        let mainGameAppName: String
        let categories: [String]
        let canRunOffline: Bool
        let build: EpicBuildManifest
        let status: Status
        let note: String?
        var id: String { installationGuid }
    }

    // MARK: - scanning

    /// Every game folder under `library` that carries an `.egstore`.
    static func scan(library: URL, catalog: EpicCatalog?, registered: Set<String>,
                     fileManager f: FileManager = .default) -> [Found] {
        guard let folders = try? f.contentsOfDirectory(at: library, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles]) else { return [] }
        var out: [Found] = []
        for folder in folders.sorted(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }) {
            let egstore = folder.appendingPathComponent(".egstore")
            guard f.fileExists(atPath: egstore.path) else { continue }
            out += found(inFolder: folder, catalog: catalog, registered: registered, fileManager: f)
        }
        return out
    }

    /// What one folder holds, resolved against the catalogue.
    static func found(inFolder folder: URL, catalog: EpicCatalog?, registered: Set<String>,
                      fileManager f: FileManager = .default) -> [Found] {
        let egstore = folder.appendingPathComponent(".egstore")
        guard let entries = try? f.contentsOfDirectory(at: egstore, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        struct Parsed { let guid: String; let url: URL; let build: EpicBuildManifest; let modified: Date; let mancpnAppName: String? }
        var parsed: [Parsed] = []
        for url in entries where url.pathExtension == "manifest" {
            let guid = url.deletingPathExtension().lastPathComponent
            guard let build = try? EpicBuildManifest.read(url) else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let mancpn = egstore.appendingPathComponent(guid + ".mancpn")
            var mancpnApp: String? = nil
            if let d = try? Data(contentsOf: mancpn), let m = try? JSONDecoder().decode(Mancpn.self, from: d) { mancpnApp = m.AppName }
            parsed.append(Parsed(guid: guid, url: url, build: build, modified: modified, mancpnAppName: mancpnApp))
        }
        guard !parsed.isEmpty else { return [] }

        var out: [Found] = []
        var baseCandidates: [Parsed] = []
        for p in parsed {
            // A manifest whose app the catalogue lists: a DLC, or the base
            // game named the way the launcher names it.
            if let item = catalog?.item(forAppName: p.build.appName, namespace: nil, catalogItemId: nil) {
                if item.isBaseGame || (item.mainGameItem?.id ?? "").isEmpty {
                    baseCandidates.append(p)
                } else {
                    out.append(make(p, item: item, kind: .dlc, folder: folder, catalog: catalog, registered: registered, note: nil))
                }
            } else {
                baseCandidates.append(p)
            }
        }
        guard !baseCandidates.isEmpty else { return out }

        // The base game: the catalogue's FolderName is the folder's name.
        let byFolder = catalog?.items.first { $0.isBaseGame && $0.folderName == folder.lastPathComponent }
        let byApp = baseCandidates.compactMap { p -> (Parsed, EpicCatalogItem)? in
            guard let item = catalog?.item(forAppName: p.build.appName, namespace: nil, catalogItemId: nil), item.isBaseGame else { return nil }
            return (p, item)
        }
        let byMancpn = baseCandidates.compactMap { p -> (Parsed, EpicCatalogItem)? in
            guard let app = p.mancpnAppName, let item = catalog?.item(forAppName: app, namespace: nil, catalogItemId: nil), item.isBaseGame else { return nil }
            return (p, item)
        }
        let chosen: (Parsed, EpicCatalogItem?)
        var note: String? = nil
        if let first = byApp.first {
            chosen = first
        } else if let item = byFolder {
            // Among the unnamed manifests, the one that launches something,
            // then the newest, then the largest.
            let ranked = baseCandidates.sorted {
                if ($0.build.launchExecutable.isEmpty) != ($1.build.launchExecutable.isEmpty) { return !$0.build.launchExecutable.isEmpty }
                if $0.modified != $1.modified { return $0.modified > $1.modified }
                return $0.build.installSize > $1.build.installSize
            }
            chosen = (ranked[0], item)
        } else if let first = byMancpn.first {
            chosen = first
        } else {
            let ranked = baseCandidates.sorted { $0.modified > $1.modified }
            chosen = (ranked[0], nil)
        }
        if baseCandidates.count > 1 {
            let others = baseCandidates.filter { $0.guid != chosen.0.guid }.map { "\($0.guid.prefix(8)) \($0.build.buildVersion)" }
            note = "This folder holds \(baseCandidates.count) builds; \(chosen.0.build.buildVersion) was taken as the installed one, not \(others.joined(separator: ", "))."
        }
        out.insert(make(chosen.0, item: chosen.1, kind: .game, folder: folder, catalog: catalog, registered: registered, note: note), at: 0)
        return out

        func make(_ p: Parsed, item: EpicCatalogItem?, kind: Found.Kind, folder: URL, catalog: EpicCatalog?,
                  registered: Set<String>, note: String?) -> Found {
            let appName = item?.appNames.first ?? p.mancpnAppName ?? p.build.appName
            var mainApp = ""
            if kind == .dlc, let main = item?.mainGameItem, let mainItem = catalog?.items.first(where: { $0.namespace == main.namespace && $0.id == main.id }) {
                mainApp = mainItem.appNames.first ?? ""
            }
            let status: Found.Status = registered.contains(p.guid.uppercased()) ? .registered : (item == nil ? .unknownTitle : .ready)
            return Found(folder: folder, manifestURL: p.url, installationGuid: p.guid.uppercased(), kind: kind,
                         title: item?.title ?? folder.lastPathComponent,
                         namespace: item?.namespace ?? "", catalogItemId: item?.id ?? "", appName: appName,
                         mainGameAppName: mainApp,
                         categories: (item?.categories ?? []).compactMap(\.path),
                         canRunOffline: item?.canRunOffline ?? false,
                         build: p.build, status: status, note: note)
        }
    }

    private struct Mancpn: Decodable { let AppName: String?; let CatalogNamespace: String?; let CatalogItemId: String? }

    // MARK: - what the bottle already knows

    struct Places {
        let manifests: URL
        let installedItems: URL
        let launcherInstalled: URL
        init(bottle: URL) {
            let programData = bottle.appendingPathComponent("drive_c/ProgramData/Epic")
            manifests = programData.appendingPathComponent("EpicGamesLauncher/Data/Manifests")
            installedItems = programData.appendingPathComponent("EpicOnlineServices/InstallHelper/InstalledItems")
            launcherInstalled = programData.appendingPathComponent("UnrealEngineLauncher/LauncherInstalled.dat")
        }
    }

    /// Installation guids the launcher or the helper already has a record for.
    static func registered(in bottle: URL, fileManager f: FileManager = .default) -> Set<String> {
        let places = Places(bottle: bottle)
        var guids: Set<String> = []
        for dir in [places.manifests, places.manifests.appendingPathComponent("Pending"), places.installedItems] {
            for url in (try? f.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            where url.pathExtension == "item" || url.pathExtension == "egi" {
                guids.insert(url.deletingPathExtension().lastPathComponent.uppercased())
            }
        }
        return guids
    }

    // MARK: - writing

    enum Failure: Error, Equatable {
        case bottleIsLive
        case noLauncher
        case nothingToRegister
    }

    struct Applied: Equatable { let registered: [String]; let revision: String }

    /// Every drive letter a CrossOver bottle has maps `Z:` to `/`.
    static func windowsPath(_ url: URL) -> String {
        // A URL that knows it is a directory renders with a trailing slash;
        // the launcher's paths never end in one.
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return "Z:" + path.replacingOccurrences(of: "/", with: "\\")
    }

    /// The helper's revision: its Revision.json timestamp and number, each as
    /// sixteen hex digits. Measured from the helper's own records.
    static func revisionString(ticks: Int64, number: Int) -> String {
        String(format: "%016llX%016llX", ticks, Int64(number))
    }

    /// .NET ticks: hundreds of nanoseconds since 0001-01-01.
    static func dotNetTicks(_ date: Date) -> Int64 {
        let epochTicks: Int64 = 621_355_968_000_000_000     // 1970-01-01 in ticks
        return epochTicks + Int64(date.timeIntervalSince1970 * 10_000_000)
    }

    /// Write the records for every `ready` entry. Refuses while the bottle is
    /// up; skips what is registered; never touches an existing record.
    @discardableResult
    static func apply(_ found: [Found], bottle: URL, now: Date = Date(),
                      fileManager f: FileManager = .default) throws -> Applied {
        guard !BottleProcesses.serverIsAlive(inBottleAt: bottle) else { throw Failure.bottleIsLive }
        let places = Places(bottle: bottle)
        guard f.fileExists(atPath: places.manifests.deletingLastPathComponent().path) else { throw Failure.noLauncher }
        let todo = found.filter { $0.status == .ready }
        guard !todo.isEmpty else { throw Failure.nothingToRegister }

        try f.createDirectory(at: places.installedItems.appendingPathComponent("ManifestCache"), withIntermediateDirectories: true)
        try f.createDirectory(at: places.manifests, withIntermediateDirectories: true)

        // The helper's revision, bumped once for the batch.
        let revisionURL = places.installedItems.appendingPathComponent("Revision.json")
        var number = 0
        if let d = try? Data(contentsOf: revisionURL), let r = try? JSONDecoder().decode(Revision.self, from: d) { number = r.number }
        let ticks = dotNetTicks(now)
        let revision = revisionString(ticks: ticks, number: number + 1)

        var installed: [InstalledEntry] = []
        if let d = try? Data(contentsOf: places.launcherInstalled), let l = try? JSONDecoder().decode(LauncherInstalled.self, from: d) {
            installed = l.InstallationList
        }
        var written: [String] = []
        for g in todo {
            let item = itemJSON(for: g)
            let egi = egiJSON(for: g, revision: revision)
            try write(item, to: places.manifests.appendingPathComponent(g.installationGuid + ".item"))
            try write(egi, to: places.installedItems.appendingPathComponent(g.installationGuid + ".egi"))
            if !installed.contains(where: { $0.AppName == g.appName }) {
                installed.append(InstalledEntry(InstallLocation: windowsPath(g.folder), NamespaceId: g.namespace, ItemId: g.catalogItemId,
                                                ArtifactId: g.appName, AppVersion: g.build.buildVersion, AppName: g.appName))
            }
            written.append(g.title)
        }
        try write(LauncherInstalled(InstallationList: installed), to: places.launcherInstalled)
        try write(Revision(timestamp: ticks, number: number + 1), to: revisionURL)
        return Applied(registered: written, revision: revision)
    }

    // MARK: - the records

    private struct Revision: Codable { let timestamp: Int64; let number: Int }
    private struct InstalledEntry: Codable { let InstallLocation, NamespaceId, ItemId, ArtifactId, AppVersion, AppName: String }
    private struct LauncherInstalled: Codable { let InstallationList: [InstalledEntry] }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try f_write(try enc.encode(value), url)
    }
    private static func write(_ dict: [String: Any], to url: URL) throws {
        try f_write(try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .withoutEscapingSlashes]), url)
    }
    private static func f_write(_ data: Data, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// The launcher's own manifest, the fields it wrote back after adopting
    /// ours plus what it needs to find the build. Dictionary rather than a
    /// struct so the key order and the exact spelling are the launcher's.
    static func itemJSON(for g: Found) -> [String: Any] {
        let loc = windowsPath(g.folder)
        let meta = loc + "\\.egstore"
        let categories = g.categories.isEmpty ? ["public", "games", "applications"] : g.categories
        return [
            "FormatVersion": 0,
            "EoshRevision": "",
            "bIsIncompleteInstall": false,
            "LaunchCommand": g.build.launchCommand,
            "LaunchExecutable": g.build.launchExecutable,
            "ManifestLocation": meta,
            "CompleteManifestPath": meta + "\\" + g.installationGuid + ".manifest",
            "PendingManifestPath": meta + "\\Pending\\" + g.installationGuid + ".manifest",
            "ManifestHash": g.build.fileHash,
            "SDMetaHash": "", "SDMetaLocation": "",
            "bIsApplication": true, "bIsExecutable": !g.build.launchExecutable.isEmpty, "bIsManaged": false, "bIsFab": false,
            "bNeedsValidation": false, "bSDMetaMigrated": false, "bRequiresAuth": true, "bAllowMultipleInstances": false,
            "bCanRunOffline": g.canRunOffline, "bAllowUriCmdArgs": false, "bLaunchElevated": false,
            "BaseURLs": [String](),
            "BuildLabel": "Live",
            "AppCategories": categories,
            "ChunkDbs": [String](), "CompatibleApps": [String](),
            "DisplayName": g.title,
            "InstallationGuid": g.installationGuid,
            "InstallLocation": loc,
            "InstallSessionId": UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased(),
            "InstallTags": [String](), "InstallComponents": [String](),
            "HostInstallationGuid": "00000000000000000000000000000000",
            "PrereqSHA1Hash": "", "LastPrereqSucceededSHA1Hash": "",
            "StagingLocation": meta + "/bps",
            "TechnicalType": categories.joined(separator: ","),
            "VaultThumbnailUrl": "", "VaultTitleText": "",
            "InstallSize": g.build.installSize,
            "MainWindowProcessName": "", "ProcessNames": [String](), "BackgroundProcessNames": [String](),
            "IgnoredProcessNames": [String](), "DlcProcessNames": [String](),
            "MandatoryAppFolderName": g.folder.lastPathComponent,
            "OwnershipToken": "false",
            "SidecarConfigRevision": 0, "SidecarDeploymentId": "", "PreloadState": 0,
            "CatalogNamespace": g.namespace,
            "CatalogItemId": g.catalogItemId,
            "AppName": g.appName,
            "AppVersionString": g.build.buildVersion,
            "MainGameCatalogNamespace": g.kind == .dlc ? g.namespace : "",
            "MainGameCatalogItemId": "",
            "MainGameAppName": g.mainGameAppName,
            "AllowedUriEnvVars": [String](),
        ]
    }

    /// The helper's record, in the shape it writes its own.
    static func egiJSON(for g: Found, revision: String) -> [String: Any] {
        let loc = windowsPath(g.folder)
        let meta = loc + "\\.egstore"
        return ["v4": [
            "installationId": g.installationGuid,
            "state": "Installed",
            "revision": revision,
            "dir": loc,
            "metaDir": meta,
            "manifestPath": meta + "\\" + g.installationGuid + ".manifest",
            "pendingManifestPath": meta + "\\Pending\\" + g.installationGuid + ".manifest",
            "platform": "Windows",
            "sandboxId": g.namespace,
            "itemId": g.catalogItemId,
            "artifactId": g.appName,
            "tags": [String](), "pendingTags": [String](),
            "stagedVersion": "",
            "manifestData": ["version": g.build.buildVersion, "launchCommand": g.build.launchCommand,
                             "launchExe": g.build.launchExecutable, "prereqSHA1Hash": "", "buildSize": g.build.installSize],
            "pendingManifestData": ["version": "", "launchCommand": "", "launchExe": "", "prereqSHA1Hash": "", "buildSize": 0],
            "manifestUris": [String](),
        ]]
    }
}
