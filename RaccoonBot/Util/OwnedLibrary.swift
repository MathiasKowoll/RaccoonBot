//
//  OwnedLibrary.swift
//  RaccoonBot
//
//  Everything the user owns, not just what is installed -- read from disk.
//
//  Three files Steam already keeps, none of them requiring a key, a login or a
//  request:
//
//    userdata/<id>/config/localconfig.vdf   which app ids this account owns,
//                                           with LastPlayed and Playtime
//    appcache/appinfo.vdf                   their names, type and oslist
//    appcache/librarycache/<appid>/         their cover art
//
//  Measured on a real machine: 427 owned titles, 391 with a name locally,
//  388 with art already downloaded. Upstream got this list from a proxy holding
//  a Steam Web API key, because GetOwnedGames refuses an unkeyed caller -- but
//  the Steam client had already written the answer to the disk.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

struct OwnedGame: Identifiable, Sendable, Equatable {
    let appID: String
    /// Empty when appinfo.vdf has no record: 36 of 427 on the machine this was
    /// measured on. Shown by app id rather than hidden, because the cover
    /// usually carries the title and a request each would be 36 more.
    let name: String
    let platforms: Set<String>
    let lastPlayed: Date?
    let playtimeMinutes: Int?
    let coverURL: URL?

    var id: String { appID }
    var displayName: String { name.isEmpty ? "App \(appID)" : name }
    var runsOnMac: Bool { platforms.contains("macos") }
    var runsOnWindows: Bool { platforms.contains("windows") }
    /// Both, so the install has to ask which one the user wants.
    var isCrossPlatform: Bool { runsOnMac && runsOnWindows }
}

enum OwnedLibrary {

    /// Every Steam installation inside a bottle. A machine can have more than
    /// one bottle and each carries its own Steam.
    static func steamRoots(fileManager: FileManager = .default) -> [URL] {
        let bottles = PROCYON_SUPPORT_FOLDER_URL
            .appendingPathComponent(DEFAULT_CXP_BOTTLES_FOLDER, isDirectory: true)
        guard let names = try? fileManager.contentsOfDirectory(atPath: bottles.path(percentEncoded: false))
        else { return [] }
        return names
            .map { bottles.appendingPathComponent($0).appendingPathComponent(DEFAULT_STEAM_WINE_PATH) }
            .filter { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// localconfig.vdf sits under a numeric account directory, and there can be
    /// more than one account.
    static func localConfigs(inSteamAt steam: URL, fileManager: FileManager = .default) -> [URL] {
        let userdata = steam.appendingPathComponent("userdata", isDirectory: true)
        guard let accounts = try? fileManager.contentsOfDirectory(atPath: userdata.path(percentEncoded: false))
        else { return [] }
        return accounts
            .map { userdata.appendingPathComponent($0).appendingPathComponent("config/localconfig.vdf") }
            .filter { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// app id -> (lastPlayed, playtime), read out of one localconfig.
    static func ownedApps(inLocalConfigAt url: URL) -> [String: (lastPlayed: Date?, playtime: Int?)] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        let parsed = parseVDFToDict(from: text)
        // UserLocalConfigStore -> Software -> Valve -> Steam -> apps
        var node = parsed as [String: Any]
        for key in ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps"] {
            guard let next = caseInsensitive(node, key) as? [String: Any] else { return [:] }
            node = next
        }
        var out: [String: (Date?, Int?)] = [:]
        for (appID, value) in node {
            guard appID.allSatisfy(\.isNumber), !appID.isEmpty else { continue }
            let fields = value as? [String: Any] ?? [:]
            var played: Date?
            if let raw = caseInsensitive(fields, "LastPlayed") as? String, let seconds = TimeInterval(raw), seconds > 0 {
                played = Date(timeIntervalSince1970: seconds)
            }
            let minutes = (caseInsensitive(fields, "Playtime") as? String).flatMap(Int.init)
            out[appID] = (played, minutes)
        }
        return out
    }

    /// Steam writes these keys with inconsistent capitalisation between client
    /// versions, and a miss here silently empties the whole library.
    private static func caseInsensitive(_ dict: [String: Any], _ key: String) -> Any? {
        if let exact = dict[key] { return exact }
        let wanted = key.lowercased()
        return dict.first { $0.key.lowercased() == wanted }?.value
    }

    /// The full owned library, minus anything already installed.
    ///
    /// `installed` is the set of app ids the .acf scan found, which the other
    /// tab is already showing.
    static func notInstalled(installed: Set<String>,
                             fileManager: FileManager = .default) -> [OwnedGame] {
        var owned: [String: (lastPlayed: Date?, playtime: Int?)] = [:]
        var info: [String: AppInfoEntry] = [:]

        for steam in steamRoots(fileManager: fileManager) {
            for config in localConfigs(inSteamAt: steam, fileManager: fileManager) {
                for (appID, value) in ownedApps(inLocalConfigAt: config) where owned[appID] == nil {
                    owned[appID] = value
                }
            }
            info.merge(AppInfoVDF.read(at: AppInfoVDF.url(inSteamAt: steam))) { first, _ in first }
        }

        let caches = LocalLibrary.artCaches(fileManager: fileManager)
        return owned.compactMap { appID, played -> OwnedGame? in
            if installed.contains(appID) { return nil }
            let entry = info[appID]
            // A known non-game is dropped; an UNKNOWN one is kept, because not
            // knowing what something is differs from knowing it is a soundtrack.
            if let entry, !entry.isGame { return nil }
            return OwnedGame(appID: appID,
                             name: entry?.name ?? "",
                             platforms: entry?.platforms ?? [],
                             lastPlayed: played.lastPlayed,
                             playtimeMinutes: played.playtime,
                             coverURL: LocalLibrary.coverURL(forAppID: appID, caches: caches,
                                                             fileManager: fileManager))
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
