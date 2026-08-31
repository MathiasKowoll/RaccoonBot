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

    /// The test that would have caught it. `env -u NAME` does NOT win against a
    /// later `NAME=value` -- measured: `env -u A A=1 sh -c 'echo $A'` prints 1 --
    /// so removing a variable we also set has to remove OUR assignment too, or
    /// the launch line says "unset this" and "set this" and the second decides.
    @Test func removingAVariableWeSetActuallyRemovesIt() {
        let o = GameOptions()
        o.cxGraphicsBackend = "d3dmetal4"
        o.ue4Hack = true
        o.envVariables = "-MVK_CONFIG_UE4_HACK_ENABLED\n-NAS_DISABLE_UE4_HACK"
        let rendered = getInlineEnvs(from: o)
        #expect(rendered.contains("MVK_CONFIG_UE4_HACK_ENABLED") == false)
        #expect(rendered.contains("NAS_DISABLE_UE4_HACK") == false)
        // and nothing else went with them
        #expect(rendered.contains("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS="))
        #expect(rendered.contains("ROSETTA_ADVERTISE_AVX="))
    }

    /// Removing something we never set is not an error and disturbs nothing.
    @Test func removingSomethingWeDoNotSetChangesNothing() {
        let o = GameOptions()
        o.cxGraphicsBackend = "d3dmetal4"
        let before = getInlineEnvs(from: o)
        o.envVariables = "-SOMETHING_WE_NEVER_WRITE"
        let after = getInlineEnvs(from: o)
        #expect(before.split(separator: " ").sorted() == after.split(separator: " ").sorted())
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
