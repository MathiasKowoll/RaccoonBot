//
//  EpicSession.swift
//  RaccoonBot
//
//  What happens after an Epic title exits, so that its saves survive it.
//
//  Steam's exit is understood: it writes an exit sync to cloud_log.txt within
//  the second the game stops, and SteamCloudSyncWatcher waits for that to end
//  before Steam is asked to leave and the bottle is closed. Epic's launcher
//  does the same kind of upload after a game exits -- and killing it in the
//  middle leaves the cloud copy behind what was played, the same failure that
//  has already cost real Steam saves here.
//
//  The launcher's vocabulary for it is NOT yet measured: as of 2026-09-02 no
//  game had run through the launcher in this bottle, and its log holds no
//  cloud-save line to learn from. So the wait is the quiet rule Steam's
//  watcher also has as its fallback -- the launcher writes an exit sync in one
//  burst; once it has been silent for a few seconds it is done, whatever words
//  it finished with -- bounded by a deadline, and everything the launcher
//  writes in that window is put in the console so the first real session
//  teaches the phrase. When it does, `isTerminal` is where it goes.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// The decision, kept apart from the clock and the file so it can be tested
/// with neither.
nonisolated struct EpicSettle {
    /// How long the launcher may stay silent before it is taken to be done.
    let quiet: TimeInterval
    /// How long to wait for it to say anything at all. Cloud saves may be off
    /// for the title, or the launcher not signed in; then there is no sync
    /// coming and the full deadline would only delay the teardown.
    let patience: TimeInterval
    let deadline: TimeInterval

    let started: Date
    private(set) var lastHeard: Date?
    private(set) var heard = 0

    init(started: Date, quiet: TimeInterval = 5, patience: TimeInterval = 15, deadline: TimeInterval = 60) {
        self.started = started
        self.quiet = quiet; self.patience = patience; self.deadline = deadline
    }

    mutating func observe(line: String, at now: Date) {
        heard += 1
        lastHeard = now
    }

    /// The line the launcher ends a save sync with.
    ///
    /// Measured on 2026-09-03, from this machine's own sessions, which is why
    /// this was left answering false until then: the launcher writes
    ///
    ///     LogCloudSync: Cloud Sync: Sync Started for <ns>:<item>:<app>
    ///     LogCloudSync: Cloud Sync: Exiting Cloud Sync - SUCCESS - AppName: <ns>:<item>:<app>
    ///
    /// once before it launches a title, pulling the cloud copy down, and again
    /// when the title exits, pushing it back up. "Exiting" is what is matched
    /// rather than "SUCCESS", for the same reason the Steam watcher accepts
    /// "Failed sync for": a sync that ended badly has still ended, and waiting
    /// past it buys nothing.
    static func isTerminal(_ line: String) -> Bool {
        line.contains("Exiting Cloud Sync")
    }

    /// Whether the launcher's log ends in a save sync that has begun and not
    /// ended: "Cloud Sync: Sync Started for" with no "Exiting Cloud Sync"
    /// after it, the pair measured on 2026-09-10 in the Steam bottle's log.
    ///
    /// For a caller that arrives after the sync began and so had no tail open
    /// for its first line. No clock is needed, unlike Steam's cumulative
    /// log: the launcher opens a fresh log every time it starts -- see
    /// EpicReadiness.header -- and this is asked only while it is running, so
    /// the log is this launcher's own. A sync that never ends is bounded by
    /// the wait that follows, not by this.
    static func syncUnderWay(inLog content: String) -> Bool {
        var open = false
        for piece in content.split(whereSeparator: \.isNewline) {
            let line = String(piece)
            if line.contains("Cloud Sync: Sync Started for") {
                open = true
            } else if isTerminal(line) {
                open = false
            }
        }
        return open
    }

    enum Verdict: Equatable { case waiting, settled(String) }

    func verdict(at now: Date) -> Verdict {
        if now.timeIntervalSince(started) >= deadline { return .settled("the launcher was given \(Int(deadline))s") }
        guard let lastHeard else {
            return now.timeIntervalSince(started) >= patience
                ? .settled("the launcher said nothing for \(Int(patience))s; no exit sync is coming")
                : .waiting
        }
        return now.timeIntervalSince(lastHeard) >= quiet
            ? .settled("the launcher has been quiet for \(Int(quiet))s after \(heard) line\(heard == 1 ? "" : "s")")
            : .waiting
    }
}

