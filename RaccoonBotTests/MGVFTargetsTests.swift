//
//  MGVFTargetsTests.swift
//  RaccoonBotTests
//
//  Where a fix is allowed to be installed, which is the question a Kingdom
//  Hearts run answered for itself by finding four bottles nobody had named.
//

import Foundation
import Testing
@testable import RaccoonBot

struct MGVFTargetsTests {

    private func game(scope: String?) -> MGVFGame {
        MGVFGame(name: "KINGDOM HEARTS HD 1.5+2.5", script: "install-kh-fix.sh",
                 exe: "KINGDOM HEARTS FINAL MIX.exe", files: [], carrier: "",
                 keptAs: "", carrierDir: "", why: "green cutscenes",
                 writesRegistry: true, scope: scope, backend: nil, gptk: nil,
                 env: nil, codec: nil)
    }

    private func reference(_ path: String) throws -> BottleReference {
        try #require(BottleReference(path))
    }

    // MARK: folder-scoped

    @Test func aFolderFixGoesToTheGameFolderAndNowhereElse() throws {
        let bottles = [try reference("/Users/x/RaccoonBot/CXPBottles/Steam"),
                       try reference("/Users/x/RaccoonBot/CXPBottles/Epic")]
        #expect(game(scope: "folder").targets(gameFolder: "/games/Nioh", bottles: bottles)
                == ["/games/Nioh"])
        #expect(game(scope: nil).targets(gameFolder: "/games/Nioh", bottles: bottles)
                == ["/games/Nioh"])
    }

    /// A folder fix does not stop existing because no bottle is configured.
    @Test func aFolderFixDoesNotNeedABottleAtAll() {
        #expect(game(scope: "folder").targets(gameFolder: "/games/Nioh", bottles: [])
                == ["/games/Nioh"])
    }

    // MARK: bottle-scoped

    /// The requirement, in the owner's words: a patch installs into the bottles
    /// RaccoonBot defines, and if there are ten it is ten.
    @Test func aBottleFixGoesToEveryConfiguredBottleAndInConfigurationOrder() throws {
        let bottles = [try reference("/Users/x/RaccoonBot/CXPBottles/Steam"),
                       try reference("/Users/x/RaccoonBot/CXPBottles/Epic")]
        #expect(game(scope: "bottle").targets(gameFolder: "/games/KH", bottles: bottles)
                == ["/Users/x/RaccoonBot/CXPBottles/Steam",
                    "/Users/x/RaccoonBot/CXPBottles/Epic"])
    }

    /// The game folder is never a target for a bottle fix. Passing it is why
    /// `--status` answered "not a bottle", exit 1, and the gate could not be
    /// cleared from the interface for a fix that was already installed.
    @Test func aBottleFixNeverTargetsTheGameFolder() throws {
        let targets = game(scope: "bottle")
            .targets(gameFolder: "/games/KH", bottles: [try reference("/b/Steam")])
        #expect(targets.contains("/games/KH") == false)
    }

    /// Nothing configured is not "install everywhere" and not "install in the
    /// folder instead". It is nowhere, and the caller has to refuse.
    @Test func noBottlesMeansNoTargetsRatherThanAFallback() {
        #expect(game(scope: "bottle").targets(gameFolder: "/games/KH", bottles: []).isEmpty)
    }

    /// Percent-encoding survives the round trip: the settings hold
    /// `Application%20Support`, and a script handed that would not find it.
    @Test func theTargetIsAPathAScriptCanUse() throws {
        let stored = "file:///Users/x/Library/Application%20Support/RaccoonBot/CXPBottles/Steam/"
        let targets = game(scope: "bottle")
            .targets(gameFolder: "/games/KH", bottles: [try reference(stored)])
        #expect(targets == ["/Users/x/Library/Application Support/RaccoonBot/CXPBottles/Steam"])
    }

    /// A reference built from a bare name has no directory, so there is no path
    /// to hand a script. Dropped rather than guessed at.
    @Test func aBareNameIsNotAUsableTarget() throws {
        let targets = game(scope: "bottle")
            .targets(gameFolder: "/games/KH", bottles: [try reference("Steam")])
        #expect(targets.isEmpty)
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
