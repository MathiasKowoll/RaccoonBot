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
    static func target(settings: StoreSettings, selectedBottle: String) -> Target? {
        let bottle = settings.bottle.isEmpty ? selectedBottle : settings.bottle
        guard !bottle.isEmpty else { return nil }
        return Target(bottle: bottle, clientPath: settings.clientPath ?? Store.epic.defaultClientPath)
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
}
