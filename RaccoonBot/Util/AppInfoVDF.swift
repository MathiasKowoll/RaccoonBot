//
//  AppInfoVDF.swift
//  RaccoonBot
//
//  Reading the names Steam already knows, out of its own binary cache.
//
//  The .acf files name the titles that are INSTALLED. For the rest of a
//  library there is appcache/appinfo.vdf: a binary KeyValues file Steam keeps
//  for every app it has heard of. Measured on a real machine: 2076 apps parsed
//  with zero errors, covering 391 of that user's 427 owned titles. The
//  alternative is one network request per title, which for a 400-game library
//  is seven minutes of asking Valve for something already on the disk.
//
//  Format, version 0x07564429 ("v29"):
//
//      uint32   magic
//      uint32   universe
//      int64    offset of the string table          <- header is 16 bytes, not 12
//      per app: uint32 appid (0 ends the file)
//               uint32 size of the rest of this record
//               uint32 infoState, uint32 lastUpdated,
//               uint64 picsToken, 20 bytes sha1(text),
//               uint32 changeNumber, 20 bytes sha1(binary)
//               binary KeyValues blob
//      table:   uint32 count, then that many NUL-terminated strings
//
//  In v28 and v29 every KEY is a uint32 index into that table rather than an
//  inline string, which is what makes this cheap to walk.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Plain data, read off a disk. Nothing about it belongs to the interface, so
/// nothing about it belongs on the main actor -- and leaving it there would
/// have dragged the parser back onto the main thread through its own results.
nonisolated struct AppInfoEntry: Sendable, Equatable {
    let appID: String
    let name: String
    /// "Game", "DLC", "Demo", "Tool", "Music"… Only Game is worth listing.
    let type: String
    /// Steam's own comma list, e.g. "windows,macos,linux".
    let osList: String

    var isGame: Bool { type.lowercased() == "game" }
    var runsOnMac: Bool { platforms.contains("macos") }
    var runsOnWindows: Bool { platforms.contains("windows") }

    /// Trimmed: at least one record in the wild carries " macos" with a leading
    /// space, and a raw split would silently drop that title from the Mac side.
    var platforms: Set<String> {
        Set(osList.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        })
    }
}

nonisolated enum AppInfoVDF {

    static let supportedMagic: Set<UInt32> = [0x07564428, 0x07564429]

    /// Where Steam keeps it inside a bottle.
    static func url(inSteamAt steam: URL) -> URL {
        steam.appendingPathComponent("appcache/appinfo.vdf")
    }

    /// Returns app id -> entry. Never throws on a malformed file: a truncated
    /// or unfamiliar cache means fewer names, not a dead library.
    static func read(at url: URL) -> [String: AppInfoEntry] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [:] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [String: AppInfoEntry] {
        let bytes = [UInt8](data)
        guard bytes.count > 16 else { return [:] }
        let magic = u32(bytes, 0)
        guard supportedMagic.contains(magic) else { return [:] }

        let tableOffset = Int(i64(bytes, 8))
        guard tableOffset > 16, tableOffset + 4 <= bytes.count else { return [:] }

        // The string table, read first because every key is an index into it.
        let count = Int(u32(bytes, tableOffset))
        var strings: [String] = []
        strings.reserveCapacity(count)
        var cursor = tableOffset + 4
        for _ in 0..<count {
            guard cursor < bytes.count else { break }
            var end = cursor
            while end < bytes.count, bytes[end] != 0 { end += 1 }
            strings.append(String(decoding: bytes[cursor..<end], as: UTF8.self))
            cursor = end + 1
        }
        guard !strings.isEmpty else { return [:] }

        var found: [String: AppInfoEntry] = [:]
        var position = 16
        while position + 8 <= tableOffset {
            let appID = u32(bytes, position)
            if appID == 0 { break }
            let size = Int(u32(bytes, position + 4))
            let body = position + 8
            // infoState 4, lastUpdated 4, picsToken 8, sha1 20, change 4, sha1 20
            let blob = body + 60
            let end = body + size
            guard size > 0, end <= tableOffset, blob < end else { break }

            var fields: [String: String] = [:]
            _ = walk(bytes, from: blob, to: end, strings: strings, path: [], into: &fields)
            if let name = fields["name"], !name.isEmpty {
                found[String(appID)] = AppInfoEntry(appID: String(appID),
                                                    name: name,
                                                    type: fields["type"] ?? "",
                                                    osList: fields["oslist"] ?? "")
            }
            position = end
        }
        return found
    }

    /// Walks one binary KeyValues blob, collecting only the three fields under
    /// `common` that a library card needs. Everything else is skipped by size,
    /// which is why this stays fast over a 4.7 MB file.
    private static func walk(_ bytes: [UInt8], from start: Int, to end: Int,
                             strings: [String], path: [String],
                             into fields: inout [String: String]) -> Int {
        var i = start
        while i < end {
            let type = bytes[i]; i += 1
            if type == 0x08 { return i }                 // end of this object
            guard i + 4 <= end else { return end }
            let keyIndex = Int(u32(bytes, i)); i += 4
            let key = keyIndex < strings.count ? strings[keyIndex].lowercased() : ""

            switch type {
            case 0x00:                                    // nested object
                i = walk(bytes, from: i, to: end, strings: strings, path: path + [key], into: &fields)
            case 0x01:                                    // string
                var stop = i
                while stop < end, bytes[stop] != 0 { stop += 1 }
                if path.last == "common", ["name", "type", "oslist"].contains(key) {
                    fields[key] = String(decoding: bytes[i..<stop], as: UTF8.self)
                }
                i = stop + 1
            case 0x02, 0x03, 0x04, 0x06: i += 4           // int32, float, pointer, colour
            case 0x07, 0x0A: i += 8                       // uint64, int64
            case 0x05:                                    // wide string, UTF-16
                var stop = i
                while stop + 1 < end, !(bytes[stop] == 0 && bytes[stop + 1] == 0) { stop += 2 }
                i = stop + 2
            default:
                return end                                // unknown tag: stop, do not guess
            }
        }
        return i
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | UInt32(b[o+1]) << 8 | UInt32(b[o+2]) << 16 | UInt32(b[o+3]) << 24
    }

    private static func i64(_ b: [UInt8], _ o: Int) -> Int64 {
        guard o + 8 <= b.count else { return 0 }
        var v: UInt64 = 0
        for k in (0..<8).reversed() { v = v << 8 | UInt64(b[o + k]) }
        return Int64(bitPattern: v)
    }
}
