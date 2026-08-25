//
//  MGVFBundleTests.swift
//  ProcyonTests
//
//  The parts that decide whether something downloaded from the internet gets
//  copied into a user's game folder.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import Procyon

struct MGVFReleaseParsingTests {

    private func json(_ s: String) -> Data { s.data(using: .utf8)! }

    @Test func picksTheBundleAndItsChecksum() throws {
        let release = try MGVFBundle.parseRelease(json("""
        {"tag_name":"v4.8.2","assets":[
          {"name":"MacGameVideoFix-4.8.2.zip","browser_download_url":"https://x/app.zip"},
          {"name":"fixes-v4.8.2.tar.gz","browser_download_url":"https://x/fixes.tar.gz"},
          {"name":"fixes-v4.8.2.tar.gz.sha256","browser_download_url":"https://x/fixes.sha256"}
        ]}
        """))
        #expect(release.tag == "v4.8.2")
        #expect(release.tarball.absoluteString == "https://x/fixes.tar.gz")
        #expect(release.checksum?.absoluteString == "https://x/fixes.sha256")
    }

    @Test func doesNotMistakeTheAppForTheBundle() throws {
        // The app zip is attached to every release and is the bigger asset. A
        // looser match would download 1.6 MB of the wrong thing and then fail
        // to find a manifest inside it.
        let release = try MGVFBundle.parseRelease(json("""
        {"tag_name":"v4.8.2","assets":[
          {"name":"MacGameVideoFix-4.8.2.zip","browser_download_url":"https://x/app.zip"},
          {"name":"fixes-v4.8.2.tar.gz","browser_download_url":"https://x/fixes.tar.gz"}
        ]}
        """))
        #expect(release.tarball.lastPathComponent == "fixes.tar.gz")
        #expect(release.checksum == nil)
    }

    @Test func reportsARateLimitInsteadOfCrashing() {
        // The anonymous API allows 60 requests an hour and answers a limit with
        // a message and no tag. Forcing that cast is how the DXMT path takes
        // the app down instead of saying the server is busy.
        #expect(throws: MGVFBundleError.self) {
            _ = try MGVFBundle.parseRelease(self.json("""
            {"message":"API rate limit exceeded","documentation_url":"https://docs.github.com/"}
            """))
        }
    }

    @Test func reportsAnAnswerThatIsNotJSON() {
        // A captive portal or a proxy answers HTML to everything.
        #expect(throws: MGVFBundleError.self) {
            _ = try MGVFBundle.parseRelease("<html>Sign in to the network</html>".data(using: .utf8)!)
        }
    }

    @Test func reportsAReleaseWithNoBundleAttached() {
        // Every release before v4.8.1 is exactly this: tag and notes, no
        // assets. Silently returning nothing would look like "up to date".
        #expect(throws: MGVFBundleError.self) {
            _ = try MGVFBundle.parseRelease(self.json("""
            {"tag_name":"v4.7.4","assets":[]}
            """))
        }
    }
}

struct MGVFChecksumTests {

    @Test func readsTheDigestFromAShasumLine() {
        let line = "f5438158d3b0e26969182fdfc47cec5400513936a51fd9662774aa71d19f4790  fixes-v4.8.1.tar.gz\n"
        #expect(MGVFBundle.expectedChecksum(in: line.data(using: .utf8)!)
                == "f5438158d3b0e26969182fdfc47cec5400513936a51fd9662774aa71d19f4790")
    }

    @Test func findsNoDigestInSomethingThatIsNotOne() {
        #expect(MGVFBundle.expectedChecksum(in: "not a checksum at all".data(using: .utf8)!) == nil)
    }

    @Test func computesTheDigestTheSameWayShasumDoes() {
        // Verified against `printf 'procyon' | shasum -a 256`.
        let digest = MGVFBundle.sha256(of: "procyon".data(using: .utf8)!)
        #expect(digest.count == 64)
        #expect(digest == digest.lowercased())
    }
}

struct MGVFTagOrderTests {

    @Test func ordersByNumberNotByText() {
        // Lexicographically "v4.8.10" sorts before "v4.8.2", which would make
        // the older bundle the newest cached one.
        #expect(MGVFBundle.compareTags("v4.8.10", "v4.8.2") == .orderedDescending)
        #expect(MGVFBundle.compareTags("v4.8.2", "v4.8.10") == .orderedAscending)
        #expect(MGVFBundle.compareTags("v4.9.0", "v4.10.0") == .orderedAscending)
        #expect(MGVFBundle.compareTags("v4.8.2", "v4.8.2") == .orderedSame)
    }
}

struct MGVFManifestTests {

    @Test func readsAManifestAndRefusesANewerSchema() throws {
        let bundle = MGVFBundle()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mgvf-manifest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let good = """
        {"schema":1,"version":"v4.8.2","commit":"cbdcdd9","games":[
          {"script":"install-nier-bridge.sh","exe":"NieR Replicant ver.1.22474487139.exe",
           "files":["dinput8-nier.dll"],"carrier":"dinput8.dll","keptAs":"dinput8_real.dll",
           "writesRegistry":true}]}
        """
        try good.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let manifest = try bundle.manifest(at: dir)
        #expect(manifest.version == "v4.8.2")
        #expect(manifest.games.first?.carrier == "dinput8.dll")
        #expect(manifest.games.first?.writesRegistry == true)

        // A newer contract is refused rather than read on a best-effort basis:
        // a field that changed meaning would otherwise be acted on anyway.
        let future = good.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":2")
        try future.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        #expect(throws: MGVFBundleError.self) { _ = try bundle.manifest(at: dir) }
    }
}

struct MGVFUnpackTests {

    /// Builds a tarball in memory the way the release does, then unpacks it
    /// through the real code path.
    @Test func unpacksAndRefusesAnArchiveWithoutAManifest() throws {
        let f = FileManager.default
        let work = f.temporaryDirectory.appendingPathComponent("mgvf-pack-\(UUID().uuidString)")
        try f.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? f.removeItem(at: work) }

        let content = work.appendingPathComponent("c", isDirectory: true)
        try f.createDirectory(at: content, withIntermediateDirectories: true)
        try "#!/bin/bash\necho absent\n".write(to: content.appendingPathComponent("install-fake.sh"),
                                               atomically: true, encoding: .utf8)

        func tarball(of dir: URL) throws -> Data {
            let out = work.appendingPathComponent("\(UUID().uuidString).tar.gz")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            p.arguments = ["-czf", out.path(percentEncoded: false),
                           "-C", dir.path(percentEncoded: false), "."]
            try p.run(); p.waitUntilExit()
            return try Data(contentsOf: out)
        }

        let bundle = MGVFBundle()

        // No manifest: refused, and nothing is left behind claiming to be a
        // bundle.
        #expect(throws: MGVFBundleError.self) {
            _ = try bundle.unpack(try tarball(of: content), tag: "v0.0.0-test-nomanifest")
        }
        #expect(!f.fileExists(atPath: bundle.directory(for: "v0.0.0-test-nomanifest").path(percentEncoded: false)))

        // With a manifest: unpacked, and readable through the normal path.
        try #"{"schema":1,"version":"v0.0.0","commit":"test","games":[]}"#
            .write(to: content.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let tag = "v0.0.0-test-ok"
        let dir = try bundle.unpack(try tarball(of: content), tag: tag)
        defer { try? f.removeItem(at: dir) }
        #expect(f.fileExists(atPath: dir.appendingPathComponent("install-fake.sh").path(percentEncoded: false)))
        #expect(try bundle.manifest(at: dir).commit == "test")
        #expect(bundle.cachedTags().contains(tag))
    }
}
