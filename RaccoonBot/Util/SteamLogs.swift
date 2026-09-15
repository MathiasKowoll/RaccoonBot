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
        // Split on newlines, not on "\n".
        //
        // Steam writes these logs with CRLF, and in Swift "\r\n" is a single
        // Character -- one extended grapheme cluster, not equal to "\n". So
        // splitting on "\n" found no separator at all and handed back the whole
        // block as one enormous line. The parser then matched the first thing it
        // recognised in that block and skipped everything else, which is how a
        // game's start and its exit could arrive together and only the exit be
        // seen. Every test written for this used "\n" and so never met the
        // problem.
        return text.split(whereSeparator: \.isNewline).map(String.init)
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
    /// Every executable Steam has started for this application since it last
    /// started, in order, named the way the termination observer's name is
    /// read, so that the two can be compared.
    private(set) var startedExecutables: [String] = []

    /// What this log says about the application, for recognising it.
    ///
    /// This log is opened before the launch command runs and reads forward
    /// from there, so unlike the name read from the whole file, an earlier
    /// session cannot answer it.
    var identificationRecord: SteamLaunchIdentification.SteamRecord {
        guard let startedAt else { return .startedNothing }
        return .started(at: startedAt, executables: startedExecutables)
    }

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
                startedExecutables.removeAll()
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
                    if let named = SteamLaunchIdentification.trackedExecutable(in: line, appID: appID) {
                        startedExecutables.append(named)
                    }
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