/// Follows the launcher's own log from the moment the game starts, as the
/// Steam watcher does -- built at teardown time it would begin reading after
/// the lines it needs have gone by.
final class EpicLauncherLogWatcher {
    static func logURL(inBottleAt bottle: URL) -> URL {
        bottle.appendingPathComponent("drive_c/users/crossover/AppData/Local/EpicGamesLauncher/Saved/Logs/EpicGamesLauncher.log")
    }

    private let tail: SteamLogTail
    init(bottle: URL) {
        tail = SteamLogTail(url: Self.logURL(inBottleAt: bottle))
    }

    /// The executable the launcher says it is starting, out of its own line.
    ///
    /// Measured 2026-09-03; the launcher writes a pair, and it is the second
    /// that means it actually went:
    ///
    ///     FCommunityPortalLaunchAppTask: Preparing to launch app 'Z:/.../AlanWake2.exe' with commandline ...
    ///     FCommunityPortalLaunchAppTask: Launching app 'Z:/.../AlanWake2.exe' with commandline ...
    ///
    /// "Preparing to launch" is deliberately not accepted: it is written for
    /// a launch that may still fail, and this answer starts a clock.
    static func launchedExecutable(in line: String) -> String? {
        guard line.contains("FCommunityPortalLaunchAppTask"),
              line.contains("Launching app"),
              !line.contains("Preparing to launch") else { return nil }
        // The path is the first thing in single quotes.
        guard let open = line.firstIndex(of: "'") else { return nil }
        let rest = line[line.index(after: open)...]
        guard let close = rest.firstIndex(of: "'") else { return nil }
        let path = String(rest[..<close])
        guard !path.isEmpty else { return nil }
        // Written with forward slashes here, whatever the manifest says.
        let name = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init)
        return (name?.isEmpty ?? true) ? nil : name
    }

    /// One look at whatever the launcher has written since the last look: the
    /// executable it says it started, if it said so.
    ///
    /// A single pass rather than a loop, so the caller can watch the bottle
    /// for the same fact at the same time -- see the Epic block in
    /// getGameTracker. The Epic half of what SteamLaunchWatcher does: a title
    /// started through the launcher is not started by us, so the only party
    /// that knows its executable by name is the launcher.
    func launchedExecutableInNewLines() -> String? {
        for line in tail.newLines() {
            if let exe = Self.launchedExecutable(in: line) { return exe }
        }
        return nil
    }

    /// Read everything written up to now and throw it away.
    ///
    /// Called the moment a game is known to have started, and it is what
    /// stops a save being lost. The launcher syncs saves TWICE around a
    /// session -- pulling before it launches, pushing after the title exits
    /// -- and both write the same "Exiting Cloud Sync" line. If the pull's
    /// line is still sitting unread when the teardown starts waiting for the
    /// push's, the wait is satisfied by the wrong one instantly, the launcher
    /// is asked to leave mid-upload, and the cloud copy keeps whatever it had
    /// before this session. Everything written before the game started is
    /// about the past, so it can all go.
    func drainPastLaunch() {
        _ = tail.newLines()
    }

    /// What the tail has to offer right now. Exposed so a test can state what
    /// the drain left behind, which is the whole point of the drain.
    func linesForTesting() -> [String] { tail.newLines() }

    /// Wait for the launcher to finish whatever it does when a game exits.
    func waitForLauncherToSettle() async throws {
        var settle = EpicSettle(started: Date())
        var shown = 0
        while true {
            for line in tail.newLines() {
                settle.observe(line: line, at: Date())
                // The record the next reader learns the vocabulary from.
                // Bounded: a launcher that decides to verify a game writes
                // thousands of lines, and they are not what is asked here.
                if shown < 40 {
                    console.log("epic launcher: \(line.prefix(200))")
                    shown += 1
                }
                if EpicSettle.isTerminal(line) {
                    console.log("epic: the launcher says the exit sync is done")
                    return
                }
            }
            if case .settled(let why) = settle.verdict(at: Date()) {
                console.log("epic: \(why)")
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}
