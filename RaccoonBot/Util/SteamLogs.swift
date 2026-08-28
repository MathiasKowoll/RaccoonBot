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

/// A live reading of `gameprocess_log.txt`, which is where Steam records every
/// executable it starts for an app and the code each one exits with.
///
/// This is the account the launcher should have been using all along. It says
/// which process belongs to which AppID, and it says when the AppID itself is
/// finished -- separately from any individual process ending.
final class SteamGameProcessLog {
    private let tail: SteamLogTail
    private let appID: String

    init(steamPath: String, steamID: String) {
        self.appID = steamID
        self.tail = SteamLogTail(url: URL(fileURLWithPath: "\(steamPath)/logs/gameprocess_log.txt"))
    }

    func newEvents() -> [SteamProcessEvent] {
        var events: [SteamProcessEvent] = []
        for line in tail.newLines() {
            if line.contains("Remove \(appID) from running list") {
                events.append(.sessionEnded)
                continue
            }
            guard line.contains("AppID \(appID) ") else { continue }

            if let pid = Self.integer(after: "adding PID ", in: line) {
                events.append(.started(pid: pid, path: Self.quotedPath(in: line) ?? "unknown"))
            } else if let pid = Self.integer(after: "no longer tracking PID ", in: line) {
                let code = Self.integer(after: "exit code ", in: line) ?? 0
                events.append(.stopped(pid: pid, exitCode: code))
            }
        }
        return events
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
