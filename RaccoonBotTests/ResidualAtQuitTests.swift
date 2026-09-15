//
//  ResidualAtQuitTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Every scan here is scripted and every signal is recorded, never sent: no
/// lsof, no wine, and not one process is signalled by these tests.
@Suite("Clearing what wine left without a server when this application quits")
struct ResidualAtQuitTests {

    private typealias Running = BottleProcesses.Running
    private typealias ServerScan = BottleProcesses.ServerScan
    private typealias Stopping = BottleProcesses.Stopping

    /// Never looked in: the directories only name scripted answers.
    private static let live = URL(fileURLWithPath: "/nonexistent/.wine-0/server-1-live")
    private static let dead = URL(fileURLWithPath: "/nonexistent/.wine-0/server-2-dead")
    private static let empty = URL(fileURLWithPath: "/nonexistent/.wine-0/server-3-empty")

    private static func p(_ pid: pid_t, _ name: String) -> Running { Running(pid: pid, name: name) }

    /// A game playing under its own server, by the names lsof gave for the
    /// Steam bottle on this machine.
    private static let session = [p(10, "wineserver"), p(11, "services.exe"), p(12, "winedevice.exe"),
                                  p(13, "steam.exe"), p(14, "Game.exe")]
    /// What outlived a server: the controller driver and its service host.
    private static let orphans = [p(20, "winedevice.exe"), p(21, "services.exe")]

    /// Short enough that the tests do not wait seconds; the quit uses
    /// `startingClientWindow`.
    private static let settle = Duration.milliseconds(20)

    private static func ids(_ processes: [Running]) -> [pid_t] { processes.map(\.pid).sorted() }

    /// Later looks at a directory, answered from a script per directory: one
    /// answer per call, the last one kept once the script runs out. A
    /// directory with no script records the look and answers nothing.
    private final class Rescans: @unchecked Sendable {
        private let lock = NSLock()
        private let scripts: [String: [[Running]]]
        private var calls: [String: Int] = [:]
        private var firstCall: [String: ContinuousClock.Instant] = [:]

        init(_ scripts: [URL: [[Running]]]) {
            self.scripts = Dictionary(uniqueKeysWithValues: scripts.map { ($0.key.path, $0.value) })
        }

        func count(_ server: URL) -> Int { lock.lock(); defer { lock.unlock() }; return calls[server.path] ?? 0 }
        func firstLook(at server: URL) -> ContinuousClock.Instant? { lock.lock(); defer { lock.unlock() }; return firstCall[server.path] }

        func callAsFunction(_ server: URL) -> [Running] {
            lock.lock(); defer { lock.unlock() }
            let n = calls[server.path] ?? 0
            calls[server.path] = n + 1
            if n == 0 { firstCall[server.path] = ContinuousClock.now }
            guard let script = scripts[server.path], !script.isEmpty else { return [] }
            return script[min(n, script.count - 1)]
        }
    }

    /// Signals written down instead of sent.
    private final class Signals: @unchecked Sendable {
        private let lock = NSLock()
        private var sent: [(pid: pid_t, signal: Int32)] = []

        func callAsFunction(_ pid: pid_t, _ signal: Int32) { lock.lock(); sent.append((pid, signal)); lock.unlock() }

        var all: [pid_t] { lock.lock(); defer { lock.unlock() }; return sent.map(\.pid) }
        func pids(_ signal: Int32) -> [pid_t] {
            lock.lock(); defer { lock.unlock() }
            return sent.filter { $0.signal == signal }.map(\.pid).sorted()
        }
    }

    // MARK: - The rule, on scans

    /// A directory with a server in it is a session, whatever else is there;
    /// one with nothing in it is nothing; one with processes and no server is
    /// what somebody left behind.
    @Test func onlyADirectoryWithProcessesAndNoServerIsALeftover() {
        let scans = [ServerScan(server: Self.live, processes: Self.session),
                     ServerScan(server: Self.dead, processes: Self.orphans),
                     ServerScan(server: Self.empty, processes: [])]
        let left = BottleProcesses.serverless(scans)
        #expect(left.map(\.server) == [Self.dead])
        #expect(Self.ids(left.flatMap(\.processes)) == [20, 21])
    }

    /// An engine can name its server for its architecture, and that is still
    /// a server: the directory is a session.
    @Test func aServerNamedForItsArchitectureMakesASession() {
        let scans = [ServerScan(server: Self.live, processes: [Self.p(10, "wineserver-x86"), Self.p(12, "winedevice.exe")]),
                     ServerScan(server: Self.dead, processes: [Self.p(20, "wineserver-arm64"), Self.p(21, "Game.exe")])]
        #expect(BottleProcesses.serverless(scans).isEmpty)
    }

