//
//  EnvPrecedenceTests.swift
//  RaccoonBotTests
//

import Foundation
import Testing
@testable import RaccoonBot

struct EnvPrecedenceTests {

    private func options(typed: String, ue4: Bool = true) -> GameOptions {
        let o = GameOptions()
        o.envVariables = typed
        o.ue4Hack = ue4
        o.cxGraphicsBackend = "d3dmetal4"
        return o
    }

    /// `env` takes the LAST assignment for a repeated name, so where a typed
    /// variable sits in the line is the whole of the precedence rule.
    ///
    /// It used to be written first, which made the box inert for every name
    /// this function also sets -- and inert without a word: both assignments
    /// were on the command line and only the second did anything.
    @Test func whatSomebodyTypedWinsOverWhatWeChose() {
        let rendered = getInlineEnvs(from: options(typed: "MVK_CONFIG_UE4_HACK_ENABLED=0"))
        let ours = try! #require(rendered.range(of: "MVK_CONFIG_UE4_HACK_ENABLED=1"))
        let theirs = try! #require(rendered.range(of: "MVK_CONFIG_UE4_HACK_ENABLED=0"))
        #expect(theirs.lowerBound > ours.lowerBound,
                "the typed value must come after ours or env will ignore it")
    }

    @Test func nothingTypedChangesNothing() {
        let rendered = getInlineEnvs(from: options(typed: ""))
        #expect(rendered.contains("MVK_CONFIG_UE4_HACK_ENABLED=1"))
        #expect(rendered.hasPrefix(" ") == false)
    }

    // MARK: saying "not set at all"

    /// A toggle that is off writes the opposite, not nothing. So "we set it to
    /// 0 and it still failed" says nothing about whether setting it at all is
    /// the problem, and comparing against a launch that names neither variable
    /// needs a way to name neither.
    @Test func aLeadingMinusRemovesAVariableEntirely() {
        #expect(EnvAssignments.removals("-MVK_CONFIG_UE4_HACK_ENABLED")
                == ["MVK_CONFIG_UE4_HACK_ENABLED"])
        #expect(EnvAssignments.removalArguments("-MVK_CONFIG_UE4_HACK_ENABLED\n-NAS_DISABLE_UE4_HACK")
                == "-u MVK_CONFIG_UE4_HACK_ENABLED -u NAS_DISABLE_UE4_HACK ")
    }

    @Test func anAssignmentIsNotARemoval() {
        #expect(EnvAssignments.removals("FOO=1").isEmpty)
        #expect(EnvAssignments.removals("-FOO=1").isEmpty)
        #expect(EnvAssignments.removalArguments("FOO=1") == "")
    }

    /// Anything that is not a plain name is dropped rather than passed on: a
    /// stray token reaching `env` is read as the program to run, and the launch
    /// dies before anything starts.
    @Test func onlyARealNameIsAccepted() {
        #expect(EnvAssignments.removals("-  ").isEmpty)
        #expect(EnvAssignments.removals("-FOO BAR").isEmpty)
        #expect(EnvAssignments.removals("-rm -rf /").isEmpty)
        #expect(EnvAssignments.removals("-FOO_1") == ["FOO_1"])
    }

    /// Removals and assignments live in the same box and must not disturb each
    /// other: one is an argument to `env`, the other is an assignment.
    @Test func theTwoFormsCoexistInOneBox() {
        let typed = "-MVK_CONFIG_UE4_HACK_ENABLED\nDXVK_HUD=fps"
        #expect(EnvAssignments.removals(typed) == ["MVK_CONFIG_UE4_HACK_ENABLED"])
        #expect(EnvAssignments.normalised(typed).contains("DXVK_HUD=fps"))
        #expect(EnvAssignments.normalised(typed).contains("-MVK") == false)
    }
}
