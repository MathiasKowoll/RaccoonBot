//
//  CodecStagingTests.swift
//  RaccoonBotTests
//
//  The closure is the part that can be wrong quietly: stage one library too
//  few and a cutscene is silent with nothing in any log to say why. So it is
//  tested against a graph written here rather than against whatever happens to
//  be installed on the machine running the tests.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct CodecStagingTests {

    /// A miniature of the real thing: the plugin needs FFmpeg, which the engine
    /// does not have, and GStreamer's core, which it does. The two carry
    /// different versions of the same dependency -- libffi 7 in the framework,
    /// 8 in the engine -- which is exactly where a naive walk goes wrong.
    private static let framework: [String: [String]] = [
        "plugin.dylib":       ["libavcodec.dylib", "libgstreamer.dylib", "libgobject.dylib"],
        "libavcodec.dylib":   ["libavutil.dylib", "libz.dylib"],
        "libavutil.dylib":    [],
        "libz.dylib":         [],
        "libgstreamer.dylib": ["libglib.dylib", "liborc.dylib"],
        "libgobject.dylib":   ["libffi.7.dylib", "libglib.dylib"],
        "libglib.dylib":      ["libpcre.dylib"],
        "libpcre.dylib":      [],
        "libffi.7.dylib":     [],
        "liborc.dylib":       [],
    ]
    private static let engine: [String: [String]] = [
        "libgstreamer.dylib": ["libglib.dylib"],          // no orc in this build
        "libgobject.dylib":   ["libffi.8.dylib", "libglib.dylib"],
        "libglib.dylib":      ["libpcre.dylib"],
        "libpcre.dylib":      [],
        "libffi.8.dylib":     [],
    ]

    /// Paths are "engine/<name>" or "framework/<name>" so the test can tell
    /// which copy a walk actually read.
    private func placements() -> [String: CodecStaging.Placement] {
        CodecStaging.closure(
            from: ["framework/plugin.dylib"],
            dependencies: { path in
                let name = String(path.split(separator: "/").last!)
                return path.hasPrefix("engine/")
                    ? (Self.engine[name] ?? [])
                    : (Self.framework[name] ?? [])
            },
            resolve: { name in
                if Self.engine[name] != nil { return ("engine/\(name)", .link) }
                if Self.framework[name] != nil { return ("framework/\(name)", .copy) }
                return nil
            })
    }

    @Test func stagesWhatTheEngineLacksAndLinksWhatItHas() {
        let p = placements()
        #expect(p["libavcodec.dylib"] == .copy)
        #expect(p["libavutil.dylib"] == .copy)
        #expect(p["libz.dylib"] == .copy)
        #expect(p["libgstreamer.dylib"] == .link)
        #expect(p["libgobject.dylib"] == .link)
        #expect(p["libglib.dylib"] == .link)
    }

    /// The bug the resolution-aware walk exists to avoid. Reading the
    /// framework's libgobject all the way down asks for libffi 7; the engine's
    /// libgobject is the one that will be loaded and it asks for 8.
    @Test func followsTheCopyThatWillActuallyBeLoaded() {
        let p = placements()
        #expect(p["libffi.8.dylib"] == .link)
        #expect(p["libffi.7.dylib"] == nil, "libffi.7 belongs to the framework's libgobject, which is never loaded")
        #expect(p["liborc.dylib"] == nil, "orc is a dependency of the framework's core, not the engine's")
    }

    @Test func doesNotStageThePluginsIntoLib() {
        // They go in gstreamer-1.0, and a plugin that also appeared in lib
        // would be opened twice.
        #expect(placements()["plugin.dylib"] == nil)
    }

    @Test func aCycleDoesNotHang() {
        let p = CodecStaging.closure(
            from: ["a"],
            dependencies: { ["a": ["b"], "b": ["c"], "c": ["a", "b"]][$0] ?? [] },
            resolve: { ($0, .copy) })
        #expect(p.keys.sorted() == ["b", "c"])
    }

    @Test func somethingNeitherSideHasIsSkippedRatherThanFatal() {
        let p = CodecStaging.closure(
            from: ["root"],
            dependencies: { $0 == "root" ? ["present", "absent"] : [] },
            resolve: { $0 == "present" ? ("present", .copy) : nil })
        #expect(p == ["present": .copy])
    }

    // MARK: - Naming

    @Test func theDirectoryIsNamedAfterTheBundleNotTheVersion() {
        // A patched copy declares the version of the CrossOver it came from,
        // so two engines that must not share a staging would share one.
        #expect(CodecStaging.slug(forEngineAt: "/Applications/CrossOver.app") == "CrossOver")
        #expect(CodecStaging.slug(forEngineAt: "/x/Crossover_patched.app") == "Crossover_patched")
        #expect(CodecStaging.slug(forEngineAt: "/x/CrossOver-winevideo-0.5.app") == "CrossOver-winevideo-0.5")
    }

    @Test func aNameWithSeparatorsInItCannotEscapeTheDirectory() {
        let slug = CodecStaging.slug(forEngineAt: "/x/Cross Over (beta)/../evil.app")
        #expect(!slug.contains("/"))
        #expect(!slug.contains(".."))
    }

    @Test func theStagedPathIsTheOneCrossoverSwiftLooksFor() {
        // stagedCodecPath builds this path independently; if the two ever
        // disagree the staging is built somewhere nothing reads.
        let engine = "/Applications/CrossOver.app"
        let mine = CodecStaging.directory(engineAppPath: engine, arch: "x86_64")
            .appendingPathComponent("gstreamer-1.0").path(percentEncoded: false)
        let f = FileManager.default
        let complete = CodecStaging.directory(engineAppPath: engine, arch: "x86_64")
            .appendingPathComponent(".complete")
        guard f.fileExists(atPath: complete.path(percentEncoded: false)) else { return }
        #expect(stagedCodecPath(cxAppPath: engine, arch: "x86_64") == mine)
    }
}

