import Foundation
import AppKit

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
        return processes(holding: server)
    }

    /// Everything holding one wineserver directory open.
    static func processes(holding server: URL) -> [Running] {
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

    /// What wine always runs. Short, and it does not change.
    static let wineFurniture: Set<String> = [
        "wineserver", "winewrapper.exe", "services.exe", "winedevice.exe",
        "plugplay.exe", "rpcss.exe", "explorer.exe", "svchost.exe",
        "conhost.exe", "start.exe", "wineboot.exe", "rundll32.exe",
        "tabtip.exe", "winemenubuilder.exe",
    ]

    private static let steamCacheLock = NSLock()
    private static var steamCache: [String: Set<String>] = [:]

    /// Steam's own executables, read from the Steam that is about to run.
    ///
    /// This used to be a list written out by hand, and a list written out by
    /// hand is wrong the moment Steam ships something new. It was: the overlay,
    /// `gameoverlayui64.exe`, was missing, so the guard took Steam's own window
    /// for a game and refused to close the bottle -- for as long as Steam was
    /// running, which is to say forever.
    ///
    /// Asking the directory instead costs a twentieth of a second and cannot go
    /// stale. There are twenty-five of them in this bottle, and the answer is
    /// remembered per bottle after the first look.
    static func steamsOwnExecutables(inBottleAt bottle: URL) -> Set<String> {
        let key = bottle.path(percentEncoded: false)
        steamCacheLock.lock()
        if let known = steamCache[key] { steamCacheLock.unlock(); return known }
        steamCacheLock.unlock()

        let steam = bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam")
        var names: Set<String> = []
        if let walker = FileManager.default.enumerator(
            at: steam, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let file as URL in walker where file.pathExtension.lowercased() == "exe" {
                names.insert(file.lastPathComponent.lowercased())
            }
        }
        steamCacheLock.lock()
        steamCache[key] = names
        steamCacheLock.unlock()
        return names
    }

    /// Anything running in this bottle that belongs to neither wine nor Steam.
    ///
    /// The last word before a teardown. Every judgement above this one is made
    /// from a log, and a log can be misread or be a minute out of date -- which
    /// is how a relaunched MGS4 got killed by a decision taken about the attempt
    /// before it. This asks the machine instead of the record.
    static func gamesRunning(inBottleAt bottle: URL) -> [String] {
        let steams = steamsOwnExecutables(inBottleAt: bottle)
        return running(inBottleAt: bottle)
            .map(\.name)
            .filter { name in
                let lower = name.lowercased()
                return !wineFurniture.contains(lower) && !steams.contains(lower)
            }
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

    /// Applications that run wine themselves.
    ///
    /// While one of these is open, a wine process is not a leftover -- somebody
    /// is using it. Every CrossOver on this machine reports the same identifier,
    /// patched copies included, so one name covers all of them.
    static let wineHosts: Set<String> = [
        "com.codeweavers.CrossOver",
        "itmandar.Procyon",
    ]

    static var aWineHostIsOpen: Bool {
        NSWorkspace.shared.runningApplications.contains {
            guard let id = $0.bundleIdentifier else { return false }
            return wineHosts.contains(id)
        }
    }

    /// Every wine process on this machine whose server is gone.
    ///
    /// Wine keeps one directory per prefix, named after that prefix's device
    /// and inode, and every process of the prefix holds files open inside it.
    /// A directory with processes but no `wineserver` is a prefix nobody is
    /// running any more: what is left there outlived whatever owned it.
    static func residualEverywhere() -> [Running] {
        let root = URL(fileURLWithPath: "/private/tmp/.wine-\(getuid())")
        guard let servers = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return [] }

        var found: [Running] = []
        for server in servers where server.lastPathComponent.hasPrefix("server-") {
            let here = processes(holding: server)
            guard !here.isEmpty else { continue }
            guard !here.contains(where: { $0.name.contains("wineserver") }) else { continue }
            found.append(contentsOf: here)
        }
        return found
    }

    /// What somebody left behind, cleared at startup.
    ///
    /// A game that was force-quit, or this application closed before a bottle
    /// finished coming down, leaves wine services holding that bottle's devices
    /// and registry -- and the next launch fails because of them. One survived
    /// exactly that way tonight: a winedevice.exe with no parent, still there
    /// half an hour later.
    ///
    /// Nothing is touched while a CrossOver or Procyon window is open. Those
    /// run wine on purpose, and what looks like debris from here is somebody
    /// else's game.
    static func clearResidualAtStartup() async {
        guard !aWineHostIsOpen else {
            console.log("crossover is open; leaving its processes alone")
            return
        }
        let residual = residualEverywhere()
        guard !residual.isEmpty else { return }

        console.warn("clearing \(residual.count) wine process(es) left from before: "
                     + residual.map(\.name).sorted().joined(separator: ", "))
        for process in residual { kill(process.pid, SIGTERM) }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        for process in residualEverywhere() {
            console.warn("\(process.name) ignored the request; ending it")
            kill(process.pid, SIGKILL)
        }
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