    /// A server in the later look drops the directory whole -- including what
    /// was there before it arrived.
    @Test func aServerInTheLaterLookKeepsNothingOfThatDirectory() {
        let earlier = [ServerScan(server: Self.dead, processes: Self.orphans)]
        let later = [ServerScan(server: Self.dead, processes: Self.orphans + [Self.p(30, "wineserver")])]
        #expect(BottleProcesses.stillServerless(later, of: earlier).isEmpty)
    }

    /// Only what was in both looks, by pid and name: a newcomer never received
    /// anything, and a pid reused under another name is somebody else.
    @Test func theLaterLookKeepsOnlyWhatWasInBoth() {
        let earlier = [ServerScan(server: Self.dead, processes: Self.orphans)]
        let later = [ServerScan(server: Self.dead, processes: [Self.p(20, "winedevice.exe"),
                                                               Self.p(21, "Game.exe"),
                                                               Self.p(30, "reg.exe")])]
        let left = BottleProcesses.stillServerless(later, of: earlier)
        #expect(left.map(\.server) == [Self.dead])
        #expect(left.flatMap(\.processes).map(\.pid) == [20])
        #expect(left.flatMap(\.processes).map(\.name) == ["winedevice.exe"])
    }

    /// A directory the later look did not answer for, or found empty, ends
    /// nothing: a scan that failed must not read as permission.
    @Test func noAnswerInTheLaterLookEndsNothing() {
        let earlier = [ServerScan(server: Self.dead, processes: Self.orphans)]
        #expect(BottleProcesses.stillServerless([], of: earlier).isEmpty)
        #expect(BottleProcesses.stillServerless([ServerScan(server: Self.dead, processes: [])], of: earlier).isEmpty)
        #expect(BottleProcesses.stillServerless([ServerScan(server: Self.live, processes: Self.orphans)], of: earlier).isEmpty)
    }

    // MARK: - The sweep, on scripted scans

    /// A quit while a game is playing under its server: nothing is signalled,
    /// and nothing is even looked at a second time.
    @Test func aQuitDuringAGameTouchesNothing() {
        let rescans = Rescans([:])
        let signals = Signals()
        let sweep = BottleProcesses.clearResidualAtQuit(
            scanEverything: { [ServerScan(server: Self.live, processes: Self.session)] },
            scan: { rescans($0) }, signal: { signals($0, $1) },
            settle: Self.settle, grace: .milliseconds(100), every: .milliseconds(10))

        #expect(signals.all.isEmpty)
        #expect(rescans.count(Self.live) == 0)
        #expect(sweep.found.isEmpty && sweep.askedToLeave.isEmpty && sweep.ended.isEmpty)
    }

    /// With a game playing in one prefix and leftovers in another, only the
    /// leftovers are asked to leave, and the game's directory is never looked
    /// at again. They leave on the request, so nothing is ended.
    @Test func onlyTheDirectoryWithoutAServerIsAskedToLeave() {
        let rescans = Rescans([Self.dead: [Self.orphans, []]])
        let signals = Signals()
        let sweep = BottleProcesses.clearResidualAtQuit(
            scanEverything: { [ServerScan(server: Self.live, processes: Self.session),
                               ServerScan(server: Self.dead, processes: Self.orphans)] },
            scan: { rescans($0) }, signal: { signals($0, $1) },
            settle: Self.settle, grace: .milliseconds(100), every: .milliseconds(10))

        #expect(signals.pids(SIGTERM) == [20, 21])
        #expect(signals.pids(SIGKILL).isEmpty)
        #expect(signals.all.allSatisfy { $0 >= 20 }, "nothing of the live session may be signalled")
        #expect(rescans.count(Self.live) == 0)
        #expect(Self.ids(sweep.askedToLeave) == [20, 21])
        #expect(sweep.ended.isEmpty)
    }

    /// A prefix that is starting while the first look runs can show its first
    /// process without its server. The second look finds the server, and
    /// nothing is signalled.
    @Test func aServerAtTheSecondLookLeavesTheDirectoryAlone() {
        let rescans = Rescans([Self.dead: [[Self.p(20, "Steam.exe"), Self.p(22, "wineserver")]]])
        let signals = Signals()
        let sweep = BottleProcesses.clearResidualAtQuit(
            scanEverything: { [ServerScan(server: Self.dead, processes: [Self.p(20, "Steam.exe")])] },
            scan: { rescans($0) }, signal: { signals($0, $1) },
            settle: Self.settle, grace: .milliseconds(100), every: .milliseconds(10))

        #expect(signals.all.isEmpty)
        #expect(Self.ids(sweep.found) == [20])
        #expect(sweep.askedToLeave.isEmpty)
    }

