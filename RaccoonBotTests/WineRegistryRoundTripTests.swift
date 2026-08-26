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

/// The guarantee, rather than a fix for one known bug.
///
/// A bottle registry has one copy, and what it holds -- what can decode a
/// video, what a game installed -- cannot be reconstructed from anywhere else.
/// So the rule is: if this build cannot reproduce what it read, it has no
/// business writing it back.
struct WineRegistryFidelityTests {

    private func file(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fid-\(UUID().uuidString).reg")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Every value shape found across every .reg on a real machine: plain
    /// strings, dword, hex, hex(N) for several N, str(2), str(7), and the
    /// empty hex(0). If the parser cannot rebuild this, it says so.
    private static let everyShape = """
    WINE REGISTRY Version 2
    ;; All keys relative to \\\\Machine

    [Software\\\\Test] 1787673438
    #time=1dc0000000000000
    @="a default value"
    "plain"="just a string"
    "number"=dword:0000002a
    "binary"=hex:01,02,03
    "long"=hex:76,69,64,73,00,00,10,00,80,00,00,aa,00,38,9b,71,48,32,36,34,\\
      00,00,10,00,80,00,00,aa,00,38,9b,71
    "empty"=hex(0):
    "expand"=str(2):"C:\\\\Program Files\\\\Thing"
    "multi"=str(7):":\\0"
    "link"=hex(6):5c,00,52,00,65,00
    "odd"=hex(ffff0012):44,00,75,00
    "qword"=hex(b):00,00,00,00,0c,00,00,00

    """

    /// #link marks a registry key as a symbolic link. Read as a comment it
    /// was moved below the values, where it means nothing -- and the bottle
    /// games launch from has none left, while the one beside it has 54.
    @Test func aSectionMarkerStaysWhereItWasWritten() throws {
        let withLink = """
        WINE REGISTRY Version 2

        [System\\\\CurrentControlSet\\\\Control\\\\Class] 1787673438
        #time=1dc0000000000000
        #link
        "SymbolicLinkValue"=hex(6):5c,00,52,00,65,00
        "other"="x"

        """
        let url = try file(withLink)
        defer { try? FileManager.default.removeItem(at: url) }
        let registry = WineRegistryFile(fileURL: url)
        try registry.load()
        #expect(registry.isFaithful, "\(registry.infidelity ?? "")")
        try registry.save()
        #expect(try String(contentsOf: url, encoding: .utf8) == withLink,
                "the marker moved, and below the values it marks nothing")
        try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
    }

    @Test func everyShapeOnARealMachineRebuildsExactly() throws {
        let url = try file(Self.everyShape)
        defer { try? FileManager.default.removeItem(at: url) }
        let registry = WineRegistryFile(fileURL: url)
        try registry.load()
        #expect(registry.isFaithful, "no reproduce lo que leyó: \(registry.infidelity ?? "")")
        try registry.save()
        #expect(try String(contentsOf: url, encoding: .utf8) == Self.everyShape)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
    }

