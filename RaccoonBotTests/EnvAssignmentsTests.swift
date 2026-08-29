//
//  EnvAssignmentsTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

@Suite("Repairing what somebody typed into the environment box")
struct EnvAssignmentsTests {

    /// The one that cost an evening. Pasted out of a README, quotes and spaces
    /// and all, and it made Ninja Gaiden Sigma unlaunchable with no message
    /// beyond one line of env's own complaint.
    @Test func theLineThatBrokeNinjaGaidenSigma() {
        let typed = #""GST_PLUGIN_PATH" = "/Users/mathias/Library/Application Support/MacGameVideoFix/gst-codecs/CrossOver/x86_64/gstreamer-1.0""#
        #expect(EnvAssignments.normalised(typed)
                == #"GST_PLUGIN_PATH="/Users/mathias/Library/Application Support/MacGameVideoFix/gst-codecs/CrossOver/x86_64/gstreamer-1.0""#)
    }

    /// What already worked must keep working, untouched.
    @Test func aPlainAssignmentIsLeftAlone() {
        #expect(EnvAssignments.normalised("WINEDLLOVERRIDES=dbghelp=n,b")
                == "WINEDLLOVERRIDES=dbghelp=n,b")
    }

    @Test func nothingTypedIsNothingWritten() {
        #expect(EnvAssignments.normalised("") == "")
        #expect(EnvAssignments.normalised("   ") == "")
    }

    @Test(arguments: [
        ("A = 1", "A=1"),
        ("A =1", "A=1"),
        ("A= 1", "A=1"),
        ("  A=1  ", "A=1"),
        (#"A = "x y""#, #"A="x y""#),
        (#""A"="1""#, "A=1"),
        ("'A' = '1'", "A=1"),
    ])
    func spacingAndQuotingAreRepaired(_ c: (typed: String, wanted: String)) {
        #expect(EnvAssignments.normalised(c.typed) == c.wanted)
    }

    @Test func severalAssignmentsSurviveTogether() {
        #expect(EnvAssignments.normalised(#"A=1 B = "two words" C=3"#)
                == #"A=1 B="two words" C=3"#)
    }

    /// A value that is itself an assignment, which wine's own variables are.
    @Test func anEqualsInsideTheValueIsPartOfTheValue() {
        #expect(EnvAssignments.normalised("WINEDLLOVERRIDES=d3d11=n,b;dxgi=n,b")
                == "WINEDLLOVERRIDES=d3d11=n,b;dxgi=n,b")
    }

    /// Something that cannot be an assignment is dropped rather than passed to
    /// env, where it would be taken for the program to run and end the launch.
    @Test(arguments: ["justaword", "9LIVES=1", "not-a-name=1", "=novalue"])
    func whatCannotBeRepairedIsDropped(_ typed: String) {
        #expect(EnvAssignments.normalised(typed) == "")
    }

    /// And dropping one must not take the good ones with it.
    @Test func oneBadEntryDoesNotSpoilTheRest() {
        #expect(EnvAssignments.normalised("A=1 rubbish B=2") == "A=1 B=2")
    }

    /// An empty value is legitimate -- it is how a variable is cleared.
    @Test func anEmptyValueIsKept() {
        #expect(EnvAssignments.normalised("WINEDEBUG=") == #"WINEDEBUG="""#)
    }
}