    /// A wine command retrying its connection sits in the directory with no
    /// server until its sleep ends and it starts one. Seen that way at the
    /// first look, it is not asked to leave: the second look waits long enough
    /// to find the server it started.
    @Test func aCommandStillStartingItsServerIsNotAskedToLeave() {
        let clock = ContinuousClock()
        let serverArrives = clock.now + .milliseconds(150)
        let command = [Self.p(40, "reg.exe")]
        let lookNow: () -> [Running] = {
            clock.now < serverArrives ? command : command + [Self.p(41, "wineserver")]
        }
        let signals = Signals()
        let sweep = BottleProcesses.clearResidualAtQuit(
            scanEverything: { [ServerScan(server: Self.dead, processes: lookNow())] },
            scan: { _ in lookNow() }, signal: { signals($0, $1) },
            settle: .milliseconds(400), grace: .milliseconds(100), every: .milliseconds(10))

        #expect(Self.ids(sweep.found) == [40], "the first look should have seen it without a server")
        #expect(sweep.askedToLeave.isEmpty)
        #expect(signals.all.isEmpty)
    }

    /// The second look is taken no sooner than `settle` after the first one
    /// ended.
    @Test func theSecondLookWaitsOutTheSettle() {
        let rescans = Rescans([Self.dead: [Self.orphans, []]])
        let signals = Signals()
        let firstLookEnded = FirstLookEnded()
        let settle = Duration.milliseconds(200)
        _ = BottleProcesses.clearResidualAtQuit(
            scanEverything: {
                defer { firstLookEnded.mark() }
                return [ServerScan(server: Self.dead, processes: Self.orphans)]
            },
            scan: { rescans($0) }, signal: { signals($0, $1) },
            settle: settle, grace: .milliseconds(100), every: .milliseconds(10))

        guard let ended = firstLookEnded.at, let second = rescans.firstLook(at: Self.dead) else {
            Issue.record("both looks should have been taken")
            return
        }
        #expect(second - ended >= settle)
        #expect(signals.pids(SIGTERM) == [20, 21])
    }

    private final class FirstLookEnded: @unchecked Sendable {
        private let lock = NSLock()
        private var moment: ContinuousClock.Instant?
        func mark() { lock.lock(); moment = ContinuousClock.now; lock.unlock() }
        var at: ContinuousClock.Instant? { lock.lock(); defer { lock.unlock() }; return moment }
    }

    /// What stays through the grace is ended -- only what was asked, by pid
    /// and name. A newcomer and a pid reused under another name during the
    /// grace get nothing. And the grace is waited out before the SIGKILL.
    @Test func whatStaysThroughTheGraceIsEndedAndNothingElse() {
        let during = [Self.p(20, "winedevice.exe"), Self.p(21, "Game.exe"), Self.p(30, "reg.exe")]
        let rescans = Rescans([Self.dead: [Self.orphans, during]])
        let signals = Signals()
        let grace = Duration.milliseconds(150)
        let clock = ContinuousClock()
        let start = clock.now
        let sweep = BottleProcesses.clearResidualAtQuit(
            scanEverything: { [ServerScan(server: Self.dead, processes: Self.orphans)] },
            scan: { rescans($0) }, signal: { signals($0, $1) },
            settle: Self.settle, grace: grace, every: .milliseconds(10))
        let took = clock.now - start

        #expect(signals.pids(SIGTERM) == [20, 21])
        #expect(signals.pids(SIGKILL) == [20])
        #expect(!signals.all.contains(30))
        #expect(sweep.ended.map(\.name) == ["winedevice.exe"])
        #expect(took >= grace, "the grace should have been waited out before ending anything")
        #expect(took < .seconds(5))
    }

    /// A server that arrives during the grace makes the directory a session:
    /// what was asked to leave is not ended.
    @Test func aServerArrivingDuringTheGraceEndsNothing() {
        let rescans = Rescans([Self.dead: [Self.orphans, Self.orphans + [Self.p(30, "wineserver")]]])
        let signals = Signals()
        let sweep = BottleProcesses.clearResidualAtQuit(
            scanEverything: { [ServerScan(server: Self.dead, processes: Self.orphans)] },
            scan: { rescans($0) }, signal: { signals($0, $1) },
            settle: Self.settle, grace: .milliseconds(100), every: .milliseconds(10))

        #expect(signals.pids(SIGTERM) == [20, 21])
        #expect(signals.pids(SIGKILL).isEmpty)
        #expect(sweep.ended.isEmpty)
    }