/// Steam Cloud's exit sync as `cloud_log.txt` records it: when one has
/// begun, when it has ended, and when a wait for it is over.
///
/// The rules SteamCloudSyncWatcher has always waited by, kept apart from the
/// clock and the file so a Stop and a launch can wait by the same ones -- for
/// one title, or for every title whose exit sync is running -- and so every
/// answer can be tested without a Steam.
///
/// One rule is new. Steam writes a sync for a title's launch as well as for
/// its exit, and the wait used to end on the first line that ends a sync.
/// Lines read from a tail opened before an earlier session of the same title
/// had finished its exit sync ended the wait for the next exit sync at once,
/// with that earlier sync's last line. A launch sync -- "Starting sync (AC
/// Launch,down,)", in the Steam bottle's log on 2026-09-15 -- begins a new
/// session, so everything seen about that title's exit before it is
/// forgotten, and a batch of lines is read whole before anything is decided.
nonisolated struct SteamExitSync {
    enum Scope: Equatable, Sendable {
        /// One title's exit sync, the one its own teardown waits for.
        case app(String)
        /// Every title's, for a caller that does not know which title's to
        /// wait for. Steam runs more than one at a time: in the Steam
        /// bottle's log on 2026-09-15, 1369760 and 241100 each started an
        /// exit sync in the same second, twice.
        case anyApp

        func covers(_ app: String) -> Bool {
            switch self {
            case .app(let id): return id == app
            case .anyApp: return true
            }
        }
    }

    /// How long a wait gives Steam to begin an exit sync at all. Past it,
    /// cloud saves are off for the title or Steam is not signed in, and the
    /// rest of the deadline would only delay what follows.
    static let patience: TimeInterval = 15
    /// Steam writes an exit sync in one burst; once the titles waited for
    /// have been quiet this long, it is done, whatever words it finished with.
    static let quiet: TimeInterval = 6
    /// The most any exit sync is waited for.
    static let deadline: TimeInterval = 60

    let scope: Scope
    let started: Date
    /// Titles whose exit sync has begun and not ended.
    private(set) var underWay: Set<String>
    /// Titles whose exit sync has ended since the wait began.
    private(set) var ended: Set<String> = []
    /// "Need to upload file" lines per title, for the console.
    private(set) var uploads: [String: Int] = [:]
    /// When a title waited for last wrote anything.
    private(set) var lastHeard: Date

    /// `alreadyUnderWay` names the exit syncs a caller found running in the
    /// whole log before its tail was read -- see `underWay(inLog:...)`.
    init(scope: Scope, started: Date, alreadyUnderWay: Set<String> = []) {
        self.scope = scope
        self.started = started
        self.underWay = alreadyUnderWay
        self.lastHeard = started
    }

    var sawExitSync: Bool { !underWay.isEmpty || !ended.isEmpty }

    enum Event: Equatable {
        case began(app: String)
        case uploaded(app: String, files: Int)
        case upToDate(app: String)
        case failed(app: String, line: String)
    }

    mutating func observe(_ line: String, at now: Date) -> Event? {
        guard let app = Self.appID(in: line), scope.covers(app) else { return nil }
        lastHeard = now
        if Self.isLaunchSync(line) {
            underWay.remove(app)
            ended.remove(app)
            uploads[app] = nil
            return nil
        }
        if Self.isExitSyncStart(line) {
            underWay.insert(app)
            ended.remove(app)
            return .began(app: app)
        }
        if line.contains("Need to upload file") {
            uploads[app, default: 0] += 1
            return nil
        }
        guard underWay.contains(app), Self.isTerminal(line) else { return nil }
        underWay.remove(app)
        ended.insert(app)
        if line.contains("Failed sync") { return .failed(app: app, line: line) }
        let files = uploads[app] ?? 0
        return files > 0 ? .uploaded(app: app, files: files) : .upToDate(app: app)
    }

    enum Verdict: Equatable {
        case waiting
        /// Every exit sync seen has ended.
        case finished
        /// None began within the patience.
        case noExitSync
        /// One began, and the titles waited for have gone quiet.
        case wentQuiet
        /// The deadline came first.
        case outOfTime
    }

    func verdict(at now: Date) -> Verdict {
        if !ended.isEmpty && underWay.isEmpty { return .finished }
        if now.timeIntervalSince(started) >= Self.deadline { return .outOfTime }
        guard sawExitSync else {
            return now.timeIntervalSince(started) >= Self.patience ? .noExitSync : .waiting
        }
        return now.timeIntervalSince(lastHeard) > Self.quiet ? .wentQuiet : .waiting
    }

    /// The title a "[AppID N] ..." line is about.
    static func appID(in line: String) -> String? {
        guard let range = line.range(of: "[AppID ") else { return nil }
        let rest = line[range.upperBound...]
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, rest.dropFirst(digits.count).first == "]" else { return nil }
        return String(digits)
    }

    static func isExitSyncStart(_ line: String) -> Bool {
        line.contains("Starting sync (") && line.contains("AC Exit")
    }

    /// A sync for a title's launch, begun or refused.
    static func isLaunchSync(_ line: String) -> Bool {
        line.contains("AC Launch")
    }

    /// The lines Steam ends an exit sync with.
    ///
    /// Counted in this machine's two cloud logs rather than guessed at, which
    /// is how the first version of this went wrong: it knew "Upload complete in
    /// build list" and not "Upload complete, result OK", so a real upload that
    /// finished in six seconds went unrecognised and the teardown sat waiting
    /// for three minutes. Hence the prefix, and hence the quiet fallback: a
    /// phrase list is only ever as complete as the logs you have read.
    static func isTerminal(_ line: String) -> Bool {
        line.contains("Successfully synced")
            || line.contains("Upload complete")
            || line.contains("Failed sync for")
    }

    /// When a line was written, from the "[yyyy-MM-dd HH:mm:ss]" it opens
    /// with, read in `timeZone`.
    ///
    /// This Mac's local time by default: the Steam bottle's cloud_log.txt was
    /// last modified at 00:54:38 -0300 on 2026-09-15, and its last line opens
    /// with [2026-09-15 00:54:38].
    static func timestamp(of line: String, timeZone: TimeZone = .current) -> Date? {
        guard line.first == "[", let close = line.firstIndex(of: "]") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: String(line[line.index(after: line.startIndex)..<close]))
    }

    /// The titles with an exit sync running, read from the whole log: begun,
    /// not ended, and no launch sync since.
    ///
    /// For a caller that arrives after the sync began -- a launch or a Stop
    /// that follows a game which exited on its own seconds earlier -- and so
    /// cannot have had a tail open for its first line.
    ///
    /// Only a sync begun within `within` of `now` counts. The log is
    /// cumulative, and a sync that Steam never finished, because it was ended
    /// in the middle, stays open in it for good. The deadline is the chosen
    /// bound, because it is the most any wait gives an exit sync; a sync begun
    /// before it has already had what a teardown would give it. A line whose
    /// time cannot be read does not count.
    static func underWay(inLog content: String, scope: Scope, now: Date,
                         within: TimeInterval = deadline,
                         timeZone: TimeZone = .current) -> Set<String> {
        var begun: [String: Date] = [:]
        var open: Set<String> = []
        for piece in content.split(whereSeparator: \.isNewline) {
            let line = String(piece)
            guard let app = appID(in: line), scope.covers(app) else { continue }
            if isLaunchSync(line) || isTerminal(line) {
                open.remove(app)
                begun[app] = nil
            } else if isExitSyncStart(line) {
                open.insert(app)
                begun[app] = timestamp(of: line, timeZone: timeZone)
            }
        }
        return open.filter { app in
            guard let at = begun[app] else { return false }
            return now.timeIntervalSince(at) <= within
        }
    }
}