/// The real thing, built somewhere disposable.
///
/// Skipped rather than failed when this machine has no GStreamer or no
/// CrossOver: the closure tests above cover the logic, and this one covers the
/// part only a real engine and a real framework can answer -- whether what
/// comes out is something dyld could actually load.
struct CodecStagingIntegrationTests {

    private func engine() -> String? {
        let f = FileManager.default
        let candidates = [
            f.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Crossover_patched.app").path(percentEncoded: false),
            "/Applications/CrossOver.app",
        ]
        return candidates.first { f.fileExists(atPath: $0) && !CodecStaging.architectures(ofEngineAt: $0).isEmpty }
    }

    @Test func buildsSomethingLoadable() throws {
        let f = FileManager.default
        guard f.fileExists(atPath: CodecStaging.frameworkLib), let app = engine() else { return }
        guard let arch = CodecStaging.architectures(ofEngineAt: app).first else { return }

        let base = f.temporaryDirectory.appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
        defer { try? f.removeItem(at: base) }

        let result = try CodecStaging.stage(engineAppPath: app, arch: arch, into: base)
        let dir = CodecStaging.directory(engineAppPath: app, arch: arch, into: base)

        #expect(!result.copied.isEmpty, "FFmpeg is not in any CrossOver, so something must be copied")
        #expect(!result.linked.isEmpty, "the GStreamer core is in every CrossOver, so something must be linked")

        // .complete is the whole answer to "is it ready", so it has to be there
        // and it has to be last.
        #expect(f.fileExists(atPath: dir.appendingPathComponent(".complete").path(percentEncoded: false)))
        #expect(f.fileExists(atPath: dir.appendingPathComponent(".built-against").path(percentEncoded: false)))

        for plugin in CodecStaging.plugins {
            #expect(f.fileExists(atPath: dir.appendingPathComponent("gstreamer-1.0/\(plugin)").path(percentEncoded: false)),
                    "\(plugin) is the reason the directory exists")
        }

        // A symlink to a library that is not there is worse than no symlink:
        // it reads as staged and fails at load.
        for name in result.linked {
            let link = dir.appendingPathComponent("lib/\(name)")
            #expect(f.fileExists(atPath: link.path(percentEncoded: false)),
                    "\(name) links to somewhere that does not exist")
        }

        // The real question: after staging, is every @rpath dependency of the
        // plugins present in lib? A single missing one is a plugin dyld
        // refuses to load, and the only symptom is a silent cutscene.
        let staged = Set(result.copied + result.linked)
        for plugin in CodecStaging.plugins {
            let path = dir.appendingPathComponent("gstreamer-1.0/\(plugin)").path(percentEncoded: false)
            for dep in CodecStaging.dependencies(of: path) where !CodecStaging.plugins.contains(dep) {
                #expect(staged.contains(dep), "\(plugin) needs \(dep) and nothing staged it")
            }
        }
    }

    @Test func restagingOverAFinishedOneLeavesItFinished() throws {
        let f = FileManager.default
        guard f.fileExists(atPath: CodecStaging.frameworkLib), let app = engine() else { return }
        guard let arch = CodecStaging.architectures(ofEngineAt: app).first else { return }

        let base = f.temporaryDirectory.appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
        defer { try? f.removeItem(at: base) }

        let first = try CodecStaging.stage(engineAppPath: app, arch: arch, into: base)
        let second = try CodecStaging.stage(engineAppPath: app, arch: arch, into: base)
        // Copying onto an existing symlink throws, which is why the directory
        // is wiped rather than written over.
        #expect(first == second)
    }
}
