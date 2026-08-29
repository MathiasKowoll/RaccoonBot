//
//  LaunchGenerationTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

@Suite("A teardown must not arrive in the next session")
struct LaunchGenerationTests {

    /// The fault this exists for, in the order it happened.
    ///
    ///   22:20:39  Ninja Gaiden 3 starts
    ///   22:21:57  it exits, so a teardown is due in two minutes
    ///   22:23:57  the teardown begins
    ///   22:24:11  Sigma is launched and its Steam starts
    ///   22:24:25  the teardown, still working, kills it
    @Test func aLaunchDuringATeardownSupersedesIt() {
        let generation = LaunchGeneration.shared.current
        #expect(LaunchGeneration.shared.supersedes(generation) == false)

        LaunchGeneration.shared.launched()          // Sigma is launched
        #expect(LaunchGeneration.shared.supersedes(generation),
                "the teardown should know it is about a session that has ended")
    }

    @Test func withoutALaunchNothingIsSuperseded() {
        let generation = LaunchGeneration.shared.current
        #expect(LaunchGeneration.shared.supersedes(generation) == false)
        #expect(LaunchGeneration.shared.supersedes(generation) == false)
    }

    @Test func everyLaunchGetsItsOwnGeneration() {
        let first = LaunchGeneration.shared.launched()
        let second = LaunchGeneration.shared.launched()
        #expect(second == first + 1)
        #expect(LaunchGeneration.shared.supersedes(first))
        #expect(LaunchGeneration.shared.supersedes(second) == false)
    }

    /// It is read from a workspace notification and written from a launch, so
    /// it has to survive being used from several places at once.
    @Test func countingSurvivesBeingUsedFromEverywhere() async {
        let before = LaunchGeneration.shared.current
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask { LaunchGeneration.shared.launched() }
            }
        }
        #expect(LaunchGeneration.shared.current == before + 200)
    }
}
