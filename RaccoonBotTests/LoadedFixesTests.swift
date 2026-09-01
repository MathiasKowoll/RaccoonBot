//
//  LoadedFixesTests.swift
//  RaccoonBotTests
//

import Foundation
import Testing
@testable import RaccoonBot

struct LoadedFixesTests {

    /// A payload unpacked under Application Support is a download, whatever
    /// its version says.
    @Test func aPayloadOutsideTheBundleIsADownload() {
        let loaded = MGVFLibrary.LoadedFixes(
            version: "5.0.0",
            directory: URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/Procyon/mgvf/v5.0.0"))
        #expect(loaded.isBundled == false)
        #expect(loaded.describedSource == "downloaded")
    }

    /// And one inside our own Resources is not, which is what makes this keep
    /// telling the truth when the payload moves into the bundle -- the answer
    /// comes from where the files are, not from a flag somebody sets.
    @Test func aPayloadInsideTheBundleSaysSo() throws {
        let resources = try #require(Bundle.main.resourceURL)
        let loaded = MGVFLibrary.LoadedFixes(
            version: "5.0.0",
            directory: resources.appendingPathComponent("fixes"))
        #expect(loaded.isBundled)
        #expect(loaded.describedSource == "bundled")
    }

    /// The version is carried, not derived: it is read from the manifest that
    /// was actually loaded rather than from the tag that was asked for, and
    /// those diverge exactly when somebody needs to know which ran.
    @Test func theVersionIsWhateverWasLoaded() {
        let loaded = MGVFLibrary.LoadedFixes(version: "4.12.1",
                                             directory: URL(fileURLWithPath: "/tmp/x"))
        #expect(loaded.version == "4.12.1")
    }
}
