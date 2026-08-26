//
//  WindowsPath.swift
//  RaccoonBot
//
//  Turning a path a Windows program wrote into a path macOS can open.
//
//  Steam records its libraries as "D:\SteamLibrary". Epic records every install
//  location the same way. Neither means anything until it is read through the
//  bottle's dosdevices directory, which is where Wine keeps the drive letters.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// What became of a Windows path when we went looking for it.
///
/// Four outcomes, because the two that used to be one are the two that matter
/// most. A game on an external drive that is not plugged in is not the same as
/// a game that was deleted, and telling somebody the second when the first is
/// true invites them to redownload eighty gigabytes they already own.
nonisolated enum WindowsPathResolution: Equatable, Sendable {
    /// The drive letter maps and the target is on disk.
    case resolved(URL)
    /// The drive letter maps, but the drive itself is not mounted.
    case volumeOffline(URL)
    /// The drive is mounted; this particular folder is not on it.
    case missing(URL)
    /// This bottle has no such drive letter. Carries what was asked for.
    case noSuchDrive(String)

    /// Where it would be, whether or not it is there.
    var url: URL? {
        switch self {
        case .resolved(let u), .volumeOffline(let u), .missing(let u): return u
        case .noSuchDrive: return nil
        }
    }

    /// Only true when something is actually at the other end.
    var isPresent: Bool {
        if case .resolved = self { return true }
        return false
    }

    /// True when the path is fine and the disk is elsewhere. The interface
    /// greys these out rather than calling them uninstalled.
    var isOffline: Bool {
        if case .volumeOffline = self { return true }
        return false
    }
}

/// One bottle's drive letters, read once.
///
/// Reading dosdevices is a directory listing plus a readlink for each entry,
/// and a library scan asks the same question for every title it finds. Doing
/// it once per scan rather than once per title is the difference between one
/// listing and several hundred.
nonisolated struct BottleDrives: Sendable {

    /// Keyed by uppercase letter and colon: "C:", "Z:".
    let letters: [String: URL]

    init(bottle: URL) {
        self.init(dosdevices: bottle.appendingPathComponent("dosdevices", isDirectory: true))
    }

    init(dosdevices: URL) {
        // Relative link targets are resolved against this, so it has to be
        // known to be a directory whatever the caller passed in.
        let base = URL(filePath: dosdevices.path(percentEncoded: false), directoryHint: .isDirectory)
        let f = FileManager.default
        var found: [String: URL] = [:]

        let entries = (try? f.contentsOfDirectory(at: base,
                                                  includingPropertiesForKeys: nil,
                                                  options: .skipsHiddenFiles)) ?? []
        for entry in entries {
            let name = entry.lastPathComponent
            // CrossOver writes two entries per drive: "d:" for the folder and
            // "d::" for the device it was mounted from. The second is a path
            // to /dev/rdisk7s2 and cannot be opened as a directory, so the
            // only safe key is exactly a letter and one colon.
            guard name.count == 2,
                  name.hasSuffix(":"),
                  let letter = name.first, letter.isLetter else { continue }
            guard let target = try? f.destinationOfSymbolicLink(
                    atPath: entry.path(percentEncoded: false)) else { continue }

            // "c:" is a relative link to ../drive_c. Reading it as an absolute
            // path gives /drive_c, which exists on nobody's Mac.
            let resolved = target.hasPrefix("/")
                ? target
                : URL(filePath: target, relativeTo: base).standardizedFileURL
                    .path(percentEncoded: false)
            found[name.uppercased()] = Self.fileURL(resolved)
        }
        self.letters = found
    }

    /// The macOS location of a drive letter, if this bottle has one.
    func root(ofDrive letter: String) -> URL? {
        letters[normaliseKey(letter)]
    }

    /// Where a Windows path lands on this Mac, and what is there.
    func resolve(_ winPath: String) -> WindowsPathResolution {
        // Windows tolerates either separator and so does Wine; manifests in
        // the wild carry both, sometimes in the same string.
        let normalised = winPath.replacingOccurrences(of: "\\", with: "/")

        let key = String(normalised.prefix(2)).uppercased()
        guard key.count == 2, key.hasSuffix(":"), key.first?.isLetter == true else {
            return .noSuchDrive(key)
        }
        guard let root = letters[key] else { return .noSuchDrive(key) }

        // Joined as text rather than by appendingPathComponent, which asks
        // the file system whether each component is a directory and stamps a
        // trailing slash on the answer. Two spellings of one path would then
        // compare unequal depending on what happened to be mounted.
        var path = root.path(percentEncoded: false)
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        for part in normalised.dropFirst(2).split(separator: "/") {
            path += "/" + part
        }
        let url = Self.fileURL(path)

        let f = FileManager.default
        if f.fileExists(atPath: url.path(percentEncoded: false)) {
            return .resolved(url)
        }
        // The drive maps but the target does not exist. Which of the two
        // things went wrong is one more stat call, and it is the difference
        // between "plug your disk back in" and "this is gone".
        return f.fileExists(atPath: root.path(percentEncoded: false))
            ? .missing(url)
            : .volumeOffline(url)
    }

    /// A file URL whose text form does not depend on what is mounted.
    ///
    /// URL spells a directory with a trailing slash and a file without one,
    /// and decides which by looking at the disk. For a path on a drive that is
    /// not plugged in it looks, finds nothing, and picks the other spelling --
    /// so the same library compares unequal to itself once the disk comes back.
    private static func fileURL(_ path: String) -> URL {
        var p = path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return URL(filePath: p, directoryHint: .notDirectory)
    }

    private func normaliseKey(_ letter: String) -> String {
        let trimmed = letter.uppercased().replacingOccurrences(of: ":", with: "")
        return trimmed + ":"
    }
}