    /// What leaves on the request is not waited for: a grace of a minute
    /// ends at the first look that finds the directory empty.
    @Test func whatLeavesAtOnceIsNotWaitedFor() {
        let rescans = Rescans([Self.dead: [Self.orphans, []]])
        let signals = Signals()
        let clock = ContinuousClock()
        let start = clock.now
        _ = BottleProcesses.clearResidualAtQuit(
            scanEverything: { [ServerScan(server: Self.dead, processes: Self.orphans)] },
            scan: { rescans($0) }, signal: { signals($0, $1) },
            settle: Self.settle, grace: .seconds(60), every: .milliseconds(10))

        #expect(clock.now - start < .seconds(5))
        #expect(rescans.count(Self.dead) == 2)
        #expect(signals.pids(SIGKILL).isEmpty)
    }

    // MARK: - A quit inside a teardown

    /// A quit inside the two seconds a server takes to go after `wineserver
    /// -k`: the directory still holds that server, so a look then would call
    /// it a session and end nothing. The sweep waits for the server this
    /// application asked to quit, and then asks what outlived it to leave.
    @Test func aQuitInsideATeardownWaitsForThatServerThenClearsWhatOutlivedIt() {
        let clock = ContinuousClock()
        let start = clock.now
        let serverGone = start + .milliseconds(150)
        let lookNow: () -> [Running] = {
            clock.now < serverGone ? Self.orphans + [Self.p(30, "wineserver")] : Self.orphans
        }
        let signals = Signals()
        let sweep = BottleProcesses.clearResidualAtQuit(
            stopping: [Stopping(server: Self.dead, until: start + .seconds(2))],
            scanEverything: { [ServerScan(server: Self.dead, processes: lookNow())] },
            scan: { _ in lookNow() }, signal: { signals($0, $1) },
            settle: Self.settle, grace: .milliseconds(50), every: .milliseconds(10))

        #expect(sweep.serversStillUp.isEmpty)
        #expect(signals.pids(SIGTERM) == [20, 21])
        #expect(!signals.all.contains(30), "the server is never signalled")
        #expect(clock.now - start >= .milliseconds(150), "the server should have been waited for")
    }

    /// A server still up when its wait ends -- a newer session, or one that
    /// takes longer than the bound -- leaves its directory alone, and the
    /// wait does not outlast its moment.
    @Test func aServerStillUpWhenItsWaitEndsIsLeftAlone() {
        let clock = ContinuousClock()
        let start = clock.now
        let signals = Signals()
        let sweep = BottleProcesses.clearResidualAtQuit(
            stopping: [Stopping(server: Self.dead, until: start + .milliseconds(150))],
            scanEverything: { [ServerScan(server: Self.dead, processes: Self.session)] },
            scan: { _ in Self.session }, signal: { signals($0, $1) },
            settle: Self.settle, grace: .milliseconds(50), every: .milliseconds(10))
        let took = clock.now - start

        #expect(signals.all.isEmpty)
        #expect(sweep.serversStillUp == [Self.dead])
        #expect(sweep.found.isEmpty)
        #expect(took >= .milliseconds(150))
        #expect(took < .seconds(2))
    }

    /// A server that was asked to quit and has already gone costs one look,
    /// not a wait.
    @Test func aServerAlreadyGoneIsNotWaitedFor() {
        let rescans = Rescans([Self.dead: [[]]])
        let clock = ContinuousClock()
        let start = clock.now
        _ = BottleProcesses.clearResidualAtQuit(
            stopping: [Stopping(server: Self.dead, until: start + .seconds(60))],
            scanEverything: { [] },
            scan: { rescans($0) }, signal: { _, _ in },
            settle: Self.settle, grace: .milliseconds(50), every: .milliseconds(10))

        #expect(rescans.count(Self.dead) == 1)
        #expect(clock.now - start < .seconds(5))
    }

    /// A server is waited for only within its allowance from the moment it was
    /// asked, and asking again starts that allowance over.
    @Test func aServerIsWaitedForOnlyWithinItsAllowance() {
        let asked = BottleProcesses.ServersAskedToQuit()
        let start = ContinuousClock.now
        asked.record(Self.dead, at: start)
        asked.record(Self.live, at: start - .seconds(10))

        let going = asked.stillGoing(at: start + .seconds(1), allowance: .seconds(4))
        #expect(going.map(\.server) == [Self.dead])
        #expect(going.first?.until == start + .seconds(4))

        asked.record(Self.live, at: start + .seconds(1))
        #expect(asked.stillGoing(at: start + .milliseconds(4500), allowance: .seconds(4)).map(\.server) == [Self.live])
        #expect(asked.stillGoing(at: start + .seconds(6), allowance: .seconds(4)).isEmpty)
    }

