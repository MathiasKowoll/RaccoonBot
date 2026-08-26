//
//  BottleEnvTests.swift
//  RaccoonBotTests
//
//  Writing one key into a bottle's configuration without disturbing the rest
//  of it, and without leaving the file in a state the next writer corrupts.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct BottleEnvTests {

    private func bottle(_ conf: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bottle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try conf.write(to: dir.appendingPathComponent("cxbottle.conf"),
                       atomically: true, encoding: .utf8)
        return dir
    }

    private func read(_ dir: URL) throws -> String {
        try String(contentsOf: dir.appendingPathComponent("cxbottle.conf"), encoding: .utf8)
    }

    /// The case that bit a real bottle on this machine.
    ///
    /// [EnvironmentVariables] is the last section in a stock cxbottle.conf, and
    /// a key that is not already there gets appended after the file's own
    /// trailing newline -- so the file ends without one. CrossOver writes into
    /// this file too, when a game starts. The next line it appends would land
    /// on the end of ours, and the parser would read one fused key that nobody
    /// set.
    @Test func appendingToTheLastSectionLeavesATrailingNewline() throws {
        let dir = try bottle("""
        [Bottle]
        "Template" = "win10_64"

        [EnvironmentVariables]
        "WINEMSYNC" = "1"

        """)
        setBottleEnv(dir, key: "GST_PLUGIN_PATH", value: "/some/where")
        let out = try read(dir)
        #expect(out.hasSuffix("\n"), "the next writer appends onto our last line")
        #expect(out.contains("\"GST_PLUGIN_PATH\" = \"/some/where\""))
        #expect(out.contains("\"WINEMSYNC\" = \"1\""), "other keys are not ours to remove")
    }

    @Test func replacingAKeyInPlaceAlsoLeavesOne() throws {
        let dir = try bottle("""
        [EnvironmentVariables]
        "GST_PLUGIN_PATH" = "/old"
        "WINEMSYNC" = "1"

        """)
        setBottleEnv(dir, key: "GST_PLUGIN_PATH", value: "/new")
        let out = try read(dir)
        #expect(out.hasSuffix("\n"))
        #expect(out.contains("\"GST_PLUGIN_PATH\" = \"/new\""))
        #expect(!out.contains("/old"), "one key, one line")
        #expect(out.contains("\"WINEMSYNC\" = \"1\""))
    }

    /// Truncating the section is what took other tools' keys with it.
    @Test func aKeyGoesInsideEnvironmentVariablesAndNowhereElse() throws {
        let dir = try bottle("""
        [Bottle]
        "Template" = "win10_64"

        [EnvironmentVariables]
        "WINEMSYNC" = "1"

        [AppDefaults]
        "d3d11" = "native"

        """)
        setBottleEnv(dir, key: "GST_PLUGIN_PATH", value: "/some/where")
        let out = try read(dir)
        let lines = out.components(separatedBy: "\n")
        let key = lines.firstIndex { $0.hasPrefix("\"GST_PLUGIN_PATH\"") }!
        let env = lines.firstIndex { $0 == "[EnvironmentVariables]" }!
        let next = lines.firstIndex { $0 == "[AppDefaults]" }!
        #expect(env < key && key < next, "it landed outside the section it belongs to")
        #expect(out.contains("\"d3d11\" = \"native\""), "the section after ours is not ours to touch")
        #expect(out.hasSuffix("\n"))
    }

    @Test func aFileWithNoSuchSectionGetsOne() throws {
        let dir = try bottle("""
        [Bottle]
        "Template" = "win10_64"

        """)
        setBottleEnv(dir, key: "GST_PLUGIN_PATH", value: "/some/where")
        let out = try read(dir)
        #expect(out.contains("[EnvironmentVariables]"))
        #expect(out.hasSuffix("\n"))
    }

    /// Twice in a row is one line, not two. Restaging calls this every time.
    @Test func writingTheSameKeyTwiceDoesNotDoubleIt() throws {
        let dir = try bottle("""
        [EnvironmentVariables]
        "WINEMSYNC" = "1"

        """)
        setBottleEnv(dir, key: "GST_PLUGIN_PATH", value: "/some/where")
        setBottleEnv(dir, key: "GST_PLUGIN_PATH", value: "/some/where")
        let out = try read(dir)
        #expect(out.components(separatedBy: "\n").filter { $0.hasPrefix("\"GST_PLUGIN_PATH\"") }.count == 1)
        #expect(out.hasSuffix("\n"))
    }
}

