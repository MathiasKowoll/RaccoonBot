//
//  DownloadCacheTests.swift
//  RaccoonBotTests
//
//  The download cache lives in ~/Library/Caches, which macOS empties whenever
//  it likes -- that is what the directory is for. The flag saying "already
//  downloaded" lives in preferences, which it does not. The two drift apart on
//  their own, and the drift used to be silent: the flag was believed, the empty
//  directory was handed on, DXMT was not installed, and the engine was signed
//  and marked as patched anyway.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct DownloadCacheTests {

    private func key(for url: URL) -> String {
        namespacedKey("downloads", url.lastPathComponent)
    }

    private func cleanSlate(_ url: URL) {
        deleteUsrDefOption(key: key(for: url))
        try? FileManager.default.removeItem(at: TarDownloader.getDownloadsDir())
    }

    /// The flag alone is not evidence. With the extracted directory gone, the
    /// downloader must fetch again rather than report success over nothing.
    @Test func aFlagWithoutTheFilesIsNotACacheHit() async {
        let url = URL(string: "https://example.invalid/dxmt-v0.99-builtin.tar.gz")!
        cleanSlate(url)
        defer { cleanSlate(url) }
        persistUsrDefOptionString(key: key(for: url), value: url.path(percentEncoded: false))

        let completed = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            var resumed = false
            let d = TarDownloader(fromUrl: url, expecting: "v0.99",
                                  onProgress: { _ in },
                                  onComplete: { _ in if !resumed { resumed = true; c.resume(returning: true) } },
                                  onError: { _ in if !resumed { resumed = true; c.resume(returning: false) } })
            d.download()
        }
        // example.invalid does not resolve, so a real attempt fails. Failing is
        // the right answer; reporting completion over an empty directory is not.
        #expect(completed == false, "it believed the flag instead of looking")
        // And the stale flag is gone, so the next run does not repeat the lie.
        #expect(readUsrDefOptionString(key: key(for: url)) == nil)
    }

    @Test func aFlagWithTheFilesIsACacheHit() async {
        let url = URL(string: "https://example.invalid/dxmt-v0.98-builtin.tar.gz")!
        cleanSlate(url)
        defer { cleanSlate(url) }
        let dir = TarDownloader.getDownloadsDir().appendingPathComponent("v0.98", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        persistUsrDefOptionString(key: key(for: url), value: url.path(percentEncoded: false))

        let completed = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            var resumed = false
            let d = TarDownloader(fromUrl: url, expecting: "v0.98",
                                  onProgress: { _ in },
                                  onComplete: { _ in if !resumed { resumed = true; c.resume(returning: true) } },
                                  onError: { _ in if !resumed { resumed = true; c.resume(returning: false) } })
            d.download()
        }
        #expect(completed, "the files are there and it went to the network anyway")
    }

    /// Both outcomes have to reach the caller. A patching run waits on a
    /// continuation that only onComplete and onError resume, so a path that
    /// calls neither hangs it for good.
    @Test func aFailedDownloadReportsRatherThanGoingQuiet() async {
        let url = URL(string: "https://example.invalid/nothing-here.tar.gz")!
        cleanSlate(url)
        defer { cleanSlate(url) }

        let answered = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            var resumed = false
            let d = TarDownloader(fromUrl: url, expecting: "whatever",
                                  onProgress: { _ in },
                                  onComplete: { _ in if !resumed { resumed = true; c.resume(returning: true) } },
                                  onError: { _ in if !resumed { resumed = true; c.resume(returning: true) } })
            d.download()
        }
        #expect(answered)
    }
}

/// DXMT missing from the unpacked archive used to be a log line, and the
/// patching run carried on to sign and mark the engine.
struct DXMTErrorTests {

    @Test func aMissingSourceIsAnErrorThatNamesTheFile() {
        let message = DXMTError.sourceMissing("/some/where/x86_64-unix/winemetal.so").errorDescription ?? ""
        #expect(message.contains("/some/where"))
        #expect(message.contains("not installed"))
    }

    @Test func aTagThatIsNotAnAddressIsRefusedRatherThanForced() {
        // The tag comes off the network. It used to build a URL with `!`.
        #expect(DXMTError.badReleaseTag("v 1.0").errorDescription?.contains("v 1.0") == true)
    }
}
