import Foundation

/// The processes belonging to one bottle, and how to end them without touching
/// anything else.
///
/// A wine process does not carry its bottle anywhere macOS will show us: `ps -E`
/// refuses another process's environment, and a child reports a Windows path
/// like `C:\windows\system32\winedevice.exe` that names no prefix at all. So
/// the old teardown matched on `.exe` and killed machine-wide, which is how a
/// mistake about one game became a mistake about every bottle.
///
/// But every process of a prefix holds files open in the directory wine derives
/// from that prefix's device and inode, and `lsof` will say who they are. That
/// is exact, it is fast -- a fifth of a second, because the directory is small
/// and belongs to one bottle -- and it cannot name a process from anywhere else.
enum BottleProcesses {

    /// Where wine keeps the server for a bottle: `server-<dev>-<ino>` in hex,
    /// under `.wine-<uid>` in the temporary directory.
    static func serverDirectory(ofBottleAt bottle: URL) -> URL? {
        let path = bottle.path(percentEncoded: false)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let device = attrs[.systemNumber] as? Int,
              let inode = attrs[.systemFileNumber] as? Int else { return nil }
        return URL(fileURLWithPath:
            "/private/tmp/.wine-\(getuid())/server-\(String(device, radix: 16))-\(String(inode, radix: 16))")
    }

    struct Running {
        let pid: pid_t
        let name: String
    }

    /// Everything holding this bottle's server open.
    static func running(inBottleAt bottle: URL) -> [Running] {
        guard let server = serverDirectory(ofBottleAt: bottle),
              FileManager.default.fileExists(atPath: server.path(percentEncoded: false))
        else { return [] }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-Fpc", "+D", server.path(percentEncoded: false)]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        task.waitUntilExit()

        // lsof -F emits one field per line: "p<pid>" then "c<command>".
        var found: [pid_t: String] = [:]
        var pid: pid_t?
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            if line.hasPrefix("p") { pid = pid_t(line.dropFirst()) }
            else if line.hasPrefix("c"), let pid { found[pid] = String(line.dropFirst()) }
        }
        return found.map { Running(pid: $0.key, name: $0.value) }.sorted { $0.pid < $1.pid }
    }

    /// Is the server that owns these processes still alive?
    ///
    /// While it is, they belong to a live session and are nobody else's to end.
    /// Once it is gone they are orphans: they keep the bottle's devices and
    /// registry claimed, and the next launch fails because of them.
    static func serverIsAlive(inBottleAt bottle: URL) -> Bool {
        running(inBottleAt: bottle).contains { $0.name.contains("wineserver") }
    }

    /// End what is left of a bottle, and nothing outside it.
    ///
    /// Asks first, then insists. Returns what would not go.
    @discardableResult
    static func end(inBottleAt bottle: URL, gracePeriod: TimeInterval = 3) async -> [Running] {
        let doomed = running(inBottleAt: bottle)
        guard !doomed.isEmpty else { return [] }

        console.warn("ending \(doomed.count) leftover process(es) of this bottle: "
                     + doomed.map(\.name).joined(separator: ", "))
        for process in doomed { kill(process.pid, SIGTERM) }

        try? await Task.sleep(nanoseconds: UInt64(gracePeriod * 1_000_000_000))

        let stubborn = running(inBottleAt: bottle)
        for process in stubborn {
            console.warn("\(process.name) ignored the request; ending it")
            kill(process.pid, SIGKILL)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        return running(inBottleAt: bottle)
    }

    /// Clear orphans left by a previous session, before starting a new one.
    ///
    /// These are what make the next launch fail: wine services outliving the
    /// server that owned them, still holding the bottle's devices. Nothing is
    /// touched while a server is alive -- that is somebody's game.
    static func clearOrphans(inBottleAt bottle: URL) async {
        let left = running(inBottleAt: bottle)
        guard !left.isEmpty else { return }
        guard !left.contains(where: { $0.name.contains("wineserver") }) else {
            console.log("this bottle is already in use; leaving it alone")
            return
        }
        console.warn("clearing \(left.count) orphan(s) from a previous session: "
                     + left.map(\.name).joined(separator: ", "))
        await end(inBottleAt: bottle)
    }
}
