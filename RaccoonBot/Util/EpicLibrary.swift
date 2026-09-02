//
//  EpicLibrary.swift
//  RaccoonBot
//
//  What the Epic Games Launcher says is installed, read from its own records
//  in the one bottle configured for it.
//
//  Read-only. The launcher keeps one JSON file per installed title under
//  ProgramData\Epic\EpicGamesLauncher\Data\Manifests, and that is the
//  appmanifest_*.acf of this store. Everything here follows docs/epic-design.md:
//  the id comes from inside the file and never from its name; the decode is
//  permissive because real manifests carry keys no template knows; every path
//  in a manifest is a Windows path on some drive letter and goes through the
//  bottle's dosdevices, except LaunchExecutable, which is a bare file name
//  joined onto the folder once the folder is known; and reads are keyed to
//  the ONE Epic bottle from configuration, because the same records exist
//  in several bottles on this machine and scanning them all would surface
//  the same four games four times over.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// One `.item` file, as Epic writes it. Everything optional but the name,
/// so a manifest with a key missing decodes rather than throws.
nonisolated struct EpicManifest: Decodable, Equatable {
    let AppName: String
    var DisplayName: String?
    var CatalogNamespace: String?
    var CatalogItemId: String?
    var MainGameAppName: String?
    var InstallLocation: String?
    var LaunchExecutable: String?
    var AppCategories: [String]?
    var bIsIncompleteInstall: Bool?
    var AppVersionString: String?
    var InstallSize: Int64?

    /// A game, as opposed to Unreal Engine, a launcher component or a tool.
    var isGame: Bool { AppCategories?.contains("games") == true }

    /// DLC iff it names a main game that is not itself. Base games carry an
    /// EMPTY MainGameAppName in real data, so "main == self" would drop them.
    var isDLC: Bool {
        guard let main = MainGameAppName, !main.isEmpty else { return false }
        return main != AppName
    }

    var isComplete: Bool { bIsIncompleteInstall != true }

    /// The store-tagged identity, in the three-part form the launcher's own
    /// URL scheme uses. Persisted as a string; never a bare AppName.
    var tripleID: String {
        "epic:\(CatalogNamespace ?? ""):\(CatalogItemId ?? ""):\(AppName)"
    }
}

/// A title the launcher has installed, located on this Mac.
nonisolated struct EpicInstalled: Equatable, Sendable {
    enum Presence: Equatable, Sendable {
        case installed
        /// The drive it lives on maps in the bottle but is not mounted now.
        case volumeOffline
    }
    let id: String
    let appName: String
    let title: String
    let folder: URL
    let executable: URL?
    let version: String
    let presence: Presence
}

nonisolated enum EpicLibrary {

    static let defaultDataPath = #"C:\ProgramData\Epic\EpicGamesLauncher\Data"#

    /// The three filters, as one question, so a caller cannot apply two.
    static func isListable(_ m: EpicManifest) -> Bool {
        m.isGame && m.isComplete && !m.isDLC
    }

    /// Where the launcher keeps its records in this bottle.
    ///
    /// Asked of the bottle's registry first -- the launcher writes AppDataPath
    /// under Software\Wow6432Node\Epic Games\EpicGamesLauncher, with that
    /// casing -- and of the conventional location when the key is not there.
    /// A .reg value is written with doubled backslashes and a trailing one;
    /// both are undone here, because no caller has read a REG_SZ path through
    /// the parser before and it does not.
    static func dataPath(inBottle bottle: URL) -> String {
        let reg = WineRegistryFile(fileURL: bottle.appendingPathComponent("system.reg"))
        // Parsing is a separate step from construction; the launcher's own
        // registry writes do the same. Without it there are no sections at all.
        try? reg.load()
        // The parser keeps the header's own spelling of the path; a .reg file
        // doubles its backslashes. Ask with both, so a change in how the
        // parser normalises does not silently turn this into the fallback.
        let doubled = #"Software\\Wow6432Node\\Epic Games\\EpicGamesLauncher"#
        let single  = #"Software\Wow6432Node\Epic Games\EpicGamesLauncher"#
        guard let section = reg.section(forPath: doubled) ?? reg.section(forPath: single) else {
            return defaultDataPath
        }
        // The raw line, wherever the parser filed it. A REG_SZ whose value
        // ends in a backslash -- every path Epic writes does -- is not a
        // shape the value parser was ever asked to accept, and a line it
        // does not accept is kept as a trailing line rather than dropped.
        // Reading both is what makes this the first REG_SZ path read through
        // the parser without also being the first to change it.
        let lines = section.values.map(\.value.rawLine) + section.trailingLines.map { $0.trimmingCharacters(in: .whitespaces) }
        for line in lines {
            guard line.hasPrefix(#""AppDataPath"="#) else { continue }
            var value = String(line.dropFirst(#""AppDataPath"="#.count))
            if value.hasPrefix("\"") { value.removeFirst() }
            if value.hasSuffix("\"") { value.removeLast() }
            value = value.replacingOccurrences(of: "\\\\", with: "\\")
            while value.hasSuffix("\\") { value.removeLast() }
            return value.isEmpty ? defaultDataPath : value
        }
        return defaultDataPath
    }

    /// Every listable title the launcher in this bottle has installed.
    static func read(bottle: URL, fileManager f: FileManager = .default) -> [EpicInstalled] {
        let drives = BottleDrives(bottle: bottle)
        guard case .resolved(let data) = drives.resolve(dataPath(inBottle: bottle)) else { return [] }
        let manifests = data.appendingPathComponent("Manifests")
        let files = ((try? f.contentsOfDirectory(at: manifests, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "item" }
        let decoder = JSONDecoder()
        var seen: Set<String> = []
        var out: [EpicInstalled] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let bytes = try? Data(contentsOf: file),
                  let m = try? decoder.decode(EpicManifest.self, from: bytes),
                  isListable(m), !seen.contains(m.AppName),
                  let installed = locate(m, drives: drives) else { continue }
            seen.insert(m.AppName)
            out.append(installed)
        }
        return out.sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    /// Where a manifest's install lands on this Mac, or nil when it is gone.
    ///
    /// Offline is kept: "plug the disk back in" is a state worth showing,
    /// where "this folder does not exist" is not a game.
    static func locate(_ m: EpicManifest, drives: BottleDrives) -> EpicInstalled? {
        guard let location = m.InstallLocation, !location.isEmpty else { return nil }
        let presence: EpicInstalled.Presence
        let folder: URL
        switch drives.resolve(location) {
        case .resolved(let url):      folder = url; presence = .installed
        case .volumeOffline(let url): folder = url; presence = .volumeOffline
        case .missing, .noSuchDrive:  return nil
        }
        // A bare file name, joined onto the folder. Not resolved: it carries
        // no drive letter and would be reported as no such drive.
        let exe = (m.LaunchExecutable ?? "").isEmpty ? nil : folder.appendingPathComponent(m.LaunchExecutable!)
        return EpicInstalled(id: m.tripleID,
                             appName: m.AppName,
                             title: m.DisplayName ?? m.AppName,
                             folder: folder,
                             executable: exe,
                             version: m.AppVersionString ?? "",
                             presence: presence)
    }
}
