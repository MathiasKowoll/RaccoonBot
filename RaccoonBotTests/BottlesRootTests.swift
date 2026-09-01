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

    /// And the bottles this application is configured with sit under it, which
    /// is what makes the two settings one story rather than two.
    @Test func theConfiguredBottlesLiveUnderTheRoot() throws {
        let globals = AppGlobals()
        guard !globals.selectedBottle.isEmpty else { return }
        let bottle = try #require(BottleReference(globals.selectedBottle))
        var root = globals.bottlesRoot
        while root.count > 1 && root.hasSuffix("/") { root.removeLast() }
        #expect(bottle.root == root,
                "the selected bottle sits under \(bottle.root) but the root says \(root)")
    }
}
