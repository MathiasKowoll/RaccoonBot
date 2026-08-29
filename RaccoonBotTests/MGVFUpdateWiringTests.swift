//
//  MGVFUpdateWiringTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// The check itself was already tested. What was missing was anybody calling
/// it, and a test cannot see a call that is not made -- so these are about the
/// decision it hands back, which is what the caller now acts on.
@Suite("Noticing a newer fixes bundle")
struct MGVFUpdateWiringTests {

    /// The state this machine was actually in: v4.8.6 on disk, v4.11.1
    /// published, and nothing asking.
    @Test func aNewerReleaseIsNewer() {
        #expect(MGVFBundle.compare(remote: "v4.11.1", cached: "v4.8.6") == .newer("v4.11.1"))
    }

    @Test func theSameReleaseIsNotAnUpdate() {
        #expect(MGVFBundle.compare(remote: "v4.11.1", cached: "v4.11.1") == .upToDate("v4.11.1"))
    }

    /// Lexicographic order puts v4.8.10 before v4.8.2, which would have made
    /// every tenth release invisible.
    @Test func versionsAreComparedAsNumbersNotText() {
        #expect(MGVFBundle.compare(remote: "v4.8.10", cached: "v4.8.2") == .newer("v4.8.10"))
        #expect(MGVFBundle.compare(remote: "v4.8.2", cached: "v4.8.10") == .upToDate("v4.8.10"))
    }

    @Test func anEmptyMachineTakesAnything() {
        #expect(MGVFBundle.compare(remote: "v4.11.1", cached: nil) == .nothingCached("v4.11.1"))
    }

    /// An older remote than what is on disk is not an update, however odd that
    /// is -- a release withdrawn upstream must not roll this machine back.
    @Test func anOlderReleaseIsNotTakenAsAnUpdate() {
        #expect(MGVFBundle.compare(remote: "v4.8.6", cached: "v4.11.1") == .upToDate("v4.11.1"))
    }
}
