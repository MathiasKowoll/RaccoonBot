//
//  BottlesRootTests.swift
//  RaccoonBotTests
//

import Foundation
import Testing
@testable import RaccoonBot

struct BottlesRootTests {

    /// The default is where bottles have always lived, so an existing install
    /// keeps working and simply starts showing what it was already doing.
    @Test func theDefaultIsWhereBottlesAlreadyAre() {
        #expect(DEFAULT_BOTTLES_ROOT.contains("CXPBottles"))
        #expect(DEFAULT_BOTTLES_ROOT.hasPrefix("/"))
    }

    /// A fresh AppGlobals answers with a usable root rather than an empty
    /// string, because the value is written into an engine's CrossOver.conf
    /// and an empty one points it at nothing.
    @Test func aFreshInstallStillHasARoot() {
        #expect(AppGlobals().bottlesRoot.isEmpty == false)
    }

    /// It has to be a real bottle root, not a name: MacGameVideoFix's
    /// --bottle-path takes a path, and BottleReference exists because a
    /// file:// URL once arrived where a path belonged.
    @Test func theRootIsAPathAScriptCanUse() {
        let root = AppGlobals().bottlesRoot
        #expect(root.hasPrefix("file://") == false)
        #expect(root.contains("%20") == false)
    }

    // A case that asserted THIS machine's configuration was here and has
    // been removed. It compared the saved bottle against the saved root, which
    // is a fact about one install rather than about the code -- the same
    // antipattern as a test that needs a particular engine on disk. It would
    // fail for somebody who moved their bottles, which is the thing the
    // setting exists to let them do.
}
