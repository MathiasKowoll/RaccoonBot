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

nonisolated struct OwnedGame: Identifiable, Sendable, Equatable {
    let appID: String
    /// Empty when appinfo.vdf has no record: 36 of 427 on the machine this was
    /// measured on. Shown by app id rather than hidden, because the cover
    /// usually carries the title and a request each would be 36 more.
    let name: String
    let platforms: Set<String>
    let lastPlayed: Date?
    let playtimeMinutes: Int?
    /// Filled in later for the titles Steam never cached art for: the list is
    /// drawn first, with placeholders, and these arrive one at a time.
    var coverURL: URL?

    var id: String { appID }
    var displayName: String { name.isEmpty ? "App \(appID)" : name }
    var runsOnMac: Bool { platforms.contains("macos") }
    var runsOnWindows: Bool { platforms.contains("windows") }
    /// Both, so the install has to ask which one the user wants.
    var isCrossPlatform: Bool { runsOnMac && runsOnWindows }
}

enum OwnedLibrary {
    // Every one of these reads files and returns values. None of them touches
    // the interface, so none belongs on the main actor -- and being on it was
    // not merely untidy: GamesList hands notInstalled() to a Task.detached
    // precisely to keep a 4.7 MB parse off the main thread, and a main-actor
    // function hops straight back onto it. The detachment was doing nothing.


    /// Every Steam installation inside a bottle. A machine can have more than
    /// one bottle and each carries its own Steam.
    nonisolated static func steamRoots(fileManager: FileManager = .default) -> [URL] {
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
    nonisolated static func localConfigs(inSteamAt steam: URL, fileManager: FileManager = .default) -> [URL] {
        let userdata = steam.appendingPathComponent("userdata", isDirectory: true)
        guard let accounts = try? fileManager.contentsOfDirectory(atPath: userdata.path(percentEncoded: false))
        else { return [] }
        return accounts
            .map { userdata.appendingPathComponent($0).appendingPathComponent("config/localconfig.vdf") }
            .filter { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// app id -> (lastPlayed, playtime), read out of one localconfig.
    ///
    /// Scanned directly rather than through parseVDFToDict. That parser builds
    /// the entire file into nested dictionaries, and on a real localconfig it
    /// does not come back: a string token followed by a closing brace advances
    /// no pointer, so the loop spins. It also calls fatalError() in its lexer.
    /// Neither is a thing to run on a file Steam writes.
    ///
    /// This wants one block and three fields, so it reads them and nothing
    /// else. No recursion, no regex, no whole-file model.
    nonisolated static func ownedApps(inLocalConfigAt url: URL) -> [String: (lastPlayed: Date?, playtime: Int?)] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return ownedApps(inLocalConfig: text)
    }

    nonisolated static func ownedApps(inLocalConfig text: String) -> [String: (lastPlayed: Date?, playtime: Int?)] {
        var out: [String: (Date?, Int?)] = [:]
        let scalars = Array(text.unicodeScalars)

        /// The next quoted string at or after `index`, and where it ended.
        func nextQuoted(from index: Int) -> (value: String, end: Int)? {
            var i = index
            while i < scalars.count, scalars[i] != "\"" { i += 1 }
            guard i < scalars.count else { return nil }
            var value = String.UnicodeScalarView()
            i += 1
            while i < scalars.count, scalars[i] != "\"" {
                if scalars[i] == "\\", i + 1 < scalars.count { i += 1 }
                value.append(scalars[i]); i += 1
            }
            guard i < scalars.count else { return nil }
            return (String(value), i + 1)
        }

        /// The first `{` after `index`, skipping whitespace only. Anything else
        /// means this key had a value rather than a block.
        func openBrace(after index: Int) -> Int? {
            var i = index
            while i < scalars.count {
                let s = scalars[i]
                if s == "{" { return i + 1 }
                if s == " " || s == "\t" || s == "\n" || s == "\r" { i += 1; continue }
                return nil
            }
            return nil
        }

        // Find the apps block: a key "apps" whose value is an object.
        var cursor = 0
        var appsBody: Int?
        while let (key, end) = nextQuoted(from: cursor) {
            if key.lowercased() == "apps", let body = openBrace(after: end) {
                appsBody = body
                break
            }
            cursor = end
        }
        guard var i = appsBody else { return [:] }

        // Walk its direct children. Depth is counted rather than recursed so a
        // surprising shape cannot blow the stack or spin.
        while i < scalars.count {
            if scalars[i] == "}" { break }                       // end of apps
            guard let (appID, afterKey) = nextQuoted(from: i) else { break }
            guard let body = openBrace(after: afterKey) else { i = afterKey; continue }

            var depth = 1
            var j = body
            var lastPlayed: Date?
            var playtime: Int?
            while j < scalars.count, depth > 0 {
                switch scalars[j] {
                case "{": depth += 1; j += 1
                case "}": depth -= 1; j += 1
                case "\"":
                    guard let (field, afterField) = nextQuoted(from: j) else { j = scalars.count; break }
                    // Only fields directly on this app, not inside "cloud" etc.
                    if depth == 1, let (value, afterValue) = nextQuoted(from: afterField),
                       openBrace(after: afterField) == nil {
                        switch field.lowercased() {
                        case "lastplayed":
                            if let seconds = TimeInterval(value), seconds > 0 {
                                lastPlayed = Date(timeIntervalSince1970: seconds)
                            }
                        case "playtime": playtime = Int(value)
                        default: break
                        }
                        j = afterValue
                    } else {
                        j = afterField
                    }
                default: j += 1
                }
            }
            if appID.allSatisfy(\.isNumber), !appID.isEmpty {
                out[appID] = (lastPlayed, playtime)
            }
            i = j
        }
        return out
    }

    /// The full owned library, minus anything already installed.
    ///
    /// `installed` is the set of app ids the .acf scan found, which the other
    /// tab is already showing.
    nonisolated static func notInstalled(installed: Set<String>,
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
            // Only titles appinfo can actually name. A card reading "App
            // 1139900" tells nobody anything, and there is no cheap way to
            // learn the name: it would be one store request each, for entries
            // that are disproportionately the odd ones -- tools, delisted
            // things, and apps this Steam merely heard about.
            guard let entry = info[appID], !entry.name.isEmpty else { return nil }
            if !entry.isGame { return nil }
            return OwnedGame(appID: appID,
                             name: entry.name,
                             platforms: entry.platforms,
                             lastPlayed: played.lastPlayed,
                             playtimeMinutes: played.playtime,
                             coverURL: LocalLibrary.coverURL(forAppID: appID, caches: caches,
                                                             fileManager: fileManager))
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
