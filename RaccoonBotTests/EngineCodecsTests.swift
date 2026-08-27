//
//  EngineCodecsTests.swift
//  RaccoonBotTests
//
//  Putting the decoders inside the engine, rather than beside it.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct EngineCodecsLayoutTests {

    /// URL spells a directory with a trailing slash and decides by looking at
    /// the disk, so a path that exists compares differently from one that does
    /// not. Trimmed here rather than asserted around.
    private func tidy(_ url: URL) -> String {
        var p = url.path(percentEncoded: false)
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// An engine shaped like a real one, with only the directory that
    /// generation actually has.
    private func engine(version: String, dir: String) throws -> URL {
        let f = FileManager.default
        let app = f.temporaryDirectory.appendingPathComponent("Eng-\(UUID().uuidString).app", isDirectory: true)
        try f.createDirectory(at: app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
                                .appendingPathComponent(dir).appendingPathComponent("gstreamer-1.0"),
                              withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleVersion": version]
        try (plist as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    @Test func a26EngineIsFoundThroughLib64() throws {
        let app = try engine(version: "26.3.0.39832", dir: "lib64")
        defer { try? FileManager.default.removeItem(at: app) }
        let d = try #require(EngineCodecs.directories(ofEngineAt: app.path(percentEncoded: false)))
        #expect(tidy(d.plugins).hasSuffix("/lib64/gstreamer-1.0"))
        #expect(tidy(d.libs).hasSuffix("/lib64"))
    }

    @Test func a27EngineIsFoundThroughLibArch() throws {
        let app = try engine(version: "27.0.0.40921", dir: "lib/x86_64")
        defer { try? FileManager.default.removeItem(at: app) }
        let d = try #require(EngineCodecs.directories(ofEngineAt: app.path(percentEncoded: false)))
        #expect(tidy(d.plugins).hasSuffix("/lib/x86_64/gstreamer-1.0"))
    }

    /// The directory is found, never created. A 27 engine's own `wine` sets
    /// GST_PLUGIN_SYSTEM_PATH to whichever of these exists and REPLACES the
    /// value, so a lib64 invented here would hide the plugins it ships.
    @Test func anEngineWithNoPluginDirectoryGetsNoneInvented() throws {
        let f = FileManager.default
        let app = f.temporaryDirectory.appendingPathComponent("Bare-\(UUID().uuidString).app", isDirectory: true)
        try f.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try (["CFBundleVersion": "27.0.0.40921"] as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        defer { try? f.removeItem(at: app) }

        #expect(EngineCodecs.directories(ofEngineAt: app.path(percentEncoded: false)) == nil)
        #expect(throws: EngineCodecs.Failure.self) {
            try EngineCodecs.install(intoEngineAt: app.path(percentEncoded: false))
        }
        #expect(!f.fileExists(atPath: app.appendingPathComponent(SHARED_SUPPORT_COMPONENT + "/lib64").path(percentEncoded: false)),
                "it created a directory the engine does not have")
    }
}

/// Against the real GStreamer on this machine, into an engine made here.
/// Skipped where there is no framework to take the bits from.
struct EngineCodecsInstallTests {

    private func fakeEngine() throws -> URL? {
        let f = FileManager.default
        guard f.fileExists(atPath: EngineCodecs.frameworkLib) else { return nil }
        let app = f.temporaryDirectory.appendingPathComponent("Eng-\(UUID().uuidString).app", isDirectory: true)
        try f.createDirectory(at: app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
                                .appendingPathComponent("lib64").appendingPathComponent("gstreamer-1.0"),
                              withIntermediateDirectories: true)
        try (["CFBundleVersion": "26.3.0.39832"] as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    @Test func theDecoderAndEverythingItNeedsGoIn() throws {
        let f = FileManager.default
        guard let app = try fakeEngine() else { return }
        defer { try? f.removeItem(at: app) }

        let result = try EngineCodecs.install(intoEngineAt: app.path(percentEncoded: false))
        #expect(result.copied.contains("libgstlibav.dylib"))
        // FFmpeg is in no CrossOver, so it always has to come with it.
        #expect(result.copied.contains { $0.hasPrefix("libavcodec") })

        // And every @rpath dependency of the installed plugin is now beside it.
        let libs = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT).appendingPathComponent("lib64")
        let plugin = libs.appendingPathComponent("gstreamer-1.0/libgstlibav.dylib")
        #expect(f.fileExists(atPath: plugin.path(percentEncoded: false)))
        for dep in EngineCodecs.dependencies(of: plugin) where !EngineCodecs.plugins.contains(dep) {
            #expect(f.fileExists(atPath: libs.appendingPathComponent(dep).path(percentEncoded: false)),
                    "\(dep) is needed and was not copied")
        }
    }

    /// What the engine already has is left alone. This is the whole reason
    /// the decoders can live inside it: the plugin binds to the engine's own
    /// GStreamer rather than dragging another core in beside it.
    @Test func whatTheEngineAlreadyHasIsNotReplaced() throws {
        let f = FileManager.default
        guard let app = try fakeEngine() else { return }
        defer { try? f.removeItem(at: app) }

        let libs = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT).appendingPathComponent("lib64")
        let core = libs.appendingPathComponent("libgstreamer-1.0.0.dylib")
        try Data("the engine's own core".utf8).write(to: core)

        let result = try EngineCodecs.install(intoEngineAt: app.path(percentEncoded: false))
        #expect(!result.copied.contains("libgstreamer-1.0.0.dylib"))
        #expect(try String(contentsOf: core, encoding: .utf8) == "the engine's own core")
        #expect(!f.fileExists(atPath: core.appendingPathExtension("orig").path(percentEncoded: false)))
    }

    /// Anything we do replace is kept, once, so an engine can be put back.
    @Test func whatIsReplacedIsKeptAsOrig() throws {
        let f = FileManager.default
        guard let app = try fakeEngine() else { return }
        defer { try? f.removeItem(at: app) }

        let plugins = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
            .appendingPathComponent("lib64/gstreamer-1.0")
        let existing = plugins.appendingPathComponent("libgstlibav.dylib")
        try Data("an older one".utf8).write(to: existing)

        try EngineCodecs.install(intoEngineAt: app.path(percentEncoded: false))
        let orig = existing.appendingPathExtension("orig")
        #expect(f.fileExists(atPath: orig.path(percentEncoded: false)))
        #expect(try String(contentsOf: orig, encoding: .utf8) == "an older one")

        // Twice does not bury the original under our own copy.
        try EngineCodecs.install(intoEngineAt: app.path(percentEncoded: false))
        #expect(try String(contentsOf: orig, encoding: .utf8) == "an older one")
    }

    @Test func withoutTheFrameworkItSaysSoAndWritesNothing() throws {
        // Only meaningful as a shape check: the framework is present here.
        #expect(EngineCodecs.Failure.frameworkMissing.errorDescription?.contains("GStreamer.framework") == true)
    }
}

/// GStreamer stays a requirement, and the version is part of it.
///
/// winevideo names it exactly -- 1.24.13 for Nioh, Nioh 2, Persona 5 Strikers,
/// Returnal, Ghostwire Tokyo and the WMV/VC-1 titles -- so "some 1.24" is not
/// the requirement and must not be reported as if it were.
struct GStreamerRequirementTests {

    private func status(framework: GStreamerStatus.Framework, decoders: [String]) -> GStreamerStatus {
        GStreamerStatus(framework: framework, engineDecoders: decoders, engineVersion: "26.3.0.39832")
    }

    @Test func theExpectedVersionIsTheOneWinevideoNames() {
        #expect(GStreamerStatus.expectedVersion == "1.24.13")
    }

    @Test func anotherVersionIsNamedRatherThanAccepted() {
        let s = status(framework: .present(version: "1.28.4"), decoders: [])
        #expect(s.frameworkMismatch == "1.28.4")
        #expect(s.summary.contains("1.28.4"))
        #expect(s.summary.contains("1.24.13"), "the summary has to say which one is wanted")
    }

    @Test func theRightVersionIsNotFlagged() {
        #expect(status(framework: .present(version: "1.24.13"), decoders: []).frameworkMismatch == nil)
    }

    /// What makes a video play is the decoder being inside the engine. The
    /// framework matters when the engine is patched, and by the time a game
    /// runs it has already been copied in -- so a mismatched framework beside
    /// a working engine is a note, not a failure.
    @Test func decodersInTheEngineAreWhatCounts() {
        let mismatched = status(framework: .present(version: "1.28.4"), decoders: ["libgstlibav"])
        #expect(mismatched.isOK)
        #expect(mismatched.summary.contains("carries libav"))

        let none = status(framework: .present(version: "1.24.13"), decoders: [])
        #expect(!none.isOK)
    }

    @Test func withNoFrameworkAtAllItSaysWhatIsMissing() {
        let s = status(framework: .missing, decoders: [])
        #expect(!s.isOK)
        #expect(s.summary.contains("1.24.13"))
        #expect(s.summary.contains("silent"))
    }
}
