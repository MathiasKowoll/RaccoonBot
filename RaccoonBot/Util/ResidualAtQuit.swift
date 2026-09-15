//
//  ResidualAtQuit.swift
//  RaccoonBot
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import AppKit

/// Clearing what wine left without a server when this application quits, not
/// only at its next start.
///
/// Measured 2026-09-14: a Steam bottle's winedevice.exe -- where winebus, the
/// controller driver, runs -- went on receiving a DualSense's input reports
/// after that bottle's wineserver died (the trace's wine clock stopped at the
/// moment of the death): 34,335 of them, until macOS cut the idle pad about ten
/// minutes later. Its output only landed an hour after the death, as this
/// application was next started, and that the startup sweep ended it then is
/// read from the timing alone. Nothing in this application was going to end it
/// before that.
///
/// What the code allows. `closeBottle` is the only thing that ends a bottle's
/// processes during a session, and it runs from a game's tracker or a Stop
/// button, never at quit; nothing else here watches this application's own
/// termination. Its `wineserver -k` is where the server goes: wine's server,
/// asked that way, marks every thread of every client terminated (a wakeup for
/// a thread in a wait, SIGQUIT for any other) and exits two seconds later --
/// sooner only once every process has gone -- without checking that they went
/// (server/process.c, shutdown_master_socket and process_died; server/thread.c,
/// kill_thread). So a quit that lands between that request and
/// `BottleProcesses.end` leaves whatever did not act on it to the next start
/// -- or to the next launch into that bottle.
///
/// Until it exits, that server holds its lock in the server directory
/// (server/request.c, acquire_lock), so a look inside those two seconds finds a
/// server there and, by the rule below, a session. A sweep that only looked
/// would miss that part of the window and let the application exit before the
/// server did. So the sweep first waits, bounded, for a server this
/// application itself asked to quit (`ServersAskedToQuit`), and only then
/// looks.
///
/// The rules are `clearResidualAtStartup`'s: only a directory with no
/// wineserver in it, never a live session, and nothing at all while CrossOver
/// or Procyon is open. A quit while a game is running under its server finds
/// that server in the game's directory and touches nothing there.
extension BottleProcesses {

    /// One wineserver directory, and what held it open when it was looked at.
    nonisolated struct ServerScan {
        let server: URL
        let processes: [Running]
    }

    /// Is a wine server among these? Judged by name, the test `occupancy`
    /// makes, so a server an engine named for its architecture counts.
    nonisolated static func includesServer(_ processes: [Running]) -> Bool {
        processes.contains { $0.name.contains("wineserver") }
    }

    /// Every wineserver directory of this user, each with what holds it open.
    ///
    /// One lsof per directory, which is where the second and a half of a
    /// sweep goes.
    nonisolated static func scanEveryServer() -> [ServerScan] {
        let root = URL(fileURLWithPath: "/private/tmp/.wine-\(getuid())")
        guard let servers = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        return servers
            .filter { $0.lastPathComponent.hasPrefix("server-") }
            .map { ServerScan(server: $0, processes: processes(holding: $0)) }
    }

    /// The directories whose processes outlived their server: something holds
    /// them open and none of it is a wineserver. A prefix nobody is running
    /// any more.
    nonisolated static func serverless(_ scans: [ServerScan]) -> [ServerScan] {
        scans.filter { !$0.processes.isEmpty && !includesServer($0.processes) }
    }

    /// What of an earlier look is still there, and still without a server, at
    /// a later one.
    ///
    /// A directory with a wineserver in the later look is dropped whole: from
    /// then on it is somebody's session, whatever else is in it. Otherwise
    /// only what was in both looks is kept, by pid AND name as `stillThere`
    /// keeps it -- a newcomer never received anything it could be ending for
    /// ignoring, and a reused pid is somebody else. A directory the later look
    /// has no answer for is dropped too, so a scan that failed ends nothing.
    nonisolated static func stillServerless(_ later: [ServerScan], of earlier: [ServerScan]) -> [ServerScan] {
        let now = Dictionary(later.map { ($0.server.path(percentEncoded: false), $0.processes) },
                             uniquingKeysWith: { first, _ in first })
        return earlier.compactMap { before in
            guard let here = now[before.server.path(percentEncoded: false)],
                  !includesServer(here) else { return nil }
            let left = stillThere(here, of: before.processes)
            return left.isEmpty ? nil : ServerScan(server: before.server, processes: left)
        }
    }

