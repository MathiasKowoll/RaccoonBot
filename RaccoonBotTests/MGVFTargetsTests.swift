//
//  MGVFTargetsTests.swift
//  RaccoonBotTests
//
//  Where a fix is allowed to be installed, and which bottle it is pinned to --
//  the question a Kingdom Hearts run answered for itself by finding four
//  bottles nobody had named, one of them Battle.net's.
//

import Foundation
import Testing
@testable import RaccoonBot

struct MGVFTargetsTests {

    private func game(scope: String?, writesRegistry: Bool) -> MGVFGame {
        MGVFGame(name: "A Title", script: "install.sh", exe: "Game.exe", files: [],
                 carrier: "", keptAs: "", carrierDir: "", why: "because",
                 writesRegistry: writesRegistry, scope: scope, backend: nil,
                 gptk: nil, env: nil, codec: nil)
    }

    /// KINGDOM HEARTS: folder-scoped, and it writes registry overrides. The
    /// combination scope alone would have missed.
    private var kingdomHearts: MGVFGame { game(scope: "folder", writesRegistry: true) }
    /// NINJA GAIDEN 3: the installer takes the bottle itself.
    private var ninjaGaiden3: MGVFGame { game(scope: "bottle", writesRegistry: true) }
    /// Nioh and most others: a DLL beside the game, no bottle involved.
    private var folderOnly: MGVFGame { game(scope: "folder", writesRegistry: false) }

    private func reference(_ path: String) throws -> BottleReference {
        try #require(BottleReference(path))
    }

    private func bottles() throws -> [BottleReference] {
        [try reference("/Users/x/RaccoonBot/CXPBottles/Steam"),
         try reference("/Users/x/RaccoonBot/CXPBottles/Epic")]
    }

    // MARK: which fixes touch a bottle at all

    @Test func aFixThatWritesRegistryNeedsABottleEvenWhenItIsFolderScoped() {
        #expect(kingdomHearts.needsABottle)
        #expect(ninjaGaiden3.needsABottle)
        #expect(folderOnly.needsABottle == false)
    }

    // MARK: a fix that touches no bottle

    @Test func aFolderOnlyFixRunsOnceAgainstTheGameFolderAndNamesNoBottle() throws {
        let placements = folderOnly.placements(gameFolder: "/games/Nioh", bottles: try bottles())
        #expect(placements.count == 1)
        #expect(placements.first?.target == "/games/Nioh")
        #expect(placements.first?.bottle == nil)
    }

    /// It does not stop existing because no bottle is configured: none is
    /// involved.
    @Test func aFolderOnlyFixDoesNotNeedABottleToBeConfigured() {
        let placements = folderOnly.placements(gameFolder: "/games/Nioh", bottles: [])
        #expect(placements.map(\.target) == ["/games/Nioh"])
    }

    // MARK: a bottle-scoped fix

    /// The requirement, in the owner's words: a patch installs into the bottles
    /// RaccoonBot defines, and if there are ten it is ten.
    @Test func aBottleFixRunsOncePerConfiguredBottleInConfigurationOrder() throws {
        let placements = ninjaGaiden3.placements(gameFolder: "/games/NG3", bottles: try bottles())
        #expect(placements.map(\.target) == ["/Users/x/RaccoonBot/CXPBottles/Steam",
                                             "/Users/x/RaccoonBot/CXPBottles/Epic"])
        #expect(placements.map(\.bottle) == ["/Users/x/RaccoonBot/CXPBottles/Steam",
                                             "/Users/x/RaccoonBot/CXPBottles/Epic"])
    }

    /// Passing the game folder is why `--status` answered "not a bottle", exit
    /// 1, and the gate could not be cleared for a fix already installed.
    @Test func aBottleFixNeverTargetsTheGameFolder() throws {
        let placements = ninjaGaiden3.placements(gameFolder: "/games/NG3",
                                                 bottles: [try reference("/b/Steam")])
        #expect(placements.map(\.target).contains("/games/NG3") == false)
    }

    // MARK: the case that caused all of this

    /// KINGDOM HEARTS is handed its own game folder -- correctly, it is
    /// folder-scoped -- and is pinned to a bottle anyway. Without the pin the
    /// installer goes looking, and what it found was Battle.net's bottle.
    @Test func aRegistryWritingFolderFixIsPinnedWhileStillTargetingTheFolder() throws {
        let placements = kingdomHearts.placements(gameFolder: "/games/KH", bottles: try bottles())
        #expect(placements.count == 2)
        #expect(placements.map(\.target) == ["/games/KH", "/games/KH"])
        #expect(placements.map(\.bottle) == ["/Users/x/RaccoonBot/CXPBottles/Steam",
                                             "/Users/x/RaccoonBot/CXPBottles/Epic"])
    }

    /// Nothing configured is not "install everywhere" and not "install in the
    /// folder instead". It is nowhere, and the caller has to refuse.
    @Test func noBottlesMeansNoRunsRatherThanAFallback() {
        #expect(kingdomHearts.placements(gameFolder: "/games/KH", bottles: []).isEmpty)
        #expect(ninjaGaiden3.placements(gameFolder: "/games/NG3", bottles: []).isEmpty)
    }

    // MARK: the shape of the value

    /// The settings hold `Application%20Support`, and a script handed that
    /// would not find it. `MGVF_BOTTLE` is an absolute path to the directory
    /// holding drive_c -- not a name, not a URL.
    @Test func theBottleIsAnAbsolutePathAScriptCanUse() throws {
        let stored = "file:///Users/x/Library/Application%20Support/RaccoonBot/CXPBottles/Steam/"
        let placements = kingdomHearts.placements(gameFolder: "/games/KH",
                                                  bottles: [try reference(stored)])
        #expect(placements.map(\.bottle)
                == ["/Users/x/Library/Application Support/RaccoonBot/CXPBottles/Steam"])
    }

    /// `URL.path` reports a trailing slash only for a directory that exists, so
    /// the same setting produced two different strings depending on the machine.
    @Test func theTrailingSlashIsGoneWhicheverWayItWasStored() throws {
        for stored in ["/b/Steam", "/b/Steam/", "file:///b/Steam/"] {
            let placements = ninjaGaiden3.placements(gameFolder: "/g",
                                                     bottles: [try reference(stored)])
            #expect(placements.map(\.bottle) == ["/b/Steam"], "for \(stored)")
        }
    }

    /// A reference built from a bare name carries no directory, so there is no
    /// path to pin to. Dropped rather than guessed at.
    @Test func aBareNameIsNotAUsablePin() throws {
        let placements = ninjaGaiden3.placements(gameFolder: "/g",
                                                 bottles: [try reference("Steam")])
        #expect(placements.isEmpty)
    }

    // MARK: when the bottles disagree

    /// "Installed in one of the two" is not installed. Reporting the better
    /// half would hide the exact case this change exists to stop.
    @Test func theWorstAnswerWins() {
        #expect(MGVFCatalog.isWorse(.needsPatch, than: .patched))
        #expect(MGVFCatalog.isWorse(.unknown("no"), than: .needsPatch))
        #expect(MGVFCatalog.isWorse(.needsPatch, than: .outdated))
        #expect(MGVFCatalog.isWorse(.patched, than: .needsPatch) == false)
        #expect(MGVFCatalog.isWorse(.patched, than: .patched) == false)
    }
}
