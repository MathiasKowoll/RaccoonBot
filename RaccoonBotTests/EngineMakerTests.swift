//
//  EngineMakerTests.swift
//  RaccoonBotTests
//

import Foundation
import Testing
@testable import RaccoonBot

struct EngineMakerTests {

    /// The script travels inside this application, so the engine and the thing
    /// that knows how to make it ship together.
    @Test func theScriptIsCarried() {
        let embedded = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RaccoonBot/Libs/mgvf/MacGameVideoFix.app/Contents/Resources/make-engine-copy.sh")
        #expect(FileManager.default.fileExists(atPath: embedded.path(percentEncoded: false)))
    }

    /// Refused before the script is asked. The bottle root is the isolation --
    /// an engine without CX_BOTTLE_PATH falls through to stock CrossOver's root
    /// and works on somebody else's bottles -- so an empty one must never
    /// become an omitted flag.
    @Test func anEmptyBottleRootIsRefusedBeforeAnythingRuns() async {
        await #expect(throws: EngineMaker.Failure.noBottlesRoot) {
            try await EngineMaker.make(from: URL(fileURLWithPath: "/Applications/CrossOver.app"),
                                       bottlesRoot: "   ",
                                       progress: { _, _ in })
        }
    }

    /// Progress comes from the script's own steps rather than a guess.
    @Test func theStepsAreRead() {
        #expect(EngineMaker.step(in: "[1/6] copying") == 1)
        #expect(EngineMaker.step(in: "[4/6] toolkit: unchanged") == 4)
        #expect(EngineMaker.step(in: "[6/6] signing") == 6)
        #expect(EngineMaker.step(in: "copy      : /Users/x/Applications/Thing.app") == nil)
        #expect(EngineMaker.step(in: "") == nil)
    }

    /// Success is the script saying where it put the engine, not merely
    /// exiting zero -- and the LAST such line, since it ends with one.
    @Test func theEngineIsWhereTheScriptSaysItIs() {
        let output = """
        [6/6] signing
          bottles   : /Users/x/Library/Application Support/RaccoonBot/CXPBottles/
          wine      : wine-11.0
        ready: /Users/x/Applications/Crossover_MGVF.app
        Open it once from Finder, pick a bottle, and it runs with this engine.
        """
        #expect(EngineMaker.readyPath(in: output) == "/Users/x/Applications/Crossover_MGVF.app")
        #expect(EngineMaker.readyPath(in: "error: --bottle-path is required.") == nil)
    }
}
