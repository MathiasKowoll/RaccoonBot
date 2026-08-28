import Foundation

/// Reads a Steam log forward from where it was when we started looking.
///
/// Steam's logs are cumulative: `cloud_log.txt` holds every sync of the whole
/// session. The cloud-sync wait used to scan the entire file for "Successfully
/// synced", so it matched a line belonging to an earlier game and reported the
/// upload finished about a tenth of a second after being asked -- every time,
/// without ever waiting for anything.
///
/// Anything that decides something must read only what was written after it
/// started reading.
final class SteamLogTail {
    let url: URL
    private var offset: UInt64

    /// Starts at the current end of the file. Everything already there belongs
    /// to the past and says nothing about this session.
    init(url: URL) {
        self.url = url
        if let handle = try? FileHandle(forReadingFrom: url) {
            offset = (try? handle.seekToEnd()) ?? 0
            try? handle.close()
        } else {
            offset = 0
        }
    }

    /// Complete lines written since the last call.
    ///
    /// A line still being written is left for next time: half a line has been
    /// enough to fool this code once already.
    func newLines() -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        // Steam rotates its logs when it restarts; a shorter file is a new one.
        if end < offset { offset = 0 }
        guard end > offset else { return [] }

        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }

        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
        let complete = data[data.startIndex...lastNewline]
        offset += UInt64(complete.count)

        guard let text = String(data: complete, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

/// What Steam says it started and stopped for one application.
enum SteamProcessEvent {
    case started(pid: Int, path: String)
    case stopped(pid: Int, exitCode: Int)
    /// Steam's own statement that the application is over: "Remove N from
    /// running list". It names no executable, so a launcher handing off cannot
    /// produce it.
    case sessionEnded
}

/// Which processes Steam currently has tracked for one application, kept from
/// `gameprocess_log.txt` as the lines arrive.
///
/// Steam's own "Remove <id> from running list" looks like the answer and is
/// not. It fires whenever the tracked set momentarily empties, and for a game
/// whose launcher chain restarts itself that happens mid-launch. Red Dead
/// Redemption 2 produces it one second into every launch -- the Rockstar
/// launcher, its service and PlayRDR2 all exit, Steam declares the app gone,
/// and one second later the chain begins again. `RDR2.exe` appears
/// forty-four seconds after Steam said the application was over.
///
/// So the set emptying is a question, not an answer. The answer is the set
/// staying empty.
final class SteamGameProcessLog {
    private let tail: SteamLogTail
    private let appID: String

    /// The PIDs Steam has tracked, per AppID, and not yet released.
    ///
    /// Every app is followed, not just ours, because the bottle is shared: a
    /// teardown decided for one game would take another game down with it.
    private(set) var trackedByApp: [String: Set<Int>] = [:]

    /// The PIDs Steam has tracked for this app and not yet released.
    var tracked: Set<Int> { trackedByApp[appID] ?? [] }

    /// Another application using this bottle right now, if there is one.
    var otherAppRunning: String? {
        trackedByApp.first { $0.key != appID && !$0.value.isEmpty }?.key
    }
    /// Set once the app has been seen running at all; before that, an empty set
    /// means "not started yet", which is not the same as finished.
    private(set) var everStarted = false
    /// When the set last became empty, or nil while it holds anything.
    private(set) var emptySince: Date?
    /// When this application's first process appeared.
    private(set) var startedAt: Date?
    /// How the last process of this application ended.
    private(set) var lastExitCode: Int?

    init(steamPath: String, steamID: String) {
        self.appID = steamID
        self.tail = SteamLogTail(url: URL(fileURLWithPath: "\(steamPath)/logs/gameprocess_log.txt"))
    }

    @discardableResult
    func poll(now: Date = Date()) -> [SteamProcessEvent] {
        var events: [SteamProcessEvent] = []
        for line in tail.newLines() {
            // Steam restarted: everything it knew is void.
            if line.contains("Client version:") {
                trackedByApp.removeAll()
                everStarted = false
                emptySince = nil
                startedAt = nil
                continue
            }
            if line.contains("Remove \(appID) from running list") {
                events.append(.sessionEnded)
                continue
            }
            // Steam has a second way of saying a process ended, used when it
            // takes the app down itself rather than noticing it exit:
            //   "Game 2492670 going away; no longer tracking PID 1664"
            // Not knowing it left the tracked set holding processes that were
            // already dead, so it never emptied -- and MGS4, whose launcher
            // exits this way, became invisible to every judgement made here.
            if let app = Self.number(after: "Game ", in: line),
               line.contains("going away"),
               let pid = Self.integer(after: "no longer tracking PID ", in: line) {
                trackedByApp[app, default: []].remove(pid)
                if app == appID { events.append(.stopped(pid: pid, exitCode: 0)) }
                continue
            }

            guard let app = Self.appID(in: line) else { continue }
            let ours = app == appID

            if let pid = Self.integer(after: "adding PID ", in: line) {
                trackedByApp[app, default: []].insert(pid)
                if ours {
                    if !everStarted { startedAt = now }
                    everStarted = true
                    emptySince = nil
                    lastExitCode = nil
                    events.append(.started(pid: pid, path: Self.quotedPath(in: line) ?? "unknown"))
                }
            } else if let pid = Self.integer(after: "no longer tracking PID ", in: line) {
                trackedByApp[app, default: []].remove(pid)
                if ours {
                    let code = Self.integer(after: "exit code ", in: line) ?? 0
                    lastExitCode = code
                    events.append(.stopped(pid: pid, exitCode: code))
                }
            }
        }
        if everStarted && tracked.isEmpty {
            if emptySince == nil { emptySince = now }
        } else {
            emptySince = nil
        }
        return events
    }

    /// Did the last thing to stop crash, rather than exit?
    ///
    /// Windows reports an unhandled exception as the process's exit status, and
    /// those codes are unmistakable: 0xC0000005 for an access violation,
    /// 0xC0000374 for a corrupted heap, 0xC0000409 for a smashed stack. Every
    /// launcher handing off in this machine's history exited 0, 1 or 3 -- never
    /// one of these. So a game that ended this way is not a launcher chain
    /// about to come back; it is a game that fell over, and there is nothing to
    /// wait for.
    var lastExitWasACrash: Bool {
        guard let lastExitCode else { return false }
        return lastExitCode <= -1_000_000
    }

    /// How long this application ran before everything stopped.
    var sessionLength: TimeInterval {
        guard let startedAt, let emptySince else { return 0 }
        return emptySince.timeIntervalSince(startedAt)
    }

    /// Has this application had nothing running for long enough to be over?
    ///
    /// The wait is what separates a launcher chain restarting from a session
    /// ending. It is long because the evidence says it has to be: the widest
    /// mid-launch gap seen in this machine's history is forty-four seconds.
    func hasBeenIdle(for seconds: TimeInterval, now: Date = Date()) -> Bool {
        guard let emptySince else { return false }
        return now.timeIntervalSince(emptySince) >= seconds
    }

    /// The digits following a marker, as a string.
    private static func number(after marker: String, in line: String) -> String? {
        guard let range = line.range(of: marker) else { return nil }
        let digits = line[range.upperBound...].prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    /// The AppID a "AppID N ..." line is about.
    private static func appID(in line: String) -> String? {
        guard let range = line.range(of: "AppID ") else { return nil }
        let digits = line[range.upperBound...].prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    private static func integer(after marker: String, in line: String) -> Int? {
        guard let range = line.range(of: marker) else { return nil }
        let rest = line[range.upperBound...]
        let digits = rest.prefix { $0.isNumber || $0 == "-" }
        return Int(digits)
    }

    /// The executable path Steam quotes, which arrives with doubled quotes.
    private static func quotedPath(in line: String) -> String? {
        guard let open = line.firstIndex(of: "\"") else { return nil }
        let rest = line[line.index(after: open)...]
        let path = rest.drop { $0 == "\"" }.prefix { $0 != "\"" }
        return path.isEmpty ? nil : String(path)
    }
}

/// Why a game process stopped, for the log.
func describeExit(code: Int) -> String {
    switch code {
    case 0: return "cleanly"
    case -1073741819: return "with an access violation (0xC0000005)"
    case -1073741510: return "interrupted (0xC000013A)"
    default: return "with exit code \(code)"
    }
}