    /// The quit waits longer only while a server it asked to quit may still be
    /// on its way out, and by at least what is left of that wait.
    @Test func theQuitBoundGrowsByWhatIsLeftOfTheServerWait() {
        let now = ContinuousClock.now
        let plain = BottleProcesses.quitBound(waitingFor: [], now: now)
        let waiting = BottleProcesses.quitBound(waitingFor: [Stopping(server: Self.dead, until: now + .seconds(3))], now: now)
        let expired = BottleProcesses.quitBound(waitingFor: [Stopping(server: Self.dead, until: now - .seconds(3))], now: now)
        #expect(waiting >= plain + .seconds(3))
        #expect(expired >= plain && expired < plain + .seconds(1))
        #expect(plain >= BottleProcesses.startingClientWindow + .seconds(1),
                "the bound must cover the settle and the grace")
    }

    // MARK: - The wait at quit

    /// With CrossOver or Procyon open, the sweep is not even started.
    @MainActor
    @Test func aQuitWithAWineHostOpenLooksAtNothing() {
        let signals = Signals()
        let outcome = BottleProcesses.clearResidualBeforeQuitting(
            hostIsOpen: true, within: .seconds(1),
            sweep: { signals(0, 0); return BottleProcesses.QuitSweep() })
        guard case .hostOpen = outcome else {
            Issue.record("expected .hostOpen, got \(outcome)")
            return
        }
        #expect(signals.all.isEmpty, "the sweep must not run")
    }

    /// A sweep that does not come back does not hold the quit: the wait gives
    /// up at its bound.
    @MainActor
    @Test func aSweepThatDoesNotReturnDoesNotHoldTheQuit() {
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = BottleProcesses.clearResidualBeforeQuitting(
            hostIsOpen: false, within: .milliseconds(200),
            sweep: { Thread.sleep(forTimeInterval: 3); return BottleProcesses.QuitSweep() })
        let took = clock.now - start

        guard case .gaveUp = outcome else {
            Issue.record("expected .gaveUp, got \(outcome)")
            return
        }
        #expect(took >= .milliseconds(200))
        #expect(took < .seconds(2))
    }

    /// A sweep that finishes inside the bound is handed back as it finished.
    @MainActor
    @Test func aFinishedSweepIsHandedBack() {
        let outcome = BottleProcesses.clearResidualBeforeQuitting(
            hostIsOpen: false, within: .seconds(2),
            sweep: {
                var sweep = BottleProcesses.QuitSweep()
                sweep.found = ResidualAtQuitTests.orphans
                sweep.askedToLeave = ResidualAtQuitTests.orphans
                return sweep
            })
        guard case .finished(let sweep) = outcome else {
            Issue.record("expected .finished, got \(outcome)")
            return
        }
        #expect(Self.ids(sweep.askedToLeave) == [20, 21])
    }

    /// What the console says: nothing when there was nothing, and each case
    /// in its own words.
    @Test func theConsoleSaysWhatHappenedAndNothingWhenNothingDid() {
        #expect(BottleProcesses.quitLines(for: .finished(.init())).isEmpty)
        #expect(BottleProcesses.quitLines(for: .hostOpen) == ["at quit: crossover is open; leaving its processes alone"])
        #expect(BottleProcesses.quitLines(for: .gaveUp(after: .seconds(4))).first?.contains("within 4 s") == true)

        var unconfirmed = BottleProcesses.QuitSweep()
        unconfirmed.found = Self.orphans
        let alone = BottleProcesses.quitLines(for: .finished(unconfirmed))
        #expect(alone.count == 1)
        #expect(alone.first?.contains("leaving them alone") == true)

        var stillUp = BottleProcesses.QuitSweep()
        stillUp.serversStillUp = [Self.dead]
        #expect(BottleProcesses.quitLines(for: .finished(stillUp)) == [
            "at quit: the server asked to quit in server-2-dead was still up when the wait for it ended; leaving that bottle alone",
        ])

        var ended = BottleProcesses.QuitSweep()
        ended.found = Self.orphans
        ended.askedToLeave = Self.orphans
        ended.ended = [Self.p(20, "winedevice.exe")]
        #expect(BottleProcesses.quitLines(for: .finished(ended)) == [
            "at quit: asking 2 wine process(es) whose server is gone to leave: services.exe, winedevice.exe",
            "at quit: winedevice.exe ignored the request; ending it",
        ])
    }
}
