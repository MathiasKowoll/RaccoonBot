//
//  EpicBuildManifestTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
import CryptoKit
@testable import RaccoonBot

/// A manifest built here in the launcher's own layout, read back.
struct EpicBuildManifestTests {

    // MARK: a writer for the layout, so the reader can be tested without a game

    struct W {
        var d = Data()
        mutating func u8(_ v: UInt8) { d.append(v) }
        mutating func u32(_ v: UInt32) { for i in 0..<4 { d.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
        mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
        mutating func bytes(_ n: Int, _ b: UInt8 = 0) { d.append(Data(repeating: b, count: n)) }
        mutating func fstr(_ s: String, utf16: Bool = false) {
            if s.isEmpty { i32(0); return }
            if utf16 {
                let u = Array(s.utf16) + [0]
                i32(-Int32(u.count)); for c in u { u8(UInt8(c & 0xFF)); u8(UInt8(c >> 8)) }
            } else {
                let u = Array(s.utf8) + [0]
                i32(Int32(u.count)); d.append(contentsOf: u)
            }
        }
    }

    static func body(appName: String = "app1", version: String = "1.2.3", exe: String = "Game.exe",
                     files: [(String, [UInt32])] = [("Game.exe", [10, 20]), ("data/a.pak", [1000])], utf16: Bool = false) -> Data {
        var meta = W()
        meta.u8(1)                      // data version 1: build id present
        meta.u32(17); meta.u8(0); meta.u32(0)
        meta.fstr(appName, utf16: utf16); meta.fstr(version); meta.fstr(exe); meta.fstr("-arg")
        meta.u32(1); meta.fstr("prereq1")
        meta.fstr("Prereq"); meta.fstr("p.exe"); meta.fstr("/q")
        meta.fstr("BUILDID")
        var m = W(); m.u32(UInt32(meta.d.count + 4)); m.d.append(meta.d)
        // chunk list: size, version, count, then nothing (skipped by size)
        var cdl = W(); cdl.u8(0); cdl.u32(0)
        var c = W(); c.u32(UInt32(cdl.d.count + 4)); c.d.append(cdl.d)
        // file list
        var fml = W(); fml.u8(0); fml.u32(UInt32(files.count))
        for (n, _) in files { fml.fstr(n) }
        for _ in files { fml.fstr("") }
        fml.bytes(20 * files.count); fml.bytes(files.count)
        for _ in files { fml.u32(0) }
        for (_, parts) in files {
            fml.u32(UInt32(parts.count))
            for p in parts { fml.u32(28); fml.bytes(16); fml.u32(0); fml.u32(p) }
        }
        var fl = W(); fl.u32(UInt32(fml.d.count + 4)); fl.d.append(fml.d)
        var custom = W(); custom.u8(0); custom.u32(0)
        var cu = W(); cu.u32(UInt32(custom.d.count + 4)); cu.d.append(custom.d)
        return m.d + c.d + fl.d + cu.d
    }

    static func file(body: Data, compressed: Bool = true, magic: UInt32 = EpicBuildManifest.magic) throws -> Data {
        var stored = body
        if compressed {
            let deflate = try (body as NSData).compressed(using: .zlib) as Data
            stored = Data([0x78, 0x9C]) + deflate + Data([0, 0, 0, 0])
        }
        var h = W()
        h.u32(magic); h.u32(41); h.u32(UInt32(body.count)); h.u32(UInt32(stored.count))
        h.d.append(Data(Insecure.SHA1.hash(data: body)))
        h.u8(compressed ? 1 : 0); h.u32(18)
        return h.d + stored
    }

    // MARK: tests

    @Test func readsTheMetaAndTheSizes() throws {
        let m = try EpicBuildManifest.parse(try Self.file(body: Self.body()))
        #expect(m.appName == "app1")
        #expect(m.buildVersion == "1.2.3")
        #expect(m.launchExecutable == "Game.exe")
        #expect(m.launchCommand == "-arg")
        #expect(m.buildID == "BUILDID")
        #expect(m.prerequisiteIDs == ["prereq1"])
        #expect(m.fileCount == 2)
        #expect(m.installSize == 1030, "the chunk parts of every file, added up")
        #expect(m.executables == ["Game.exe"])
    }

    @Test func uncompressedBodiesAreReadToo() throws {
        let m = try EpicBuildManifest.parse(try Self.file(body: Self.body(), compressed: false))
        #expect(m.appName == "app1")
    }

    @Test func utf16StringsAreRead() throws {
        let m = try EpicBuildManifest.parse(try Self.file(body: Self.body(appName: "Ys IX – Monstrum", utf16: true)))
        #expect(m.appName == "Ys IX – Monstrum")
    }

    /// A surrogate pair or a combining accent has fewer grapheme clusters
    /// than code units; the terminator must go by the byte, or it stays.
    @Test func utf16StringsWithFewerGraphemesThanUnitsLoseTheirTerminator() throws {
        for name in ["Game\u{1F3AE}", "cafe\u{301}", "a\r\nb"] {
            let m = try EpicBuildManifest.parse(try Self.file(body: Self.body(appName: name, utf16: true)))
            #expect(m.appName == name, Comment(rawValue: name.debugDescription))
            #expect(!m.appName.unicodeScalars.contains("\u{0}"))
        }
    }

    @Test func theHashOfTheFileIsTheLaunchersManifestHash() throws {
        let raw = try Self.file(body: Self.body())
        let m = try EpicBuildManifest.parse(raw)
        let expected = Insecure.SHA1.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        #expect(m.fileHash == expected)
    }

    @Test func notAManifestIsRefused() throws {
        #expect(throws: EpicBuildManifest.Failure.notAManifest(0x11223344)) {
            try EpicBuildManifest.parse(try Self.file(body: Self.body(), magic: 0x11223344))
        }
        #expect(throws: EpicBuildManifest.Failure.tooShort) { try EpicBuildManifest.parse(Data([1, 2, 3])) }
    }

    @Test func aBodyThatDoesNotMatchItsHashIsRefused() throws {
        var raw = try Self.file(body: Self.body())
        raw[20] ^= 0xFF                                     // one byte of the stored SHA-1
        #expect(throws: EpicBuildManifest.Failure.hashMismatch) { try EpicBuildManifest.parse(raw) }
    }
}
