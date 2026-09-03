//
//  EpicBuildManifest.swift
//  RaccoonBot
//
//  Epic's binary build manifest, the `.egstore/<guid>.manifest` beside an
//  installed game: what the launcher wrote when it installed it, and the only
//  record of the build that survives without the launcher's own bookkeeping.
//
//  Layout, measured against nine real manifests here (2026-09-02) and
//  matching the reader in Legendary: a 41-byte header -- magic 0x44BEC00C,
//  header size, uncompressed size, compressed size, SHA-1 of the uncompressed
//  body, a "stored as" byte whose bit 0 means zlib, a version -- then the
//  body: a Meta block (app name, build version, launch executable and command,
//  prerequisites, build id), a chunk list, a file list whose chunk parts add
//  up to the install size, and custom fields. Only the Meta block and the
//  file sizes are read; the rest is skipped by the block sizes each carries.
//
//  Two things this does NOT tell. The app name here is the build's, which is
//  the catalogue AppName for most titles but not all: Borderlands 4 and Ys IX
//  carry a different id in the manifest than in the launcher's own manifest.
//  And a folder may hold more than one manifest (Alan Wake Remastered holds
//  two builds of the same app). EpicImport resolves both against the
//  catalogue cache.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Compression
import CryptoKit

nonisolated struct EpicBuildManifest: Equatable {
    static let magic: UInt32 = 0x44BEC00C

    let appName: String
    let buildVersion: String
    let launchExecutable: String
    let launchCommand: String
    let buildID: String
    let prerequisiteIDs: [String]
    let fileCount: Int
    /// The sum of every file's chunk parts: what the launcher records as
    /// InstallSize, byte for byte on the eight titles checked.
    let installSize: Int64
    let executables: [String]
    /// SHA-1 of the file as stored: the launcher's ManifestHash.
    let fileHash: String

    enum Failure: Error, Equatable {
        case tooShort, notAManifest(UInt32), unsupportedStorage(UInt8), inflateFailed, hashMismatch, truncated(String)
    }

    static func read(_ url: URL) throws -> EpicBuildManifest {
        try parse(Data(contentsOf: url))
    }

    static func parse(_ raw: Data) throws -> EpicBuildManifest {
        guard raw.count >= 41 else { throw Failure.tooShort }
        var h = Cursor(raw)
        let magic = h.u32()
        guard magic == Self.magic else { throw Failure.notAManifest(magic) }
        let headerSize = Int(h.u32())
        let uncompressedSize = Int(h.u32())
        _ = h.u32()                       // compressed size; the file's length says the same
        let sha1 = h.bytes(20)
        let storedAs = h.u8()
        _ = h.u32()                       // manifest version
        guard headerSize <= raw.count else { throw Failure.tooShort }
        let stored = raw.subdata(in: headerSize..<raw.count)
        let body: Data
        if storedAs & 1 == 1 {
            body = try inflateZlib(stored, expecting: uncompressedSize)
        } else if storedAs == 0 {
            body = stored
        } else {
            throw Failure.unsupportedStorage(storedAs)   // bit 1 would be encryption
        }
        guard Data(Insecure.SHA1.hash(data: body)) == sha1 else { throw Failure.hashMismatch }
        let meta = try readMeta(body)
        let sizes = try readFileList(body, from: meta.end)
        let fileHash = Insecure.SHA1.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        return EpicBuildManifest(appName: meta.appName, buildVersion: meta.buildVersion,
                                 launchExecutable: meta.launchExe, launchCommand: meta.launchCommand,
                                 buildID: meta.buildID, prerequisiteIDs: meta.prereqIDs,
                                 fileCount: sizes.names.count, installSize: sizes.total,
                                 executables: sizes.names.filter { $0.lowercased().hasSuffix(".exe") },
                                 fileHash: fileHash)
    }

    // MARK: - blocks

    private struct Meta { let appName, buildVersion, launchExe, launchCommand, buildID: String; let prereqIDs: [String]; let end: Int }

    private static func readMeta(_ body: Data) throws -> Meta {
        var c = Cursor(body)
        let size = Int(c.u32())
        let dataVersion = c.u8()
        _ = c.u32()                       // feature level
        _ = c.u8()                        // is file data
        _ = c.u32()                       // app id
        let appName = try c.fstring()
        let buildVersion = try c.fstring()
        let launchExe = try c.fstring()
        let launchCommand = try c.fstring()
        let n = Int(c.u32())
        var prereqIDs: [String] = []
        for _ in 0..<n { prereqIDs.append(try c.fstring()) }
        _ = try c.fstring(); _ = try c.fstring(); _ = try c.fstring()   // prereq name, path, args
        let buildID = dataVersion >= 1 ? try c.fstring() : ""
        guard size <= body.count else { throw Failure.truncated("meta") }
        return Meta(appName: appName, buildVersion: buildVersion, launchExe: launchExe,
                    launchCommand: launchCommand, buildID: buildID, prereqIDs: prereqIDs, end: size)
    }

    private struct Sizes { let names: [String]; let total: Int64 }

    private static func readFileList(_ body: Data, from metaEnd: Int) throws -> Sizes {
        var c = Cursor(body, at: metaEnd)
        // The chunk data list: skipped whole by its own size.
        let cdlStart = c.offset
        let cdlSize = Int(c.u32())
        guard cdlStart + cdlSize <= body.count else { throw Failure.truncated("chunk list") }
        c = Cursor(body, at: cdlStart + cdlSize)
        // The file manifest list.
        let fmlStart = c.offset
        let fmlSize = Int(c.u32())
        guard fmlStart + fmlSize <= body.count else { throw Failure.truncated("file list") }
        _ = c.u8()                        // version
        let count = Int(c.u32())
        var names: [String] = []
        for _ in 0..<count { names.append(try c.fstring()) }
        for _ in 0..<count { _ = try c.fstring() }          // symlink targets
        c.skip(20 * count)                                   // sha1 per file
        c.skip(count)                                        // flags per file
        for _ in 0..<count {                                 // install tags per file
            let n = Int(c.u32()); for _ in 0..<n { _ = try c.fstring() }
        }
        var total: Int64 = 0
        for _ in 0..<count {                                 // chunk parts per file
            let parts = Int(c.u32())
            for _ in 0..<parts {
                _ = c.u32(); c.skip(16); _ = c.u32()         // struct size, guid, offset
                total += Int64(c.u32())
            }
        }
        guard c.offset <= fmlStart + fmlSize else { throw Failure.truncated("file list overrun") }
        return Sizes(names: names, total: total)
    }

    // MARK: - bytes

    private struct Cursor {
        let data: Data
        var offset: Int
        init(_ data: Data, at offset: Int = 0) { self.data = data; self.offset = offset }
        mutating func u8() -> UInt8 { defer { offset += 1 }; return offset < data.count ? data[data.startIndex + offset] : 0 }
        mutating func u32() -> UInt32 {
            var v: UInt32 = 0
            for i in 0..<4 { v |= UInt32(u8()) << (8 * UInt32(i)) }
            return v
        }
        mutating func i32() -> Int32 { Int32(bitPattern: u32()) }
        mutating func bytes(_ n: Int) -> Data {
            let start = data.startIndex + min(offset, data.count)
            let end = data.startIndex + min(offset + n, data.count)
            offset += n
            return data.subdata(in: start..<end)
        }
        mutating func skip(_ n: Int) { offset += n }
        /// Unreal's FString: a signed length counting the terminator, negative
        /// for UTF-16, zero for empty.
        mutating func fstring() throws -> String {
            let n = Int(i32())
            if n == 0 { return "" }
            if n < 0 {
                // The terminator is dropped from the bytes, not from the
                // decoded string: String.prefix counts grapheme clusters,
                // and a surrogate pair or a combining accent has fewer of
                // those than it has code units, which left the NUL on.
                let d = bytes(2 * -n)
                guard d.count == 2 * -n, let s = String(data: d.prefix(2 * (-n - 1)), encoding: .utf16LittleEndian) else { throw Failure.truncated("string") }
                return s
            }
            let d = bytes(n)
            guard d.count == n else { throw Failure.truncated("string") }
            return String(decoding: d.prefix(n - 1), as: UTF8.self)
        }
    }

    /// zlib is a two-byte header around a raw DEFLATE stream and an Adler-32
    /// after it; Apple's Compression takes the stream alone.
    static func inflateZlib(_ zlib: Data, expecting size: Int) throws -> Data {
        guard zlib.count > 6, size > 0 else { throw Failure.inflateFailed }
        let deflate = zlib.subdata(in: (zlib.startIndex + 2)..<zlib.endIndex)
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            deflate.withUnsafeBytes { src -> Int in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, deflate.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Failure.inflateFailed }
        return out
    }
}