/// The path written into a bottle must not depend on what exists when it is
/// written. Two spellings of one directory is how a configuration file grows
/// two lines that mean the same thing.
struct StagedCodecPathTests {

    @Test func theSamePathIsSpelledOneWay() throws {
        let f = FileManager.default
        let engine = "/Applications/CrossOver.app"
        // Ask twice about the same engine: once for an architecture that is
        // staged on this machine and once for a name that is not. Whether the
        // directory happens to be there must not change the spelling.
        let staged = CodecStaging.directory(engineAppPath: engine, arch: "x86_64")
        guard f.fileExists(atPath: staged.appendingPathComponent(".complete").path(percentEncoded: false)),
              let real = stagedCodecPath(cxAppPath: engine, arch: "x86_64")
        else { return }
        #expect(!real.hasSuffix("/"), "a trailing slash that appears only when the directory exists")
        #expect(real.hasSuffix("/gstreamer-1.0"))
    }
}

/// Pointing bottles at the staged codecs, and saying which ones were missed.
///
/// The failure this guards is quiet by nature: a bottle nobody pointed looks
/// exactly like a working one, right up to the first cutscene.
struct ApplyStagedCodecsTests {

    private func bottle(arch: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        [Bottle]
        "WineArch" = "\(arch)"

        [EnvironmentVariables]
        "WINEMSYNC" = "1"

        """.write(to: dir.appendingPathComponent("cxbottle.conf"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func noEngineMeansNothingIsWritten() throws {
        let b = try bottle(arch: "win64")
        #expect(applyStagedCodecs(to: b, cxAppPath: nil) == .noEngine)
        let conf = try String(contentsOf: b.appendingPathComponent("cxbottle.conf"), encoding: .utf8)
        #expect(!conf.contains("GST_PLUGIN_PATH"))
    }

    @Test func aBottleWithNoConfigIsSaidToBeUnreadable() {
        let nowhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("gone-\(UUID().uuidString)", isDirectory: true)
        #expect(applyStagedCodecs(to: nowhere, cxAppPath: "/Applications/CrossOver.app") == .unreadableBottle)
    }

    /// The architecture comes from the bottle, not from the machine. An ARM
    /// bottle handed the x86_64 staging loads libraries of the wrong
    /// architecture into the process.
    @Test func theArchitectureIsTheBottlesOwn() throws {
        let arm = try bottle(arch: "arm64")
        let win = try bottle(arch: "win64")
        // No engine on this path, so the answer is about the arch it chose.
        let noSuchEngine = "/Applications/NoSuchCrossOver.app"
        #expect(applyStagedCodecs(to: arm, cxAppPath: noSuchEngine) == .nothingStaged(arch: "aarch64"))
        #expect(applyStagedCodecs(to: win, cxAppPath: noSuchEngine) == .nothingStaged(arch: "x86_64"))
    }

    @Test func everySelectedBottleGetsAnAnswerAndBlanksAreSkipped() throws {
        let a = try bottle(arch: "win64")
        let b = try bottle(arch: "arm64")
        let results = applyStagedCodecs(toAll: [a.absoluteString, "", b.absoluteString],
                                        cxAppPath: "/Applications/NoSuchCrossOver.app")
        #expect(results.count == 2, "an unselected slot is not a bottle")
        #expect(results.map(\.result) == [.nothingStaged(arch: "x86_64"),
                                          .nothingStaged(arch: "aarch64")])
    }

    /// The ordinary and the ARM slot can hold the same bottle. Writing it twice
    /// is harmless but reporting it twice reads as two problems.
    @Test func theSameBottleTwiceIsOneBottle() throws {
        let a = try bottle(arch: "win64")
        let results = applyStagedCodecs(toAll: [a.absoluteString, a.absoluteString],
                                        cxAppPath: "/Applications/NoSuchCrossOver.app")
        #expect(results.count == 1)
    }

    @Test func aRealStagingIsActuallyWritten() throws {
        // Only where this machine has one. The point is that the value written
        // is the same string stagedCodecPath hands out -- one spelling.
        let engine = "/Applications/CrossOver.app"
        guard let expected = stagedCodecPath(cxAppPath: engine, arch: "x86_64") else { return }
        let b = try bottle(arch: "win64")
        #expect(applyStagedCodecs(to: b, cxAppPath: engine) == .pointed(arch: "x86_64"))
        let conf = try String(contentsOf: b.appendingPathComponent("cxbottle.conf"), encoding: .utf8)
        #expect(conf.contains("\"GST_PLUGIN_PATH\" = \"\(expected)\""))
        #expect(conf.hasSuffix("\n"))
        #expect(conf.contains("\"WINEMSYNC\" = \"1\""))
    }
}

/// A bottle carried between engines.
///
/// The staging symlinks its GStreamer core into the engine it was built for.
/// Point a bottle at it and then open that bottle with an older engine, and
/// two cores load in one process -- which is the crash the whole staging
/// arrangement exists to avoid. On this machine a 26.3 bottle points at a
/// staging built for 27, and nothing said so.
struct EngineMismatchTests {

    private func bottle(arch: String, version: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("m-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        [Bottle]
        "WineArch" = "\(arch)"
        "Version" = "\(version)"

        [EnvironmentVariables]
        "WINEMSYNC" = "1"

        """.write(to: dir.appendingPathComponent("cxbottle.conf"), atomically: true, encoding: .utf8)
        return dir
    }

