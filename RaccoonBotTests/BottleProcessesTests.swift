//
//  BottleProcessesTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

@Suite("Knowing which processes belong to which bottle")
struct BottleProcessesTests {

    /// The identity comes from the bottle, not from whoever launched into it.
    /// That is what makes leftovers from another CrossOver -- or from an older
    /// run of this one -- findable: they all land in the same directory.
    @Test func theServerDirectoryComesFromTheBottleItself() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bottle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let server = try #require(BottleProcesses.serverDirectory(ofBottleAt: dir))
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        let device = try #require(attrs[.systemNumber] as? Int)
        let inode = try #require(attrs[.systemFileNumber] as? Int)

        #expect(server.lastPathComponent
                == "server-\(String(device, radix: 16))-\(String(inode, radix: 16))")
        #expect(server.deletingLastPathComponent().lastPathComponent == ".wine-\(getuid())")
    }

    /// A process that arrives while the teardown is waiting is not something
    /// that "ignored the request" -- it never got one.
    ///
    /// The one that arrives in practice is a fix installer: it starts a
    /// short-lived wineserver to run `reg.exe add`, and it is allowed to,
    /// because the guard forbidding a write while the bottle is busy is a
    /// one-shot check made before `wineserver -k` emptied the bottle. Killing
    /// it mid-write does not crash anything: `reg.exe` has already returned 0,
    /// so the fix is recorded as applied while some of its keys never reached
    /// user.reg.
    ///
    /// Signals only `/bin/sleep` processes this test started itself. No wine,
    /// no CrossOver, no game, no installer.
    /// A process that arrives while the teardown is waiting never received the
    /// request it is about to be killed for ignoring.
    ///
    /// The one that arrives in practice is a fix installer: it starts a
    /// short-lived wineserver to run `reg.exe add`, and it is allowed to,
    /// because the guard forbidding a write while the bottle is busy is a
    /// one-shot check made before `wineserver -k` emptied the bottle. Killing
    /// it mid-write does not crash anything -- `reg.exe` has already returned
    /// 0, so the fix is recorded as applied while some of its keys never
    /// reached user.reg.
    @Test func onlyWhatWasCondemnedIsKilled() {
        let doomed = [BottleProcesses.Running(pid: 100, name: "Game.exe"),
                      BottleProcesses.Running(pid: 101, name: "wineserver")]
        let now = [BottleProcesses.Running(pid: 100, name: "Game.exe"),      // ignored the request
                   BottleProcesses.Running(pid: 300, name: "wineserver")]    // the installer's
        #expect(BottleProcesses.stillThere(now, of: doomed).map(\.pid) == [100])
    }

    /// A pid the system reused between the two scans is a different process
    /// wearing an old number, and it is not under sentence.
    @Test func aReusedPidIsNotCondemnedForWhoeverHeldItBefore() {
        let doomed = [BottleProcesses.Running(pid: 100, name: "Game.exe")]
        let now = [BottleProcesses.Running(pid: 100, name: "wineserver")]
        #expect(BottleProcesses.stillThere(now, of: doomed).isEmpty)
    }

    /// Everything that was there and stayed is still killed -- the point is to
    /// narrow the second sweep, not to stop it working.
    @Test func whatWasThereAndStayedIsStillEnded() {
        let doomed = [BottleProcesses.Running(pid: 1, name: "a.exe"),
                      BottleProcesses.Running(pid: 2, name: "b.exe")]
        #expect(BottleProcesses.stillThere(doomed, of: doomed).map(\.pid) == [1, 2])
    }

    /// And a bottle that emptied itself during the grace leaves nothing to do.
    @Test func aBottleThatWentQuietLeavesNothing() {
        let doomed = [BottleProcesses.Running(pid: 1, name: "a.exe")]
        #expect(BottleProcesses.stillThere([], of: doomed).isEmpty)
    }

    /// Two bottles never share a server directory, which is why ending one
    /// cannot reach the other.
    @Test func twoBottlesGetDifferentDirectories() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let a = base.appendingPathComponent("bottle-a-\(UUID().uuidString)")
        let b = base.appendingPathComponent("bottle-b-\(UUID().uuidString)")
        for d in [a, b] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }

        #expect(BottleProcesses.serverDirectory(ofBottleAt: a)
                != BottleProcesses.serverDirectory(ofBottleAt: b))
    }

    @Test func aBottleThatIsNotThereHasNoDirectory() {
        #expect(BottleProcesses.serverDirectory(
            ofBottleAt: URL(fileURLWithPath: "/nowhere/at/all")) == nil)
    }

    /// A bottle with no server directory has nothing running, and asking must
    /// not be an error.
    @Test func aBottleWithNoServerIsQuiet() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bottle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(BottleProcesses.running(inBottleAt: dir).isEmpty)
        #expect(BottleProcesses.serverIsAlive(inBottleAt: dir) == false)
        #expect(BottleProcesses.registryIsOursToWrite(inBottleAt: dir),
                "nothing is holding this one open")
    }

    /// The rule the launch applies before it rewrites system.reg, both answers
    /// of it, without needing a live bottle to produce one.
    ///
    /// A wineserver keeps its own copy of the registry and flushes it when it
    /// shuts down, so a write underneath it is lost at best and lands in the
    /// middle of that flush at worst -- on a file the bottle cannot be repaired
    /// without. And it would change nothing anyway: winebus reads what we set
    /// when the bottle boots, so a bottle that is already up is using what it
    /// booted with whatever we write into it.
    @Test func aLiveBottlesRegistryIsNotOursToWrite() {
        #expect(BottleProcesses.registryIsOursToWrite(serverIsAlive: true) == false)
        #expect(BottleProcesses.registryIsOursToWrite(serverIsAlive: false))
    }

    // MARK: - Letting a short-lived prefix come down before a launch

    /// The wine side of a booted bottle, by the names lsof gave for the Steam
    /// bottle on this machine: two winedevice.exe and one of everything else.
    private static let wineSide = [
        "wineserver", "winewrapper.exe", "services.exe", "winedevice.exe", "winedevice.exe",
        "plugplay.exe", "rpcss.exe", "svchost.exe", "explorer.exe",
    ]

    private static func scan(_ names: [String]) -> [BottleProcesses.Running] {
        names.enumerated().map { BottleProcesses.Running(pid: pid_t(500 + $0.offset), name: $0.element) }
    }

    /// Nothing holding the directory is nothing to wait for.
    @Test func anEmptyBottleIsNotRunning() {
        #expect(BottleProcesses.occupancy(of: []) == .notRunning)
    }

    /// Without a server the next wine command starts one of its own, whatever
    /// is left behind: those are orphans, and clearOrphans has had its say.
    @Test func leftoversWithoutAServerAreNotARunningBottle() {
        #expect(BottleProcesses.occupancy(of: Self.scan(["services.exe", "winedevice.exe"])) == .notRunning)
    }

    /// The prefix a short wine command leaves up: nothing in it is the user's.
    @Test func onlyWinesFurnitureIsAPrefixNothingOfTheUsersIsIn() {
        #expect(BottleProcesses.occupancy(of: Self.scan(Self.wineSide)) == .onlyWine)
    }

    /// An installer's reg.exe is wine's own too -- the judgement
    /// MGVFCoordinator makes, read from its own list so the two cannot drift.
    @Test func aFixInstallersRegExeIsWinesOwn() {
        #expect(BottleProcesses.occupancy(of: Self.scan(Self.wineSide + ["reg.exe"])) == .onlyWine)
        #expect(BottleProcesses.occupancy(
            of: Self.scan(["wineserver"] + MGVFCoordinator.Running.furniture.sorted())) == .onlyWine)
    }

    /// Steam is not wine's, whatever gamesRunning excuses it from: a bottle
    /// with Steam in it is not coming down because a launch is waiting. Every
    /// name is reported once, as lsof gave it.
    @Test func steamsOwnExecutablesAreInUse() {
        // Standing in for steamsOwnExecutables, which has to read a real bottle.
        let steams: Set<String> = ["steam.exe", "steamwebhelper.exe", "steamservice.exe", "gameoverlayui64.exe"]
        #expect(BottleProcesses.wineOwn.isDisjoint(with: steams))

        let running = Self.scan(Self.wineSide + ["Steam.exe", "steamwebhelper.exe", "steamwebhelper.exe"])
        #expect(BottleProcesses.occupancy(of: running) == .inUse(by: ["Steam.exe", "steamwebhelper.exe"]))
    }

    /// A game, or anything nobody listed, is named rather than waited for.
    @Test func aGameIsInUseByName() {
        #expect(BottleProcesses.occupancy(of: Self.scan(Self.wineSide + ["Game.exe"]))
                == .inUse(by: ["Game.exe"]))
        #expect(BottleProcesses.occupancy(of: Self.scan(Self.wineSide + ["reg.exe", "Unlisted.exe"]))
                == .inUse(by: ["Unlisted.exe"]))
    }

    /// An engine can name its server for its architecture: CrossOver Preview on
    /// this machine ships wineserver-x86 and wineserver-arm64 and no plain
    /// wineserver. Either one is a live server and wine's own, never a name
    /// the bottle is in use by -- and without one, the rest is not a bottle
    /// that is up.
    @Test func aServerNamedForItsArchitectureIsWinesOwn() {
        let furniture = Self.wineSide.filter { $0 != "wineserver" }
        #expect(BottleProcesses.occupancy(of: Self.scan(["wineserver-x86"] + furniture)) == .onlyWine)
        #expect(BottleProcesses.occupancy(of: Self.scan(["wineserver-arm64"] + furniture)) == .onlyWine)
        #expect(BottleProcesses.occupancy(of: Self.scan(["wineserver-x86"] + furniture + ["Game.exe"]))
                == .inUse(by: ["Game.exe"]))
        #expect(BottleProcesses.occupancy(of: Self.scan(furniture)) == .notRunning)
    }

    @Test func caseDoesNotDecide() {
        #expect(BottleProcesses.occupancy(
            of: Self.scan(["wineserver", "Services.EXE", "WineDevice.exe", "REG.exe"])) == .onlyWine)
        #expect(BottleProcesses.occupancy(of: Self.scan(["wineserver", "STEAM.EXE"])) == .inUse(by: ["STEAM.EXE"]))
    }

    /// lsof cuts every name of 31 characters or more down to 31, so a known
    /// name past the cap has to match its own truncation -- and a truncated
    /// name nobody knows is still named, as lsof gave it.
    @Test func aNameLsofCutShortIsStillRecognised() {
        let long = "averylongwinetoolnamepastthelimit.exe"
        #expect(long.count > BottleProcesses.lsofNameLimit)
        let cut = String(long.prefix(BottleProcesses.lsofNameLimit))
        let known = BottleProcesses.wineOwn.union([long])

        #expect(BottleProcesses.occupancy(of: Self.scan(["wineserver", cut]), wineOwn: known) == .onlyWine)
        #expect(BottleProcesses.occupancy(of: Self.scan(["wineserver", cut.uppercased()]), wineOwn: known) == .onlyWine)
        #expect(BottleProcesses.occupancy(of: Self.scan(["wineserver", long]), wineOwn: known) == .onlyWine)

        let overlay = String("EOSOverlayRenderer-Win64-Shipping.exe".prefix(BottleProcesses.lsofNameLimit))
        #expect(BottleProcesses.occupancy(of: Self.scan(["wineserver", overlay])) == .inUse(by: [overlay]))
    }

    /// A bottle with no server is not waited for at all. No wine: the bottle
    /// is an empty temporary directory, so there is no server directory to scan.
    @Test func aBottleWithNoServerIsNotWaitedFor() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bottle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let clock = ContinuousClock()
        let start = clock.now
        #expect(await BottleProcesses.letShortLivedPrefixComeDown(inBottleAt: dir) == .notRunning)
        #expect(clock.now - start < .seconds(1))
    }

    // MARK: - The wait's own loop, on a scripted scan

    /// A scan that answers from a script, one answer per call, and keeps
    /// giving the last one once the script runs out. Counted, so a test can
    /// say how many times lsof would have run.
    private final class ScriptedScan: @unchecked Sendable {
        private let lock = NSLock()
        private let answers: [[BottleProcesses.Running]]
        private var calls = 0

        init(_ answers: [[String]]) { self.answers = answers.map(BottleProcessesTests.scan) }

        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }

        func callAsFunction(_ bottle: URL) -> [BottleProcesses.Running] {
            lock.lock(); defer { lock.unlock() }
            let answer = answers[min(calls, answers.count - 1)]
            calls += 1
            return answer
        }
    }

    /// Never looked in: every scan below is scripted.
    private static let scriptedBottle = URL(fileURLWithPath: "/nonexistent/scripted-bottle")

    /// Something of the user's in the bottle at the first look is reported at
    /// once: one scan, and no sleep -- the interval is half a minute, so a
    /// sleep would show in the time.
    @Test func aBottleInUseAtOnceIsReportedAfterOneScan() async {
        let script = ScriptedScan([Self.wineSide + ["Game.exe"]])
        let clock = ContinuousClock()
        let start = clock.now
        let result = await BottleProcesses.letShortLivedPrefixComeDown(
            inBottleAt: Self.scriptedBottle, upTo: .seconds(60), every: .seconds(30), scan: { script($0) })

        #expect(result == .inUse(by: ["Game.exe"]))
        #expect(script.count == 1)
        #expect(clock.now - start < .seconds(5))
    }

    /// No server at the first look is `.notRunning`, not a prefix that came
    /// down: nothing was waited for.
    @Test func noServerAtTheFirstLookIsNotRunning() async {
        let script = ScriptedScan([[]])
        let clock = ContinuousClock()
        let start = clock.now
        let result = await BottleProcesses.letShortLivedPrefixComeDown(
            inBottleAt: Self.scriptedBottle, upTo: .seconds(60), every: .seconds(30), scan: { script($0) })

        #expect(result == .notRunning)
        #expect(script.count == 1)
        #expect(clock.now - start < .seconds(5))
    }

    /// Only wine's own processes, then nothing: the prefix came down during
    /// the wait, and that is `.cameDown` -- the answer only a later scan can
    /// give.
    @Test func onlyWineThenNothingCameDown() async {
        let script = ScriptedScan([Self.wineSide, Self.wineSide, []])
        let result = await BottleProcesses.letShortLivedPrefixComeDown(
            inBottleAt: Self.scriptedBottle, upTo: .seconds(60), every: .milliseconds(10), scan: { script($0) })

        guard case .cameDown(let seconds) = result else {
            Issue.record("expected .cameDown, got \(result)")
            return
        }
        #expect(seconds < 5)
        #expect(script.count == 3)
    }

    /// Only wine's own processes for the whole bound: `.stillUp`, naming each
    /// of them once, and not before the bound has passed.
    ///
    /// Judged by the time taken rather than by how many scans fitted in it.
    /// In the full suite, run in parallel, a single scan here took longer than
    /// a 200 ms bound, so the loop rightly found the bound spent after its
    /// first look -- a count of scans says more about the machine's load than
    /// about the loop. The time does not: without a cancellation, the loop
    /// returns `.stillUp` only once the bound has passed.
    @Test func onlyWineForTheWholeBoundIsStillUp() async {
        let script = ScriptedScan([Self.wineSide])
        let bound = Duration.milliseconds(500)
        let clock = ContinuousClock()
        let start = clock.now
        let result = await BottleProcesses.letShortLivedPrefixComeDown(
            inBottleAt: Self.scriptedBottle, upTo: bound, every: .milliseconds(10), scan: { script($0) })
        let took = clock.now - start

        guard case .stillUp(let seconds, let names) = result else {
            Issue.record("expected .stillUp, got \(result)")
            return
        }
        #expect(names == Set(Self.wineSide).sorted())
        #expect(seconds < 5)
        #expect(took >= bound, "the bound should have been waited out, not given up at the first look")
        #expect(took < .seconds(5))
        #expect(script.count >= 1)
    }

    /// A game that arrives while the launch waits ends the wait: it is not
    /// going to leave because a launch is waiting.
    @Test func aGameArrivingMidWaitIsInUse() async {
        let script = ScriptedScan([Self.wineSide, Self.wineSide + ["Game.exe"]])
        let result = await BottleProcesses.letShortLivedPrefixComeDown(
            inBottleAt: Self.scriptedBottle, upTo: .seconds(60), every: .milliseconds(10), scan: { script($0) })

        #expect(result == .inUse(by: ["Game.exe"]))
        #expect(script.count == 2)
    }

    /// A cancelled wait returns at once, without scanning again. The interval
    /// is a minute, so a wait that ignored the cancellation would take that
    /// long; one that turned the cancelled sleep into a loop would scan many
    /// times over.
    @Test func aCancelledWaitReturnsWithoutScanningAgain() async throws {
        let script = ScriptedScan([Self.wineSide])
        let waiting = Task {
            await BottleProcesses.letShortLivedPrefixComeDown(
                inBottleAt: Self.scriptedBottle, upTo: .seconds(120), every: .seconds(60), scan: { script($0) })
        }
        // Cancelled once the first scan has been made, so the cancellation
        // arrives during or just before the sleep that follows it.
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while script.count == 0, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(script.count == 1)

        let cancelledAt = clock.now
        waiting.cancel()
        let result = await waiting.value

        #expect(clock.now - cancelledAt < .seconds(5))
        #expect(script.count == 1, "a cancelled sleep must not turn the rest of the bound into scans")
        guard case .stillUp(_, let names) = result else {
            Issue.record("expected .stillUp, got \(result)")
            return
        }
        #expect(names == Set(Self.wineSide).sorted())
    }

    /// A launch that starts the bottle itself -- nothing was up, or what was up
    /// came down first -- has nothing to warn about.
    @Test func aTraceOfABottleThisLaunchStartsIsNotWarnedAbout() {
        #expect(BottleProcesses.hidTraceWarning(after: .notRunning) == nil)
        #expect(BottleProcesses.hidTraceWarning(after: .cameDown(afterSeconds: 4)) == nil)
    }

    /// A launch that joins a bottle already up says what the trace will lack,
    /// and why, in both of the ways a bottle can still be up.
    @Test func aTraceOfABottleAlreadyUpSaysWhatItWillMiss() throws {
        let busy = try #require(BottleProcesses.hidTraceWarning(after: .inUse(by: ["Game.exe", "Steam.exe"])))
        #expect(busy.contains("in use by Game.exe, Steam.exe"))
        #expect(busy.contains("winebus"))

        let slow = try #require(BottleProcesses.hidTraceWarning(
            after: .stillUp(afterSeconds: 20, names: ["services.exe", "wineserver"])))
        #expect(slow.contains("did not go within 20 s"))
        #expect(slow.contains("winebus"))
    }

    /// Against the real thing: the bottle this application actually uses must
    /// resolve to a directory wine has really made, or the scoping is fiction.
    @Test func therealBottleResolvesToADirectoryWineMade() throws {
        let bottle = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/RaccoonBot/CXPBottles/Steam")
        try #require(FileManager.default.fileExists(atPath: bottle.path))
        let server = try #require(BottleProcesses.serverDirectory(ofBottleAt: bottle))
        #expect(FileManager.default.fileExists(atPath: server.path))
    }
}
