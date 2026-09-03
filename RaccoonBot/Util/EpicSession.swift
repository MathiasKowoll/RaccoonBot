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

    /// The lines the launcher is known to end an exit sync with. Empty until
    /// a real session has been read -- see the header. A guess here would be
    /// read back as a measurement.
    static func isTerminal(_ line: String) -> Bool { false }

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
