//
//  ToolkitRestoreTests.swift
//  RaccoonBotTests
//
//  The behaviour nobody had exercised: installd3dMetal against a .orig set
//  laid down by MacGameVideoFix's make-engine-copy.sh from true stock.
//
//  Two applications agreed a contract about those backups and neither had run
//  anything against it. The failure it guards destroys state while looking
//  fine: six of the backups are symlinks into external, and a restore that
//  puts back a resolved 95,952-byte copy instead of a 33-byte link leaves
//  libd3dshared present twice with nothing joining them.
//

import Foundation
import Testing
@testable import RaccoonBot

struct ToolkitRestoreTests {

    /// An engine MGVF made with the new script, carrying backups from stock.
    private var reference: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications/Crossover_MGVF_nuevo.app")
    }

    private var toolkits: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RaccoonBot/Libs")
    }

    private let gptkPath = "Contents/SharedSupport/CrossOver/lib64/apple_gptk"

    /// A copy, never the original. `ditto` because half the set is symlinks and
    /// a plain copy resolves them -- the very thing under test.
    private func engineCopy() throws -> URL {
        let f = FileManager.default
        let dest = f.temporaryDirectory.appendingPathComponent("Eng-\(UUID().uuidString).app")
        let lib = "Contents/SharedSupport/CrossOver/lib64"
        try f.createDirectory(at: dest.appendingPathComponent(lib), withIntermediateDirectories: true)
        try f.copyItem(at: reference.appendingPathComponent("Contents/Info.plist"),
                       to: dest.appendingPathComponent("Contents/Info.plist"))
        for item in ["apple_gptk", "libMoltenVK.dylib", "libMoltenVK.dylib.orig"] {
            let from = reference.appendingPathComponent("\(lib)/\(item)")
            guard f.fileExists(atPath: from.path(percentEncoded: false)) else { continue }
            let copy = Process()
            copy.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            copy.arguments = [from.path(percentEncoded: false),
                              dest.appendingPathComponent("\(lib)/\(item)").path(percentEncoded: false)]
            try copy.run(); copy.waitUntilExit()
        }
        return dest
    }

    /// Walked explicitly. The enumerator has already misled this codebase once
    /// today on this very tree, and a test that under-counts silently is worse
    /// than no test.
    private func origs(in engine: URL) -> [String] {
        let f = FileManager.default
        var found: [String] = []
        func walk(_ dir: URL) {
            for name in (try? f.contentsOfDirectory(atPath: dir.path(percentEncoded: false)))?.sorted() ?? [] {
                let item = dir.appendingPathComponent(name)
                if name.hasSuffix(".orig") { found.append(name); continue }
                var isDir: ObjCBool = false
                if f.fileExists(atPath: item.path(percentEncoded: false), isDirectory: &isDir), isDir.boolValue {
                    walk(item)
                }
            }
        }
        walk(engine.appendingPathComponent(gptkPath))
        return found
    }

    @Test func aBackupSetLaidFromStockSurvivesAToolkitInstall() throws {
        let f = FileManager.default
        try #require(f.fileExists(atPath: reference.path(percentEncoded: false)),
                     "no engine with backups at \(reference.path(percentEncoded: false))")

        let engine = try engineCopy()
        defer { try? f.removeItem(at: engine) }
        let unixDir = engine.appendingPathComponent("\(gptkPath)/wine/x86_64-unix")

        let before = origs(in: engine)
        try #require(before.count == 13, "expected 13 backups, found \(before.count)")
        let links = before.filter { $0.hasSuffix(".so.orig") }
        try #require(links.count == 6)

        try installd3dMetal(at: engine, version: "4", resources: toolkits)

        // 1. everything this generation wrote has a backup behind it.
        //
        // Not the same COUNT as before: generation 3's atidxx64 is restored and
        // then left alone, so it keeps no backup -- right, because a stock file
        // nobody replaced needs none.
        let after = Set(origs(in: engine))
        let stockNames = Set(before.map { String($0.dropLast(".orig".count)) })
        for path in d3dMetalResources(version: "4", resources: toolkits) where path != "external" {
            let name = URL(fileURLWithPath:
                path.replacingOccurrences(of: "nvngx-on-metalfx", with: "nvngx")).lastPathComponent
            // Only where something was displaced. A file this generation
            // introduces -- d3d10, which CrossOver does not ship -- replaced
            // nothing, so there is nothing to keep. It is removed instead when
            // the other generation comes in, which is assertion 2.
            guard stockNames.contains(name) else { continue }
            #expect(after.contains(name + ".orig"), "\(name) displaced a stock file and kept no backup")
        }
        #expect(after.contains("external.orig"))

        // 2. nothing of the other generation is left, and nothing of stock is
        //    taken. Before this was handled, installing 4 over stock left
        //    d3d10 with no backup and a later restore could not remove it --
        //    an engine reporting as 3 with a file of 4 inside it.
        let live = Set((try? f.contentsOfDirectory(atPath: unixDir.path(percentEncoded: false))) ?? [])
        #expect(live.contains("atidxx64.so"), "stock's own file was taken away")
        #expect(live.contains("d3d10.so"), "generation 4 ships d3d10 and it should be there")
        // atidxx64 is CrossOver's and generation 4 does not replace it, so it
        // stays and keeps no backup. An earlier attempt to remove "the other
        // generation's leftovers" deleted it, because after a restore a stock
        // file and one of ours look identical -- neither has a .orig.

        // 3. THE ANSWER THAT MATTERS: a link comes back a link, not a resolved
        //    copy of the library it points at.
        // The backups that exist NOW, not the ones that existed before:
        // atidxx64 was restored and left alone, so its backup is legitimately
        // gone and asking about it would be asking the wrong question.
        let linksNow = after.filter { $0.hasSuffix(".so.orig") }
        #expect(linksNow.count == 5, "expected five unix backups after, found \(linksNow.count)")
        for name in linksNow {
            let path = unixDir.appendingPathComponent(name).path(percentEncoded: false)
            let target = try? f.destinationOfSymbolicLink(atPath: path)
            #expect(target != nil, "\(name) came back as a file, not a link")
            #expect(target?.contains("libd3dshared") == true)
            let size = ((try? f.attributesOfItem(atPath: path))?[.size] as? Int) ?? 0
            #expect(size < 1000, "\(name) is \(size) bytes -- a resolved copy, not a link")
        }

        // 4. and the generation asked for is the one installed.
        let shared = engine.appendingPathComponent("\(gptkPath)/external/libd3dshared.dylib")
        let size = ((try? f.attributesOfItem(atPath: shared.path(percentEncoded: false)))?[.size] as? Int) ?? 0
        #expect(size == 241888, "generation 4 is 241,888 bytes; found \(size)")
    }
}
