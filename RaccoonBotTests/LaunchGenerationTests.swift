//
//  LaunchGenerationTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Serialised because the thing under test is a process-wide singleton.
///
/// Each case now works in a bottle of its own, which is most of what used to
/// make them collide -- but the counter behind an unidentifiable bottle is
/// still shared by everything, so the suite stays serialised rather than
/// relying on nobody ever testing that path again.
@Suite("A teardown must not arrive in the next session", .serialized)
struct LaunchGenerationTests {

    /// A bottle nothing else in the suite touches.
    private func bottle(_ name: String) -> String {
        "file:///Users/someone/Library/Application%20Support/RaccoonBot/CXPBottles/\(name)-\(UUID().uuidString)/"
    }

    /// The fault this exists for, in the order it happened -- and it happened
    /// in ONE bottle, which is why counting per bottle does not weaken it.
    ///
    ///   22:20:39  Ninja Gaiden 3 starts
    ///   22:21:57  it exits, so a teardown is due in two minutes
    ///   22:23:57  the teardown begins
    ///   22:24:11  Sigma is launched and its Steam starts
    ///   22:24:25  the teardown, still working, kills it
    @Test func aLaunchDuringATeardownSupersedesItInTheSameBottle() {
        let steam = bottle("Steam")
        let generation = LaunchGeneration.shared.current(for: steam)
        #expect(LaunchGeneration.shared.supersedes(generation, for: steam) == false)

        LaunchGeneration.shared.launched(bottle: steam)          // Sigma is launched
        #expect(LaunchGeneration.shared.supersedes(generation, for: steam),
                "the teardown should know it is about a session that has ended")
    }

    /// The defect this replaced. Play an Epic title, start a Steam one in a
    /// different prefix while it runs, and the Epic teardown gave up for
    /// good: that bottle was never closed and its cloud save never waited
    /// for. A session in one bottle says nothing about a session in another.
    @Test func aLaunchInAnotherBottleDoesNotSupersedeIt() {
        let epic = bottle("Epic")
        let steam = bottle("Steam")
        let generation = LaunchGeneration.shared.current(for: epic)

        LaunchGeneration.shared.launched(bottle: steam)
        #expect(LaunchGeneration.shared.supersedes(generation, for: epic) == false,
                "a Steam launch must not cancel an Epic teardown")
        #expect(LaunchGeneration.shared.supersedes(
            LaunchGeneration.shared.current(for: steam) - 1, for: steam),
                "while the bottle it happened in does know about it")
    }

    /// The safety argument for counting per bottle at all. The same prefix is
    /// written as a file:// URL in one place and a plain path in another,
    /// with or without a trailing slash; if those counted separately, a
    /// teardown would compare a counter nobody had bumped, read "nothing has
    /// been launched since", and kill a game that was running.
    @Test func theSameBottleWrittenDifferentlyIsTheSameBottle() {
        let id = UUID().uuidString
        let withSlash = "file:///Users/someone/CXPBottles/Steam-\(id)/"
        let withoutSlash = "file:///Users/someone/CXPBottles/Steam-\(id)"
        let asPath = "/Users/someone/CXPBottles/Steam-\(id)"

        #expect(LaunchGeneration.key(for: withSlash) == LaunchGeneration.key(for: withoutSlash))
        #expect(LaunchGeneration.key(for: withSlash) == LaunchGeneration.key(for: asPath))

        let generation = LaunchGeneration.shared.current(for: withSlash)
        LaunchGeneration.shared.launched(bottle: asPath)
        #expect(LaunchGeneration.shared.supersedes(generation, for: withoutSlash),
                "however it was spelled, it is the bottle that was launched in")
    }

    /// Two bottles of the same name under different roots are two bottles --
    /// this machine has exactly that, and macOS does not tell them apart by
    /// case either.
    @Test func sameNameUnderADifferentRootIsADifferentBottle() {
        let id = UUID().uuidString
        let ours = "file:///Users/someone/RaccoonBot/CXPBottles/Steam-\(id)/"
        let theirs = "file:///Users/someone/CrossOver/Bottles/Steam-\(id)/"
        #expect(LaunchGeneration.key(for: ours) != LaunchGeneration.key(for: theirs))

        let generation = LaunchGeneration.shared.current(for: ours)
        LaunchGeneration.shared.launched(bottle: theirs)
        #expect(LaunchGeneration.shared.supersedes(generation, for: ours) == false)
    }

    /// A bottle that cannot be identified is answered from the counter every
    /// launch bumps, so any launch supersedes it. That is the conservative
    /// direction: a bottle left standing rather than one torn down on a guess.
    @Test func anUnidentifiableBottleIsSupersededByAnyLaunch() {
        #expect(LaunchGeneration.key(for: "") .isEmpty)
        #expect(LaunchGeneration.key(for: "   ").isEmpty)

        let generation = LaunchGeneration.shared.current(for: "")
        LaunchGeneration.shared.launched(bottle: bottle("Somewhere"))
        #expect(LaunchGeneration.shared.supersedes(generation, for: ""),
                "not knowing which bottle is a reason to refuse, not to proceed")
    }

    @Test func withoutALaunchNothingIsSuperseded() {
        let steam = bottle("Steam")
        let generation = LaunchGeneration.shared.current(for: steam)
        #expect(LaunchGeneration.shared.supersedes(generation, for: steam) == false)
        #expect(LaunchGeneration.shared.supersedes(generation, for: steam) == false)
    }

    @Test func everyLaunchGetsItsOwnGeneration() {
        let steam = bottle("Steam")
        let first = LaunchGeneration.shared.launched(bottle: steam)
        let second = LaunchGeneration.shared.launched(bottle: steam)
        #expect(second == first + 1)
        #expect(LaunchGeneration.shared.supersedes(first, for: steam))
        #expect(LaunchGeneration.shared.supersedes(second, for: steam) == false)
    }

    /// It is read from a workspace notification and written from a launch, so
    /// it has to survive being used from several places at once.
    @Test func countingSurvivesBeingUsedFromEverywhere() async {
        let steam = bottle("Steam")
        let before = LaunchGeneration.shared.current(for: steam)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask { LaunchGeneration.shared.launched(bottle: steam) }
            }
        }
        #expect(LaunchGeneration.shared.current(for: steam) == before + 200)
    }

    /// And two bottles counted at once do not spend each other's numbers.
    @Test func twoBottlesCountedAtOnceKeepTheirOwnNumbers() async {
        let a = bottle("A"), b = bottle("B")
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { LaunchGeneration.shared.launched(bottle: a) }
                group.addTask { LaunchGeneration.shared.launched(bottle: b) }
            }
        }
        #expect(LaunchGeneration.shared.current(for: a) == 100)
        #expect(LaunchGeneration.shared.current(for: b) == 100)
    }
}
