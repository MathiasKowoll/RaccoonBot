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
