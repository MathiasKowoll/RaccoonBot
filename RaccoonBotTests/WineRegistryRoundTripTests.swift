//
//  WineRegistryRoundTripTests.swift
//  RaccoonBotTests
//
//  Rewriting a registry without editing it must not change it.
//
//  Every game launch loads the bottle's whole system.reg, sets two DWORDs in
//  the winebus section, and writes all 160,000 lines back. Whatever the parser
//  does not understand is destroyed on the way through -- silently, on every
//  launch, for the life of the bottle.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct WineRegistryRoundTripTests {

    private func file(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reg-\(UUID().uuidString).reg")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A value too long for one line is written with a trailing backslash and
    /// continued on the next. This is the ordinary shape of every REG_BINARY
    /// in the file -- 739 of them in the bottle games actually launch from.
    private static let multiLine = """
    WINE REGISTRY Version 2
    ;; All keys relative to \\\\Machine

    [Software\\\\Classes\\\\MediaFoundation\\\\Transforms\\\\62ce7e72] 1787673438
    #time=1dc0000000000000
    @="Microsoft H264 Video Decoder MFT"
    "InputTypes"=hex:76,69,64,73,00,00,10,00,80,00,00,aa,00,38,9b,71,48,32,36,34,\\
      00,00,10,00,80,00,00,aa,00,38,9b,71,76,69,64,73,00,00,10,00,80,00,00,aa,00,\\
      38,9b,71,f0,f4,40,3f,22,56,f8,4f,b6,d8,a1,7a,58,4b,ee,5e
    "OutputTypes"=hex:76,69,64,73,00,00,10,00,80,00,00,aa,00,38,9b,71,4e,56,31,32,\\
      00,00,10,00,80,00,00,aa,00,38,9b,71,76,69,64,73,00,00,10,00,80,00,00,aa,00,\\
      38,9b,71,59,56,31,32,00,00,10,00,80,00,00,aa,00,38,9b,71

    [System\\\\CurrentControlSet\\\\Services\\\\winebus] 1787673440
    #time=1dc0000000000001
    "DisableHidraw"=dword:00000000

    """

    /// The invariant, and the one that matters: load, change nothing, save --
    /// and the file is what it was.
    @Test func rewritingWithoutEditingChangesNothing() throws {
        let url = try file(Self.multiLine)
        defer { try? FileManager.default.removeItem(at: url) }

        let registry = WineRegistryFile(fileURL: url)
        try registry.load()
        try registry.save()

        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after == Self.multiLine, "a rewrite that edits nothing rewrote something")
    }

    /// What the launcher actually does, and the damage it did. Setting a DWORD
    /// in one section must not touch a binary value in another.
    @Test func settingOneDwordLeavesEveryOtherValueAlone() throws {
        let url = try file(Self.multiLine)
        defer { try? FileManager.default.removeItem(at: url) }

        let registry = WineRegistryFile(fileURL: url)
        try registry.load()
        let winebus = registry.section(forPath: "System\\\\CurrentControlSet\\\\Services\\\\winebus")
        #expect(winebus != nil, "the launcher looks this section up by this exact path")
        winebus?.addOrSetDword(forKey: "DisableHidraw", value: 1)
        try registry.save()

        let after = try String(contentsOf: url, encoding: .utf8)

        // The two binary values must come back whole, each still attached to
        // its own key. The corruption seen on a real bottle was InputTypes
        // emptied and OutputTypes carrying a format that belongs to the input
        // list -- the signature of continuation lines detached from their key.
        for key in ["InputTypes", "OutputTypes"] {
            guard let line = after.components(separatedBy: "\n").first(where: { $0.hasPrefix("\"\(key)\"") })
            else { #expect(Bool(false), "\(key) is gone entirely"); continue }
            #expect(line.hasSuffix("\\"), "\(key) lost its continuation marker")
        }
        // Every byte of both values still present, in order.
        let hexAfter = after.components(separatedBy: "\n")
            .drop(while: { !$0.hasPrefix("\"InputTypes\"") })
            .prefix(while: { !$0.hasPrefix("[System") })
            .joined()
        #expect(hexAfter.contains("48,32,36,34"), "H264 disappeared from the input list")
        #expect(hexAfter.contains("59,56,31,32"), "YV12 disappeared from the output list")

        // And the edit that was actually asked for did happen.
        #expect(after.contains("\"DisableHidraw\"=dword:00000001"))
    }

    /// A file with no continuation lines has always round-tripped. Kept so a
    /// fix for the multi-line case cannot break the simple one.
    @Test func theSimpleCaseStillRoundTrips() throws {
        let simple = """
        WINE REGISTRY Version 2

        [System\\\\CurrentControlSet\\\\Services\\\\winebus] 1787673440
        #time=1dc0000000000001
        "DisableHidraw"=dword:00000000
        "Enable SDL"=dword:00000001

        """
        let url = try file(simple)
        defer { try? FileManager.default.removeItem(at: url) }
        let registry = WineRegistryFile(fileURL: url)
        try registry.load()
        try registry.save()
        #expect(try String(contentsOf: url, encoding: .utf8) == simple)
    }
}