    /// The point of the guard: a shape nobody anticipated is refused rather
    /// than mangled. Here a value is deliberately written in a form the parser
    /// puts in the wrong place -- and the file is left alone.
    @Test func aShapeItCannotRebuildIsRefusedRatherThanWritten() throws {
        // A continuation line that begins a section, which the reader will
        // treat as a section header and the writer will therefore move.
        let awkward = """
        WINE REGISTRY Version 2

        [Software\\\\Test] 1787673438
        "value"=hex:01,02,\\
        [not really a section]
        "after"="x"

        """
        let url = try file(awkward)
        defer { try? FileManager.default.removeItem(at: url) }
        let before = try String(contentsOf: url, encoding: .utf8)

        let registry = WineRegistryFile(fileURL: url)
        try registry.load()
        if registry.isFaithful {
            // If it CAN rebuild this, writing it must be lossless.
            try registry.save()
            #expect(try String(contentsOf: url, encoding: .utf8) == before)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
        } else {
            // And if it cannot, it must refuse and change nothing.
            #expect(throws: WineRegistryError.self) { try registry.save() }
            #expect(try String(contentsOf: url, encoding: .utf8) == before,
                    "it refused and wrote anyway")
        }
    }

    /// A file this build has never seen the inside of cannot be written.
    @Test func savingWithoutLoadingIsRefused() throws {
        let url = try file("WINE REGISTRY Version 2\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let registry = WineRegistryFile(fileURL: url)
        #expect(throws: WineRegistryError.self) { try registry.save() }
    }

    /// Faithful is not enough: save() has to actually go through. A guard that
    /// refuses a file it could have written correctly is a feature that stops
    /// working -- the controller settings would silently never be applied.
    @Test func everyRealBottleRegistryCanActuallyBeSaved() throws {
        let f = FileManager.default
        let roots = [
            f.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/RaccoonBot/CXPBottles"),
            f.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver/Bottles"),
        ]
        for root in roots {
            for name in (try? f.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? [] {
                let reg = root.appendingPathComponent(name).appendingPathComponent("system.reg")
                guard f.fileExists(atPath: reg.path(percentEncoded: false)) else { continue }
                let copy = f.temporaryDirectory.appendingPathComponent("s-\(UUID().uuidString).reg")
                try Data(contentsOf: reg).write(to: copy)
                defer {
                    try? f.removeItem(at: copy)
                    try? f.removeItem(at: copy.appendingPathExtension("bak"))
                }
                let original = try String(contentsOf: copy, encoding: .utf8)
                let registry = WineRegistryFile(fileURL: copy)
                try registry.load()
                #expect(throws: Never.self, "\(name) was refused") { try registry.save() }
                #expect(try String(contentsOf: copy, encoding: .utf8) == original, "\(name) changed")
            }
        }
    }

    /// The real thing: a bottle registry must be declared faithful, or the
    /// launcher will refuse to apply controller settings on this machine.
    @Test func realBottleRegistriesAreWritable() throws {
        let f = FileManager.default
        let roots = [
            f.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/RaccoonBot/CXPBottles"),
            f.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver/Bottles"),
        ]
        var checked = 0
        for root in roots {
            for name in (try? f.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? [] {
                let reg = root.appendingPathComponent(name).appendingPathComponent("system.reg")
                guard f.fileExists(atPath: reg.path(percentEncoded: false)) else { continue }
                let copy = f.temporaryDirectory.appendingPathComponent("b-\(UUID().uuidString).reg")
                try Data(contentsOf: reg).write(to: copy)
                defer { try? f.removeItem(at: copy) }
                let registry = WineRegistryFile(fileURL: copy)
                try registry.load()
                #expect(registry.isFaithful, "\(name): \(registry.infidelity ?? "")")
                checked += 1
            }
        }
        if checked > 0 { #expect(checked > 0) }
    }
}

/// Key names that contain the character the parser used to split on.
///
/// Wine's MSI writes SxS assembly identities as registry key names, and they
/// carry an unescaped "=" inside the quoted name. There are 120 of them across
/// the bottles on this machine. Split at the first "=", the amd64 and x86 rows
/// of the same assembly become the same name.
struct WineRegistryKeyNameTests {

    private func loaded(_ contents: String) throws -> (WineRegistryFile, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("key-\(UUID().uuidString).reg")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        let r = WineRegistryFile(fileURL: url)
        try r.load()
        return (r, url)
    }

    private static let sxs = """
    WINE REGISTRY Version 2

    [Software\\\\Classes\\\\Installer\\\\Win32Assemblies\\\\Global] 1787620920
    #time=1dd343020bd782a
    "Microsoft.VC90.ATL,version=\\"9.0.30729.6161\\",processorArchitecture=\\"amd64\\",type=\\"win32\\""=str(7):"a\\0"
    "Microsoft.VC90.ATL,version=\\"9.0.30729.6161\\",processorArchitecture=\\"x86\\",type=\\"win32\\""=str(7):"b\\0"

    """

    @Test func twoAssembliesAreTwoKeysNotOne() throws {
        let (registry, url) = try loaded(Self.sxs)
        defer { try? FileManager.default.removeItem(at: url) }
        let section = registry.sections.first { $0.header.contains("Win32Assemblies") }
        #expect(section?.values.count == 2)
        let names = Set(section?.values.map(\.key) ?? [])
        #expect(names.count == 2, "amd64 and x86 collapsed onto one name")
        #expect(names.contains { $0.contains("amd64") })
        #expect(names.contains { $0.contains("x86") })
    }

    /// The consequence that mattered: the guard read a loss that had not
    /// happened and refused to write the file at all.
    @Test func suchAFileCanStillBeSaved() throws {
        let (registry, url) = try loaded(Self.sxs)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
        }
        #expect(registry.isFaithful)
        #expect(throws: Never.self) { try registry.save() }
        #expect(try String(contentsOf: url, encoding: .utf8) == Self.sxs)
    }

    @Test func anOrdinaryNameStillReads() throws {
        let (registry, url) = try loaded("""
        WINE REGISTRY Version 2

        [Software\\\\Test] 1
        "plain"="x"
        "with spaces"="y"

        """)
        defer { try? FileManager.default.removeItem(at: url) }
        let keys = registry.sections.first?.values.map(\.key) ?? []
        #expect(keys == ["plain", "with spaces"])
    }
}