    // MARK: - Servers this application asked to quit

    /// A server this application asked to quit, and the moment a quit stops
    /// waiting for it to go.
    nonisolated struct Stopping: Sendable {
        let server: URL
        let until: ContinuousClock.Instant
    }

    /// How long after its `wineserver -k` was started a quit still waits for
    /// that server.
    ///
    /// Asked with `-k`, wine's server exits two seconds after the request
    /// reaches it, or sooner once every process has gone (server/process.c,
    /// shutdown_master_socket and process_died). The request goes through zsh
    /// and CrossOver's wine script before it reaches the server, and that has
    /// not been timed. Four seconds from the moment the command was started is
    /// a bound, not a measurement of how long a server takes to go.
    nonisolated static let serverExitAllowance: Duration = .seconds(4)

    /// Which servers this application has asked to quit, and when.
    ///
    /// Written by `quitWine` once its command has started, read by the sweep
    /// at quit. One entry per server directory, replaced when that server is
    /// asked again, so it never holds more than one per bottle. An entry is
    /// not removed when its teardown finishes: past its allowance it is not
    /// waited for, and before it, a server that has already gone ends the
    /// wait at the first look.
    nonisolated final class ServersAskedToQuit: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String: (server: URL, at: ContinuousClock.Instant)] = [:]

        func record(_ server: URL, at moment: ContinuousClock.Instant = ContinuousClock.now) {
            lock.lock(); defer { lock.unlock() }
            asked[server.path(percentEncoded: false)] = (server, moment)
        }

        /// Those asked recently enough that a quit still waits for them.
        func stillGoing(at now: ContinuousClock.Instant = ContinuousClock.now,
                        allowance: Duration = BottleProcesses.serverExitAllowance) -> [Stopping] {
            lock.lock(); defer { lock.unlock() }
            return asked.values
                .map { Stopping(server: $0.server, until: $0.at + allowance) }
                .filter { now < $0.until }
                .sorted { $0.server.path(percentEncoded: false) < $1.server.path(percentEncoded: false) }
        }
    }

    nonisolated static let serversAskedToQuit = ServersAskedToQuit()

    /// Wait until none of these directories holds a wineserver, each up to its
    /// own moment. Returns the directories that still held one when their
    /// wait ended.
    ///
    /// Only watches. A server still up at its moment is left to the rule: the
    /// look that follows finds it, and its directory is a session.
    nonisolated static func waitForServersToGo(_ stopping: [Stopping],
                                               scan: (URL) -> [Running],
                                               every interval: Duration) -> [URL] {
        let clock = ContinuousClock()
        var waiting = stopping
        var stillUp: [URL] = []
        while true {
            var next: [Stopping] = []
            for entry in waiting where includesServer(scan(entry.server)) {
                if clock.now < entry.until { next.append(entry) } else { stillUp.append(entry.server) }
            }
            waiting = next
            guard !waiting.isEmpty else { return stillUp }
            Thread.sleep(forTimeInterval: seconds(interval))
        }
    }

    // MARK: - The sweep

    /// How far apart the two looks before any signal are.
    ///
    /// A wine command started in a prefix whose server is on its way out sits
    /// in the server directory without a server beside it. ntdll's
    /// server_connect changes into that directory first; while the old server
    /// has stopped listening but not yet exited, the connection is refused,
    /// and the command retries after sleeps of 0.1, 0.4, 0.9, 1.6 and 2.5 s,
    /// asking for a server of its own at each wake, which it gets once the old
    /// one has released its lock (dlls/ntdll/unix/server.c, server_connect;
    /// loader.c, start_server). It installs its signal handlers only after it
    /// has connected, so a SIGTERM in that window ends it -- and with it an
    /// installer's reg.exe or a launch. Seen at one look, such a command has a
    /// server beside it by the end of its current sleep, 2.5 s at the longest.
    /// So the second look comes three seconds after the first: the half second
    /// on top is room for that server's exec. All of this is reasoned from
    /// wine's source; a command in that loop has not been observed here.
    nonisolated static let startingClientWindow: Duration = .seconds(3)

    /// What the sweep at quit did, for the console.
    nonisolated struct QuitSweep {
        /// Servers this application had asked to quit that were still up when
        /// the wait for them ended. Their directories are sessions to the rule.
        var serversStillUp: [URL] = []
        /// Without a server at the first look.
        var found: [Running] = []
        /// Still without one at the second look, and asked to leave.
        var askedToLeave: [Running] = []
        /// Still there, and still without a server, once the grace was over:
        /// ended.
        var ended: [Running] = []
    }

    /// Ask what outlived its server to leave, then end what did not.
    ///
    /// First the wait for any server this application asked to quit, for the
    /// reason the top of this file gives. Then two looks before any signal,
    /// `settle` apart, and a directory with a server in either look is left
    /// alone. A scan is not an instant -- lsof takes a fifth of a second per
    /// directory -- and two looks taken back to back would not tell a process
    /// that outlived its server from a wine command that is still starting
    /// one; `startingClientWindow` says why three seconds does. The spacing is
    /// only paid when the first look finds something without a server.
    ///
    /// SIGTERM, then SIGKILL for what stayed, rather than SIGTERM alone. What
    /// is found here has already outlived its own server's request to end,
    /// and whether it acts on a SIGTERM has not been measured; the startup
    /// sweep follows its SIGTERM with SIGKILL too. A SIGTERM
    /// nobody checks could leave the process of the measurement above holding
    /// the pad until the next start, which is what this is here to prevent.
    /// The SIGKILL goes only to what the last look still finds by pid and name
    /// in a directory that is still without a server.
    ///
    /// One second of grace rather than the startup sweep's three, because a
    /// quit waits for it; the directories are looked at again every quarter
    /// of a second meanwhile, so what leaves at once is not waited for. Past
    /// the grace the last look decides.
    ///
    /// Synchronous, and meant for a thread of its own: the main thread waits
    /// for it at quit, bounded, in `clearResidualBeforeQuitting`. The scans,
    /// the signal and the durations are parameters only so a test can drive
    /// every branch without lsof, without signalling anything and without
    /// waiting seconds; the quit passes only what it is waiting for.
    nonisolated static func clearResidualAtQuit(
        stopping: [Stopping] = [],
        scanEverything: () -> [ServerScan] = { BottleProcesses.scanEveryServer() },
        scan: (URL) -> [Running] = { BottleProcesses.processes(holding: $0) },
        signal: (pid_t, Int32) -> Void = { _ = kill($0, $1) },
        settle: Duration = BottleProcesses.startingClientWindow,
        grace: Duration = .seconds(1),
        every interval: Duration = .milliseconds(250)
    ) -> QuitSweep {
        var sweep = QuitSweep()
        func lookAgain(_ scans: [ServerScan]) -> [ServerScan] {
            scans.map { ServerScan(server: $0.server, processes: scan($0.server)) }
        }

        sweep.serversStillUp = waitForServersToGo(stopping, scan: scan, every: interval)

        let found = serverless(scanEverything())
        sweep.found = found.flatMap(\.processes)
        guard !found.isEmpty else { return sweep }

        // Counted from the end of the first look, so every directory's two
        // lsof runs are at least `settle` apart whatever the first one took.
        Thread.sleep(forTimeInterval: seconds(settle))
        var left = stillServerless(lookAgain(found), of: found)
        sweep.askedToLeave = left.flatMap(\.processes)
        guard !left.isEmpty else { return sweep }
        for process in sweep.askedToLeave { signal(process.pid, SIGTERM) }

        let clock = ContinuousClock()
        let deadline = clock.now + grace
        repeat {
            Thread.sleep(forTimeInterval: seconds(interval))
            left = stillServerless(lookAgain(left), of: left)
        } while !left.isEmpty && clock.now < deadline

        sweep.ended = left.flatMap(\.processes)
        for process in sweep.ended { signal(process.pid, SIGKILL) }
        return sweep
    }

    private nonisolated static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }

    /// What became of the sweep a quit waited for.
    nonisolated enum QuitOutcome {
        /// CrossOver or Procyon was open, so nothing was looked at.
        case hostOpen
        case finished(QuitSweep)
        /// The bound passed first. The sweep's thread goes with the process.
        case gaveUp(after: Duration)
    }

    /// How long a quit waits for the sweep.
    ///
    /// Seven seconds: the second and a half the startup comment gives for lsof
    /// across every prefix, the three seconds between the two looks, a fifth
    /// of a second per condemned directory for the second look, the second of
    /// grace, and room for the last look. Plus what is left of the wait for a
    /// server this application asked to quit, and half a second for the look
    /// that ends that wait. A bound, so a lsof that does not return cannot
    /// hold a quit; not a measurement of how long a sweep takes. A quit that
    /// waits for no server and finds nothing without one takes one scan.
    nonisolated static func quitBound(waitingFor stopping: [Stopping],
                                      now: ContinuousClock.Instant = ContinuousClock.now) -> Duration {
        guard let latest = stopping.map(\.until).max() else { return .seconds(7) }
        return .seconds(7) + max(latest - now, .zero) + .milliseconds(500)
    }

    /// Run the sweep on a thread of its own and wait for it, up to `bound`.
    ///
    /// Blocking, because nothing after `willTerminate` waits for anything: the
    /// process exits once the observers return. The host check is made here,
    /// on the main thread, where NSWorkspace is asked; the sweep never touches
    /// the main thread, which is what makes waiting for it safe. The sweep is
    /// a parameter only so a test can hand it one that is slow or counts its
    /// calls.
    static func clearResidualBeforeQuitting(
        hostIsOpen: Bool,
        within bound: Duration = BottleProcesses.quitBound(waitingFor: []),
        sweep: @escaping @Sendable () -> QuitSweep = { BottleProcesses.clearResidualAtQuit() }
    ) -> QuitOutcome {
        guard !hostIsOpen else { return .hostOpen }
        let result = QuitSweepResult()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let finished = sweep()
            result.lock.lock()
            result.sweep = finished
            result.lock.unlock()
            done.signal()
        }
        guard done.wait(timeout: .now() + seconds(bound)) == .success else {
            return .gaveUp(after: bound)
        }
        result.lock.lock()
        defer { result.lock.unlock() }
        return result.sweep.map { .finished($0) } ?? .gaveUp(after: bound)
    }

    /// Where the sweep's thread leaves its answer for the waiting main thread.
    nonisolated final class QuitSweepResult: @unchecked Sendable {
        let lock = NSLock()
        var sweep: QuitSweep?
    }

    /// What the console says about a quit's sweep. Nothing, when there was
    /// nothing to find.
    nonisolated static func quitLines(for outcome: QuitOutcome) -> [String] {
        switch outcome {
        case .hostOpen:
            return ["at quit: crossover is open; leaving its processes alone"]
        case .gaveUp(let bound):
            return ["at quit: the look for wine processes whose server is gone did not finish within \(Int(seconds(bound))) s; the next start looks again"]
        case .finished(let sweep):
            var lines: [String] = []
            for server in sweep.serversStillUp {
                lines.append("at quit: the server asked to quit in \(server.lastPathComponent) was still up when the wait for it ended; leaving that bottle alone")
            }
            if !sweep.found.isEmpty, sweep.askedToLeave.isEmpty {
                lines.append("at quit: a second look found a server, or nothing, beside "
                             + sweep.found.map(\.name).sorted().joined(separator: ", ")
                             + "; leaving them alone")
            }
            if !sweep.askedToLeave.isEmpty {
                lines.append("at quit: asking \(sweep.askedToLeave.count) wine process(es) whose server is gone to leave: "
                             + sweep.askedToLeave.map(\.name).sorted().joined(separator: ", "))
            }
            for process in sweep.ended {
                lines.append("at quit: \(process.name) ignored the request; ending it")
            }
            return lines
        }
    }

    private static var quitObserver: NSObjectProtocol?

    /// Sweep at quit. Installed once; a second call does nothing.
    ///
    /// A crash, or a kill from outside, runs no observer, so the startup sweep
    /// stays: this one only means an ordinary quit does not leave the
    /// leftovers of a teardown it cut short waiting for the next start.
    static func sweepWhenQuitting() {
        guard quitObserver == nil else { return }
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                // Read once, so the sweep waits for exactly what the bound
                // was sized for.
                let stopping = serversAskedToQuit.stillGoing()
                let outcome = clearResidualBeforeQuitting(
                    hostIsOpen: aWineHostIsOpen,
                    within: quitBound(waitingFor: stopping),
                    sweep: { BottleProcesses.clearResidualAtQuit(stopping: stopping) })
                for line in quitLines(for: outcome) {
                    if case .finished = outcome { console.warn(line) } else { console.log(line) }
                }
            }
        }
    }
}
