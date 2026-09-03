//
//  EpicLaunch.swift
//  RaccoonBot
//
//  Where the Epic Games Launcher is, and whether it is there at all.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated enum EpicLaunch {

    struct Target: Equatable {
        /// The bottle, as the settings store it: a file URL string.
        let bottle: String
        /// The client, as a Windows path inside that bottle.
        let clientPath: String
    }

    /// Which bottle and which executable, from what is configured.
    ///
    /// The Epic tab keeps its own bottle, and on this machine nobody has set
    /// it: the launcher was installed into the Steam bottle, which is the one
    /// the application already uses for everything. So an unset Epic bottle
    /// falls back to the selected one rather than to "no bottle", and the
    /// client path falls back to where Epic's installer always puts it.
    static func target(settings: StoreSettings, selectedBottle: String,
                       fileManager: FileManager = .default) -> Target? {
        let bottle = settings.bottle.isEmpty ? selectedBottle : settings.bottle
        guard !bottle.isEmpty else { return nil }
        if let chosen = settings.clientPath { return Target(bottle: bottle, clientPath: chosen) }
        // A launcher that has updated itself carries a Win64 build beside the
        // Win32 one, and that is the one that runs: the bottle that works
        // logs its base directory as Win64. Prefer it when it is there, and
        // fall back to Epic's installer default when it is not.
        let win64 = Store.epic.defaultClientPath.replacingOccurrences(of: "\\Win32\\", with: "\\Win64\\")
        if let path = unixPath(of: win64, inBottle: bottle), fileManager.fileExists(atPath: path) {
            return Target(bottle: bottle, clientPath: win64)
        }
        return Target(bottle: bottle, clientPath: Store.epic.defaultClientPath)
    }

    /// The client's file on this Mac, for the one question a button needs
    /// answered before it appears: is Epic installed in that bottle.
    ///
    /// `C:\Program Files (x86)\...\EpicGamesLauncher.exe` under `<bottle>/drive_c`.
    /// Only drive C is mapped; that is the only drive Epic's installer writes
    /// to, and a path on another letter would need a dosdevices lookup this
    /// does not pretend to do.
    static func unixPath(of clientPath: String, inBottle bottle: String) -> String? {
        guard let directory = BottleReference(bottle)?.directory else { return nil }
        var windows = clientPath
        guard windows.lowercased().hasPrefix("c:\\") else { return nil }
        windows.removeFirst(3)
        let relative = windows.replacingOccurrences(of: "\\", with: "/")
        return directory.appendingPathComponent("drive_c").appendingPathComponent(relative)
            .path(percentEncoded: false)
    }

    /// A bottle built by a newer CrossOver must not be opened with an older
    /// one. Wine updates a bottle it meets with a different engine, and
    /// "update" with an older engine is a downgrade of the bottle's own
    /// system files: the one thing that could take a working Epic bottle and
    /// leave it like ours. The bottle's cxbottle.conf carries the version
    /// that made it; the engine's bundle carries its own.
    static func bottleIsNewer(bottleVersion: String, engineVersion: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let b = parts(bottleVersion), e = parts(engineVersion)
        for i in 0..<max(b.count, e.count) {
            let bi = i < b.count ? b[i] : 0, ei = i < e.count ? e[i] : 0
            if bi != ei { return bi > ei }
        }
        return false
    }

    /// The version written in the bottle's own conf, or nil if it has none.
    static func bottleVersion(of bottle: String) -> String? {
        guard let directory = BottleReference(bottle)?.directory,
              let text = try? String(contentsOf: directory.appendingPathComponent("cxbottle.conf"), encoding: .utf8)
        else { return nil }
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("\"Version\""), let eq = s.firstIndex(of: "=") else { continue }
            return s[s.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        }
        return nil
    }

    static func isInstalled(_ target: Target, fileManager: FileManager = .default) -> Bool {
        guard let path = unixPath(of: target.clientPath, inBottle: target.bottle) else { return false }
        return fileManager.fileExists(atPath: path)
    }

    /// What a Play on an Epic title runs: the launcher in its bottle, given
    /// the URI that names the title.
    struct Plan: Equatable {
        let bottle: String
        let launcher: URL
        let uri: String
    }

    /// The launcher's own way of being asked to start a title, the one its
    /// desktop shortcuts use. Measured in the 5.5.4 binary (2026-09-02): it
    /// carries "com.epicgames.launcher://apps/" and "?action=launch&silent=true"
    /// as literals, and the bottle's registry has it as the handler for the
    /// scheme. `silent=true` keeps the launcher's window out of the way; it
    /// is the launcher, signed in, that runs the game, so the game gets its
    /// account, its overlay and its cloud saves, none of which running the
    /// .exe directly would give it.
    static func launchURI(forID id: String) -> String? {
        uri(forID: id, query: "action=launch&silent=true")
    }

    /// The same door, asked to install rather than to start.
    ///
    /// Measured on 2026-09-03 against launcher 5.5.4, by firing each candidate
    /// action at it and reading its own LogUriHandler: `install` is served
    /// ("AppInstallUriHandler: Catalog item resolved ... Dispatching install
    /// ...; will navigate to Library"), while `download`, `updatecheck` and
    /// `uninstall` are all answered with "Was unable to find URI Handler".
    /// That is why opening the launcher with no action at all -- what this
    /// used to do -- opened Epic and then did nothing.
    ///
    /// Only the full triple was measured, so only the full triple is sent: a
    /// launch resolves from the AppName alone, but an install has to find the
    /// catalogue item and nothing here says the short form reaches it. No
    /// `silent`: the install is the launcher's own dialog, and the user picks
    /// the folder in it.
    static func installURI(forID id: String) -> String? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
        return uri(forID: id, query: "action=install")
    }

    /// The ids are the three from the manifest joined by an encoded colon;
    /// with only the AppName known the short form still resolves for a launch.
    private static func uri(forID id: String, query: String) -> String? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "epic", !parts[3].isEmpty else { return nil }
        let ns = parts[1], item = parts[2], app = parts[3]
        let path = (ns.isEmpty || item.isEmpty) ? app : "\(ns)%3A\(item)%3A\(app)"
        return "com.epicgames.launcher://apps/\(path)?\(query)"
    }

    /// Nil when the launcher is not in the bottle: then there is nothing that
    /// can start the title, and Play says so instead of starting nothing.
    static func plan(for game: Game, settings: StoreSettings, selectedBottle: String,
                     fileManager: FileManager = .default) -> Plan? {
        // `target` chooses a path; it does not say the launcher is there.
        // Without this check a bottle with no launcher got a plan, and Play
        // ran an executable that did not exist.
        guard game.isEpic, let uri = launchURI(forID: game.id),
              let target = target(settings: settings, selectedBottle: selectedBottle, fileManager: fileManager),
              isInstalled(target, fileManager: fileManager),
              let unix = unixPath(of: target.clientPath, inBottle: target.bottle) else { return nil }
        return Plan(bottle: target.bottle, launcher: URL(fileURLWithPath: unix), uri: uri)
    }
}
