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
            id: "1", bottle: steam, bottleURL: URL(string: steam)!, cxAppPath: "", hidTraceEnabled: false, launch: launch,
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
            id: "1", bottle: steam, bottleURL: URL(string: steam)!, cxAppPath: "", hidTraceEnabled: false, launch: launch,
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
            id: "1", bottle: steam, bottleURL: URL(string: steam)!, cxAppPath: "", hidTraceEnabled: false, launch: launch,
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
            id: "1", bottle: steam, bottleURL: URL(string: steam)!, cxAppPath: "", hidTraceEnabled: false, launch: launch,
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
            id: "1", bottle: steam, bottleURL: URL(string: steam)!, cxAppPath: "", hidTraceEnabled: false, launch: launch,
            settle: { _ in
                stopPressed(isEpic: false, selectedBottle: other)
                return .cameDown(afterSeconds: 3)
            },
            clearOrphans: { _ in cleared += 1 })

        #expect(generation == LaunchGeneration.shared.current(for: steam))
        #expect(cleared == 1)
        #expect(launch.decided == nil)
    }

    /// The bottle a Stop acts on is the bottle it marks, and the generation it
    /// hands back is the one it marked.
    @Test @MainActor func stopPressedMarksTheBottleItReturns() {
        let steam = bottle("Steam")
        let running = LaunchGeneration.shared.launched(bottle: steam)
        let press = stopPressed(isEpic: false, selectedBottle: steam)
        #expect(press.bottle == steam)
        #expect(press.generation == running)
        // Compared, not equated: another suite launching in bottles of its
        // own moves the count of every launch at any moment.
        #expect(press.launchesAnywhere <= LaunchGeneration.shared.launchesAnywhere())
        #expect(LaunchGeneration.shared.wasStopped(running, for: steam))
        #expect(LaunchGeneration.shared.supersedes(running, for: steam) == false)
    }

    /// A fault found by reading the code, not seen live: a Stop cleared the
    /// playing title, or the toolbar's loader, once its whole teardown had
    /// returned, and a title launched in another bottle during those minutes
    /// lost them. Nothing launched anywhere since the press is what a Stop's
    /// clearing is conditioned on.
    @Test @MainActor func aStopOwnsTheWindowOnlyUntilSomethingIsLaunchedAnywhere() {
        let steam = bottle("Steam"), other = bottle("Other")
        let press = stopPressed(isEpic: false, selectedBottle: steam)
        #expect(press.ownsTheWindow(launchesNow: press.launchesAnywhere, playsNow: press.playsPressed))
        LaunchGeneration.shared.launched(bottle: other)
        #expect(press.ownsTheWindow(launchesNow: LaunchGeneration.shared.launchesAnywhere(),
                                    playsNow: press.playsPressed) == false)

        let again = stopPressed(isEpic: false, selectedBottle: steam)
        LaunchGeneration.shared.launched(bottle: steam)
        #expect(again.ownsTheWindow(launchesNow: LaunchGeneration.shared.launchesAnywhere(),
                                    playsNow: again.playsPressed) == false)
    }

    /// A fault found by reading the code, not seen live: a launch is counted
    /// once its task reaches readyBottleForLaunch, and its Play puts the
    /// loader up at the press, before that. The toolbar's Stop compared the
    /// count alone, so a Play pressed in between had its loader taken down
    /// while it started. The launch count is held still here: the press alone
    /// takes the window.
    @Test @MainActor func aPlayPressedButNotYetCountedTakesTheWindowFromAStop() {
        let press = stopPressed(isEpic: false, selectedBottle: bottle("Steam"))
        let globals = LibraryPageGlobals()
        globals.raiseLoaderForPlay()
        #expect(globals.isLaunchingGame)
        #expect(press.ownsTheWindow(launchesNow: press.launchesAnywhere,
                                    playsNow: LaunchGeneration.shared.playsPressed()) == false)
    }

    /// A fault found by reading the code, not seen live: a title's tracker
    /// cleared the loader and the playing title whoever they belonged to, and
    /// a bottle can hold two titles. Play on B while A runs launches into A's
    /// bottle; A exiting took down B's loader while B started, or cleared B
    /// once it was playing.
    @Test @MainActor func aTitleEndingClearsOnlyTheWindowStillItsOwn() {
        let globals = LibraryPageGlobals()
        // A is pressed and seen running, and its loader comes down.
        let a = globals.raiseLoaderForPlay()
        globals.playingID = "A"
        globals.setLoader(state: false)
        // B is pressed while A plays, and is still starting when A exits.
        let b = globals.raiseLoaderForPlay()
        globals.titleEnded("A", raisedBy: a)
        #expect(globals.isLaunchingGame, "the loader is B's")
        #expect(globals.playingID == nil, "A is over")
        // B is seen running; A's tracker saying A is over again clears
        // nothing of B's.
        globals.playingID = "B"
        globals.titleEnded("A", raisedBy: a)
        #expect(globals.playingID == "B")
        #expect(globals.isLaunchingGame)
        // B's own end, with no Play since, clears the window as it always did.
        // A Stop pressed in between is not a Play.
        stopPressed(isEpic: false, selectedBottle: bottle("Steam"))
        globals.titleEnded("B", raisedBy: b)
        #expect(globals.isLaunchingGame == false)
        #expect(globals.playingID == nil)
    }

    // MARK: - Never a Steam that is not running

    /// A fault found by reading the code: quitSteam scanned for steam.exe and
    /// sent "Steam.exe -shutdown" whatever the scan found, and the teardown
    /// after a custom title, which never started Steam, called it. With no
    /// Steam running that request starts one -- 25 such starts in the Steam
    /// bottle's bootstrap_log.txt. Nothing is sent here: `send` records.
    @Test @MainActor func onlyASteamInTheBottleIsAskedToLeave() async throws {
        let steam = bottle("Steam")
        var sent: [String] = []

        try await quitSteam(cxAppPath: "/nowhere", bottle: steam, isNative: false,
                            scan: { _ in [BottleProcesses.Running(pid: 31, name: "steamwebhelper.exe")] },
                            send: { sent.append($0) })
        #expect(sent.isEmpty, "a helper Steam left behind is not a Steam")
        #expect(SteamShutdowns.shared.askedToLeave(in: steam).isEmpty)

        var looked = false
        try await quitSteam(cxAppPath: "/nowhere", bottle: "Steam", isNative: false,
                            scan: { _ in looked = true; return [BottleProcesses.Running(pid: 30, name: "steam.exe")] },
                            send: { sent.append($0) })
        #expect(looked == false)
        #expect(sent.isEmpty, "a bottle that cannot be looked in is not asked")

        try await quitSteam(cxAppPath: "/nowhere", bottle: steam, isNative: false,
                            scan: { _ in [BottleProcesses.Running(pid: 30, name: "Steam.exe"),
                                          BottleProcesses.Running(pid: 31, name: "steamwebhelper.exe")] },
                            send: { sent.append($0) })
        #expect(sent.count == 1)
        #expect(sent.first?.hasSuffix("-shutdown") == true)
        #expect(SteamShutdowns.shared.askedToLeave(in: steam).map(\.pid) == [30])
    }

    // MARK: - A tracker of a session taken over says nothing more

    /// Polls `condition` until it holds or `seconds` have passed.
    @MainActor
    private func eventually(within seconds: Double = 10, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    /// A fault found by reading the code, not seen live. A restarted Steam
    /// writes "Client version:" to gameprocess_log.txt, which empties the
    /// process log's record, and the last session's watch read that as its
    /// game running again: onLoad marked the old title playing and dropped
    /// the newer launch's loader. A launch that closes the session left open
    /// restarts Steam every time. A session taken over by a newer launch or
    /// by a Stop stands down instead; one that was not still reads it as
    /// before, and is what says the watches have read the line.
    @Test @MainActor func aSteamRestartDoesNotMarkATakenOverSessionPlaying() async throws {
        let appID = 4242
        struct Watched {
            let bottle: String
            let log: URL
            let calls: Calls
            let launch: PendingLaunch
            let tracker: Task<Void, Error>
        }
        var watched: [Watched] = []
        for name in ["NotTakenOver", "Launched", "Stopped"] {
            let steamPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("steam-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: steamPath.appendingPathComponent("logs"), withIntermediateDirectories: true)
            let steamBottle = bottle(name)
            let calls = Calls()
            let launch = PendingLaunch()
            // No log yet, so the process log reads it from its start once
            // it is written.
            let tracker = Task { @MainActor in
                _ = try await getGameTracker(appNames: ["Game.exe"], cxAppPath: "", bottle: steamBottle,
                                             onLoad: { _ in calls.record("onLoad") },
                                             onTerminate: { calls.record("onTerminate") },
                                             isNative: false, steamID: appID,
                                             steamPath: steamPath.path(percentEncoded: false), launch: launch)
            }
            watched.append(Watched(bottle: steamBottle, log: steamPath.appendingPathComponent("logs/gameprocess_log.txt"),
                                   calls: calls, launch: launch, tracker: tracker))
        }
        defer {
            for session in watched {
                session.tracker.cancel()
                try? FileManager.default.removeItem(at: session.log.deletingLastPathComponent().deletingLastPathComponent())
            }
        }
        // The trackers open their logs before they wait for the launch.
        try await Task.sleep(for: .milliseconds(200))
        for session in watched {
            session.launch.decide(.started(generation: LaunchGeneration.shared.launched(bottle: session.bottle)))
            try Data(("[2026-09-15 00:53:40] AppID \(appID) adding PID 100 as a tracked process \"C:\\Games\\Game.exe\"\r\n"
                      + "[2026-09-15 00:54:37] AppID \(appID) no longer tracking PID 100, exit code 0\r\n").utf8)
                .write(to: session.log)
        }
        #expect(await eventually { watched.allSatisfy { $0.calls.taken == ["onTerminate"] } })

        LaunchGeneration.shared.launched(bottle: watched[1].bottle)
        LaunchGeneration.shared.stopped(bottle: watched[2].bottle)
        for session in watched {
            let handle = try FileHandle(forWritingTo: session.log)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("[2026-09-15 00:55:12] Client version: 1757880000\r\n".utf8))
            try handle.close()
        }
        #expect(await eventually { watched[0].calls.taken == ["onTerminate", "onLoad"] })
        // Two more looks of a watch that polls every second.
        try await Task.sleep(for: .milliseconds(2500))
        #expect(watched[1].calls.taken == ["onTerminate"], "a newer launch took the bottle")
        #expect(watched[2].calls.taken == ["onTerminate"], "Stop was pressed for the bottle")
    }

    /// A temporary directory standing in for a bottle, with no wineserver:
    /// nothing is ever running in it.
    private func epicBottle() throws -> (bottle: String, log: URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Epic-\(UUID().uuidString)")
        let log = EpicLauncherLogWatcher.logURL(inBottleAt: directory)
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (directory.absoluteString, log)
    }

    @MainActor
    private func epicTracker(_ bottle: String, calls: Calls, patience: TimeInterval = 180) async throws {
        let launch = PendingLaunch()
        launch.decide(.started(generation: LaunchGeneration.shared.launched(bottle: bottle)))
        _ = try await getGameTracker(appNames: ["AlanWake2.exe"], cxAppPath: "", bottle: bottle,
                                     onLoad: { calls.record("onLoad " + $0) },
                                     onTerminate: { calls.record("onTerminate") },
                                     isNative: false, steamID: nil, steamPath: "", isEpic: true, launch: launch,
                                     epicStartPatience: patience)
    }

    /// A fault found by reading the code, not seen live: the Epic tracker's
    /// wait for its title checked neither a newer launch nor a Stop, and
    /// after a Stop had closed the bottle it claimed the next game started
    /// there. The launcher's line reaches both watches; one stands down.
    @Test @MainActor func anEpicLaunchTakenOverClaimsNoGameStartedAfterIt() async throws {
        let notTakenOver = try epicBottle(), stopped = try epicBottle()
        defer {
            for bottle in [notTakenOver, stopped] {
                try? FileManager.default.removeItem(at: URL(string: bottle.bottle)!)
            }
        }
        let quiet = Calls(), stoppedCalls = Calls()
        try await epicTracker(notTakenOver.bottle, calls: quiet)
        try await epicTracker(stopped.bottle, calls: stoppedCalls)
        LaunchGeneration.shared.stopped(bottle: stopped.bottle)
        let line = "[2026.09.03-02.11.30:935][813]LogLauncher: FCommunityPortalLaunchAppTask: Launching app 'Z:/Games/AlanWake2/AlanWake2.exe' with commandline ''\r\n"
        for bottle in [notTakenOver, stopped] {
            try Data(line.utf8).write(to: bottle.log)
        }
        #expect(await eventually { quiet.taken == ["onLoad AlanWake2.exe"] })
        // Three more looks of a watch that looks every half second.
        try await Task.sleep(for: .milliseconds(1500))
        #expect(stoppedCalls.taken.isEmpty)
    }

    /// And a Stop before the launcher's time is up leaves the window to the
    /// Stop: the tracker does not release it, nor begin waiting on the
    /// launcher for half an hour.
    @Test @MainActor func aStopBeforeTheLauncherStartsAnythingEndsTheEpicWatch() async throws {
        let epic = bottle("Epic")
        let calls = Calls()
        try await epicTracker(epic, calls: calls, patience: 1)
        LaunchGeneration.shared.stopped(bottle: epic)
        try await Task.sleep(for: .milliseconds(2500))
        #expect(calls.taken.isEmpty)
        #expect(AwaitedTitleStarts.shared.awaited(in: epic).isEmpty)
    }

    /// A fault found by reading the code, not seen live: past the launcher's
    /// time the watch went on for half an hour with the launcher's start
    /// awaited, and only a newer launch ended that, never a Stop. So a
    /// launch into the bottle the Stop had closed would not close a launcher
    /// opened there since.
    @Test @MainActor func aStopEndsTheEpicLaunchersAwaitedStart() async throws {
        let epic = bottle("Epic")
        let calls = Calls()
        try await epicTracker(epic, calls: calls, patience: 0.5)
        #expect(await eventually { AwaitedTitleStarts.shared.awaited(in: epic) == [.epic] })
        #expect(calls.taken == ["onTerminate"])
        LaunchGeneration.shared.stopped(bottle: epic)
        // The watch looks every two seconds.
        #expect(await eventually(within: 6) { AwaitedTitleStarts.shared.awaited(in: epic).isEmpty })
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
