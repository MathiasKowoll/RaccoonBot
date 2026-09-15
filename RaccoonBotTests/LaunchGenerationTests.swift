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

    // MARK: - Stop pressed while a launch waits for its bottle

    /// A launch takes its generation before it waits for the bottle, and a
    /// Stop pressed inside that wait marks that generation: the launch asks
    /// once the wait is over and does not start the title. Marking is not a
    /// launch, so it stands no teardown down -- not the stop's own, and not
    /// the running session's tracker, which the Epic stop leaves the whole
    /// teardown to.
    @Test func aStopMarksTheGenerationTheBottleIsOn() {
        let steam = bottle("Steam")
        let waiting = LaunchGeneration.shared.launched(bottle: steam)       // Play, then the wait
        #expect(LaunchGeneration.shared.wasStopped(waiting, for: steam) == false)

        LaunchGeneration.shared.stopped(bottle: steam)                      // Stop, inside the wait
        #expect(LaunchGeneration.shared.wasStopped(waiting, for: steam))
        #expect(LaunchGeneration.shared.supersedes(waiting, for: steam) == false,
                "a stop is not a launch, and must not stand a teardown down")
    }

    /// The Stop was about what was running or starting then. Play pressed
    /// after it is a new launch, and that one starts.
    @Test func aLaunchAfterAStopIsNotStopped() {
        let steam = bottle("Steam")
        let before = LaunchGeneration.shared.launched(bottle: steam)
        LaunchGeneration.shared.stopped(bottle: steam)
        let after = LaunchGeneration.shared.launched(bottle: steam)

        #expect(LaunchGeneration.shared.wasStopped(after, for: steam) == false)
        #expect(LaunchGeneration.shared.wasStopped(before, for: steam))
    }

    /// Stop pressed on a bottle nothing has been launched into does not stop
    /// the first launch that follows it.
    @Test func aStopBeforeAnyLaunchStopsNothing() {
        let steam = bottle("Steam")
        LaunchGeneration.shared.stopped(bottle: steam)
        let first = LaunchGeneration.shared.launched(bottle: steam)
        #expect(LaunchGeneration.shared.wasStopped(first, for: steam) == false)
    }

    /// A Stop for one bottle says nothing about a launch waiting for another
    /// -- both launches below are generation one of their own bottle -- and
    /// however a bottle is spelled, it is the same bottle.
    @Test func aStopBelongsToItsOwnBottle() {
        let epic = bottle("Epic"), steam = bottle("Steam")
        let epicLaunch = LaunchGeneration.shared.launched(bottle: epic)
        let steamLaunch = LaunchGeneration.shared.launched(bottle: steam)
        LaunchGeneration.shared.stopped(bottle: steam)

        #expect(LaunchGeneration.shared.wasStopped(epicLaunch, for: epic) == false,
                "a Steam stop must not keep an Epic title from starting")
        #expect(LaunchGeneration.shared.wasStopped(steamLaunch, for: steam))

        let id = UUID().uuidString
        let asURL = "file:///Users/someone/CXPBottles/Steam-\(id)/"
        let asPath = "/Users/someone/CXPBottles/Steam-\(id)"
        let launch = LaunchGeneration.shared.launched(bottle: asURL)
        LaunchGeneration.shared.stopped(bottle: asPath)
        #expect(LaunchGeneration.shared.wasStopped(launch, for: asURL),
                "however it was spelled, it is the bottle that was stopped")
    }

    /// Marked from a button and asked from a launch, so it has to survive
    /// being used from several places at once, and a stop must not spend a
    /// number that belongs to a launch.
    @Test func stoppingSurvivesBeingUsedFromEverywhere() async {
        let shared = bottle("Steam")
        let before = LaunchGeneration.shared.current(for: shared)
        let own = (0..<100).map { bottle("Own\($0)") }

        let answers = await withTaskGroup(of: Bool.self) { group in
            for index in 0..<100 {
                group.addTask { LaunchGeneration.shared.launched(bottle: shared); return true }
                group.addTask { LaunchGeneration.shared.stopped(bottle: shared); return true }
                group.addTask {
                    let launch = LaunchGeneration.shared.launched(bottle: own[index])
                    LaunchGeneration.shared.stopped(bottle: own[index])
                    return LaunchGeneration.shared.wasStopped(launch, for: own[index])
                }
            }
            var all: [Bool] = []
            for await answer in group { all.append(answer) }
            return all
        }

        #expect(answers.count == 300)
        #expect(answers.allSatisfy { $0 })
        #expect(LaunchGeneration.shared.current(for: shared) == before + 100)
        LaunchGeneration.shared.stopped(bottle: shared)
        #expect(LaunchGeneration.shared.wasStopped(before + 100, for: shared))
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

    // MARK: - What became of a launch, told to its tracker

    /// What the window and the bottle were asked to do, in order.
    @MainActor
    private final class Calls {
        var taken: [String] = []
        func record(_ name: String) { taken.append(name) }
    }

    /// Only the first answer counts: a launch says "abandoned" on every way
    /// out, including the one after it has started the title, and that must
    /// not take the start back.
    @Test func aLaunchIsDecidedOnce() async {
        let launch = PendingLaunch()
        #expect(launch.decided == nil)
        launch.decide(.started(generation: 7))
        launch.decide(.abandoned)
        launch.decide(.superseded)
        #expect(launch.decided == .started(generation: 7))
        #expect(await launch.outcome() == .started(generation: 7))
    }

    /// Whoever was waiting when the launch decided hears the answer, and
    /// nobody is left waiting.
    @Test func everyoneWaitingHearsTheDecision() async {
        let launch = PendingLaunch()
        let answers = await withTaskGroup(of: PendingLaunch.Outcome.self) { group in
            for _ in 0..<100 {
                group.addTask { await launch.outcome() }
            }
            group.addTask { launch.decide(.superseded); return .superseded }
            var all: [PendingLaunch.Outcome] = []
            for await answer in group { all.append(answer) }
            return all
        }
        #expect(answers.count == 101)
        #expect(answers.allSatisfy { $0 == .superseded })
    }

    /// The fault: a launch that stood down left its tracker to time out and
    /// then call onTerminate, clearing the playing title and the loader of
    /// whichever session was live by then. The tracker waits for its launch,
    /// and one whose launch started nothing ends with nothing said to the
    /// window. No Steam id and no Epic, so nothing here reads a log or a
    /// bottle.
    @Test @MainActor func aTrackerWhoseLaunchStartedNothingStandsDown() async throws {
        for outcome in [PendingLaunch.Outcome.superseded, .abandoned] {
            let launch = PendingLaunch()
            let calls = Calls()
            let tracker = Task { @MainActor in
                _ = try await getGameTracker(appNames: ["Nothing.exe"], cxAppPath: "", bottle: bottle("Steam"),
                                             onLoad: { _ in calls.record("onLoad") },
                                             onTerminate: { calls.record("onTerminate") },
                                             isNative: false, steamID: nil, steamPath: "", launch: launch)
                calls.record("returned")
            }
            try await Task.sleep(for: .milliseconds(200))
            #expect(calls.taken.isEmpty, "nothing is watched before the launch has decided")

            launch.decide(outcome)
            await #expect(throws: LaunchStoodDown.self) { try await tracker.value }
            #expect(calls.taken.isEmpty, "a launch that started nothing gives its tracker nothing to say")
        }
    }

    /// And one whose launch started the title goes on to watch it.
    @Test @MainActor func aTrackerWhoseLaunchStartedGoesOn() async throws {
        let launch = PendingLaunch()
        let tracker = Task { @MainActor in
            try await getGameTracker(appNames: ["Nothing.exe"], cxAppPath: "", bottle: bottle("Steam"),
                                     onLoad: { _ in }, onTerminate: {},
                                     isNative: false, steamID: nil, steamPath: "", launch: launch)
        }
        launch.decide(.started(generation: 1))
        _ = try await tracker.value
    }

    /// Every way out of a launch before its command tells the tracker. Here the
    /// launch has no bottle, the first of its guards, and nothing is run.
    @Test @MainActor func aLaunchRefusedBeforeItsCommandTellsItsTracker() async throws {
        let launch = PendingLaunch()
        try await launchWindowsGame(id: "1", cxAppPath: "", selectedBottle: "", steamExePath: "",
                                    options: nil, launch: launch)
        #expect(launch.decided == .abandoned)
    }

    // MARK: - The launch's opening: counted before it waits, asked after

    /// Two faults a review found by reading the code, while the launch was
    /// still counted after the wait for the bottle -- neither has been seen
    /// on a live bottle. A grace teardown of the last session could pass its
    /// check inside the wait and send Steam its shutdown under this launch,
    /// and a Stop pressed inside it would close the bottle with a generation
    /// the launch's later count then stood down. Each wait here reads the
    /// counter as it starts: moving the count below either of them fails this.
    @Test @MainActor func aLaunchIsCountedBeforeItFirstWaits() async {
        let steam = bottle("Steam")
        let before = LaunchGeneration.shared.current(for: steam)
        let launch = PendingLaunch()
        var seen: [Int] = []
        let generation = await readyBottleForLaunch(
            id: "1", bottle: steam, bottleURL: URL(string: steam)!, hidTraceEnabled: false, launch: launch,
            settle: { _ in seen.append(LaunchGeneration.shared.current(for: steam)); return .notRunning },
            clearOrphans: { _ in seen.append(LaunchGeneration.shared.current(for: steam)) })

        #expect(generation == before + 1)
        #expect(seen == [before + 1, before + 1])
        #expect(launch.decided == nil, "a launch that goes ahead is decided by its command, not here")
    }

    /// Stop pressed inside the wait, through the function every Stop button
    /// calls: the launch starts nothing, clears nothing, and its tracker is
    /// told.
    @Test @MainActor func aStopDuringTheWaitStartsNothing() async {
        let steam = bottle("Steam")
        let launch = PendingLaunch()
        var cleared = false
        let generation = await readyBottleForLaunch(
            id: "1", bottle: steam, bottleURL: URL(string: steam)!, hidTraceEnabled: false, launch: launch,
            settle: { _ in
                stopPressed(isEpic: false, selectedBottle: steam)
                return .stillUp(afterSeconds: 20, names: ["wineserver"])
            },
            clearOrphans: { _ in cleared = true })

        #expect(generation == nil)
        #expect(cleared == false, "a bottle a Stop is closing is not this launch's to clear")
        #expect(launch.decided == .abandoned)
    }

    /// Clearing orphans waits for them to end, and a Stop pressed then is
    /// asked about too.
    @Test @MainActor func aStopWhileOrphansAreClearedStartsNothing() async {
        let steam = bottle("Steam")
        let launch = PendingLaunch()
        let generation = await readyBottleForLaunch(
            id: "1", bottle: steam, bottleURL: URL(string: steam)!, hidTraceEnabled: false, launch: launch,
            settle: { _ in .notRunning },
            clearOrphans: { _ in stopPressed(isEpic: false, selectedBottle: steam) })

        #expect(generation == nil)
        #expect(launch.decided == .abandoned)
    }

    /// Play pressed again inside the wait: that launch has its own tracker and
    /// loader, so this one is superseded rather than abandoned, and leaves the
    /// bottle to it.
    @Test @MainActor func aPlayDuringTheWaitTakesTheBottle() async {
        let steam = bottle("Steam")
        let launch = PendingLaunch()
        var cleared = false
        let generation = await readyBottleForLaunch(
            id: "1", bottle: steam, bottleURL: URL(string: steam)!, hidTraceEnabled: false, launch: launch,
            settle: { _ in
                LaunchGeneration.shared.launched(bottle: steam)
                return .notRunning
            },
            clearOrphans: { _ in cleared = true })

        #expect(generation == nil)
        #expect(cleared == false)
        #expect(launch.decided == .superseded)
    }

    /// A Stop pressed before this Play, or for another bottle, was not about
    /// this launch, and it goes ahead.
    @Test @MainActor func aStopThatWasNotAboutThisLaunchLetsItGoAhead() async {
        let steam = bottle("Steam"), other = bottle("Other")
        stopPressed(isEpic: false, selectedBottle: steam)
        let launch = PendingLaunch()
        var cleared = 0
        let generation = await readyBottleForLaunch(
            id: "1", bottle: steam, bottleURL: URL(string: steam)!, hidTraceEnabled: false, launch: launch,
            settle: { _ in
                stopPressed(isEpic: false, selectedBottle: other)
                return .cameDown(afterSeconds: 3)
            },
            clearOrphans: { _ in cleared += 1 })

        #expect(generation == LaunchGeneration.shared.current(for: steam))
        #expect(cleared == 1)
        #expect(launch.decided == nil)
    }

    /// The bottle a Stop acts on is the bottle it marks.
    @Test @MainActor func stopPressedMarksTheBottleItReturns() {
        let steam = bottle("Steam")
        let running = LaunchGeneration.shared.launched(bottle: steam)
        #expect(stopPressed(isEpic: false, selectedBottle: steam) == steam)
        #expect(LaunchGeneration.shared.wasStopped(running, for: steam))
        #expect(LaunchGeneration.shared.supersedes(running, for: steam) == false)
    }

    // MARK: - A teardown asks again after each of its waits

    /// Runs the teardown on recorded steps, launching into the bottle during
    /// the step named `launchDuring`.
    @MainActor
    private func teardown(isEpic: Bool, in bottle: String, calls: Calls,
                          steamInBottle: Bool = false, launchDuring: String? = nil) async throws -> Bool {
        let generation = LaunchGeneration.shared.current(for: bottle)
        func step(_ name: String) {
            calls.record(name)
            if name == launchDuring { LaunchGeneration.shared.launched(bottle: bottle) }
        }
        return try await SessionTeardown.run(
            isEpic: isEpic, generation: generation, bottle: bottle, reason: "a test",
            waitForEpicLauncher: { step("epic launcher settles") },
            waitForCloudSync: { step("cloud sync") },
            steamIsInBottle: { step("is steam here"); return steamInBottle },
            quitEpic: { step("quit epic") },
            quitSteam: { step("quit steam") },
            closeBottle: { step("close " + $0.joined(separator: "+")) })
    }

    /// A fault found by reading the code, present before the wait for the
    /// bottle existed and not seen on a live bottle: the check came once,
    /// before a cloud sync wait of up to a minute, so a game launched inside
    /// that wait would have Steam sent its shutdown.
    @Test @MainActor func aLaunchDuringTheCloudSyncIsNotSentSteamsShutdown() async throws {
        let calls = Calls()
        #expect(try await teardown(isEpic: false, in: bottle("Steam"), calls: calls,
                                   launchDuring: "cloud sync") == false)
        #expect(calls.taken == ["cloud sync"])
    }

    /// The same for the Epic launcher's own wait.
    @Test @MainActor func aLaunchWhileTheEpicLauncherSettlesIsNotSentAnything() async throws {
        let calls = Calls()
        #expect(try await teardown(isEpic: true, in: bottle("Epic"), calls: calls, steamInBottle: true,
                                   launchDuring: "epic launcher settles") == false)
        #expect(calls.taken == ["epic launcher settles"])
    }

    /// Asking the Epic launcher to leave is a wait of its own, and a Steam in
    /// the same bottle is asked only if nothing was launched during it.
    @Test @MainActor func aLaunchWhileTheEpicLauncherLeavesSparesSteam() async throws {
        let calls = Calls()
        #expect(try await teardown(isEpic: true, in: bottle("Epic"), calls: calls, steamInBottle: true,
                                   launchDuring: "quit epic") == false)
        #expect(calls.taken == ["epic launcher settles", "quit epic", "is steam here"])
    }

    /// With nothing launched, every step is taken, in order, and the bottle is
    /// closed waiting for exactly the clients that were asked to leave.
    @Test @MainActor func withNothingLaunchedEveryStepIsTakenInOrder() async throws {
        let steam = Calls()
        #expect(try await teardown(isEpic: false, in: bottle("Steam"), calls: steam))
        #expect(steam.taken == ["cloud sync", "quit steam", "close steam"])

        let epicWithSteam = Calls()
        #expect(try await teardown(isEpic: true, in: bottle("Epic"), calls: epicWithSteam, steamInBottle: true))
        #expect(epicWithSteam.taken == ["epic launcher settles", "quit epic", "is steam here", "quit steam", "close epic+steam"])

        let epicAlone = Calls()
        #expect(try await teardown(isEpic: true, in: bottle("Epic"), calls: epicAlone))
        #expect(epicAlone.taken == ["epic launcher settles", "quit epic", "is steam here", "close epic"])
    }
}