    /// Only meaningful where this machine has a staging to point at.
    private func engineWithStaging() -> (path: String, version: String, arch: String)? {
        let f = FileManager.default
        for name in ["Crossover_patched.app", "CrossOver.app"] {
            for root in [f.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path(percentEncoded: false),
                         "/Applications"] {
                let app = root + "/" + name
                guard f.fileExists(atPath: app),
                      let version = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleVersion"] as? String
                else { continue }
                for arch in CodecStaging.architectures(ofEngineAt: app) where stagedCodecPath(cxAppPath: app, arch: arch) != nil {
                    return (app, version, arch)
                }
            }
        }
        return nil
    }

    @Test func aBottleFromTheSameEngineIsJustPointed() throws {
        guard let e = engineWithStaging() else { return }
        let b = try bottle(arch: e.arch == "aarch64" ? "arm64" : "win64", version: e.version)
        #expect(applyStagedCodecs(to: b, cxAppPath: e.path) == .pointed(arch: e.arch))
    }

    @Test func aBottleFromAnotherEngineIsPointedAndSaidSo() throws {
        guard let e = engineWithStaging() else { return }
        let b = try bottle(arch: e.arch == "aarch64" ? "arm64" : "win64", version: "1.2.3.4")
        let result = applyStagedCodecs(to: b, cxAppPath: e.path)
        #expect(result == .pointedAtAnotherEngine(arch: e.arch, bottle: "1.2.3.4", engine: e.version))
        // Pointed all the same: it is right for the engine we launch with,
        // and refusing would leave whatever stale value was there before.
        let conf = try String(contentsOf: b.appendingPathComponent("cxbottle.conf"), encoding: .utf8)
        #expect(conf.contains("\"GST_PLUGIN_PATH\""))
        #expect(conf.contains("\"GST_REGISTRY\""))
    }

    /// A bottle that has never been through an engine has no version to
    /// compare, and a guess is not an answer.
    @Test func aBottleWithNoVersionIsNotAccused() throws {
        guard let e = engineWithStaging() else { return }
        let b = try bottle(arch: e.arch == "aarch64" ? "arm64" : "win64", version: "")
        #expect(applyStagedCodecs(to: b, cxAppPath: e.path) == .pointed(arch: e.arch))
    }
}