/// The same invariant against a real bottle's registry, which is where the
/// shapes a hand-written fixture forgets actually live: 160,000 lines, 739
/// values continued across lines, 400 sections.
///
/// Skipped when this machine has no bottle. A copy is round-tripped, never the
/// bottle itself.
struct WineRegistryRealFileTests {

    private func anyBottleRegistry() -> URL? {
        let f = FileManager.default
        let roots = [
            f.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/RaccoonBot/CXPBottles"),
            f.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver/Bottles"),
        ]
        for root in roots {
            for name in (try? f.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? [] {
                let reg = root.appendingPathComponent(name).appendingPathComponent("system.reg")
                if f.fileExists(atPath: reg.path(percentEncoded: false)) { return reg }
            }
        }
        return nil
    }

    @Test func arealRegistrySurvivesBeingRewritten() throws {
        let f = FileManager.default
        guard let source = anyBottleRegistry() else { return }
        let original = try String(contentsOf: source, encoding: .utf8)

        let copy = f.temporaryDirectory.appendingPathComponent("real-\(UUID().uuidString).reg")
        try original.write(to: copy, atomically: true, encoding: .utf8)
        defer {
            try? f.removeItem(at: copy)
            try? f.removeItem(at: copy.appendingPathExtension("bak"))
        }

        let registry = WineRegistryFile(fileURL: copy)
        try registry.load()
        try registry.save()

        let after = try String(contentsOf: copy, encoding: .utf8)
        if after != original {
            // Report the first divergence rather than a wall of diff: on a
            // 160,000-line file the line number is the whole diagnosis.
            let a = original.components(separatedBy: "\n"), b = after.components(separatedBy: "\n")
            let at = zip(a, b).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            #expect(Bool(false),
                    "the rewrite changed the file at line \(at.map(String.init) ?? "?") — \(a.count) lines in, \(b.count) out")
        } else {
            #expect(after == original)
        }
    }
}

/// Not writing at all is the safest kind of write.
struct WineRegistryNoOpTests {

    @Test func settingAValueToWhatItAlreadyIsReportsNoChange() throws {
        let contents = """
        WINE REGISTRY Version 2

        [System\\\\CurrentControlSet\\\\Services\\\\winebus] 1787673440
        "DisableHidraw"=dword:00000000
        "Enable SDL"=dword:00000001

        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("noop-\(UUID().uuidString).reg")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let registry = WineRegistryFile(fileURL: url)
        try registry.load()
        let section = registry.section(forPath: "System\\\\CurrentControlSet\\\\Services\\\\winebus")!
        #expect(section.addOrSetDword(forKey: "DisableHidraw", value: 0) == false)
        #expect(section.addOrSetDword(forKey: "Enable SDL", value: 1) == false)
        // And a real change still says so.
        #expect(section.addOrSetDword(forKey: "DisableHidraw", value: 1) == true)
        // A key that was not there is a change too.
        #expect(section.addOrSetDword(forKey: "Something New", value: 1) == true)
    }
}
