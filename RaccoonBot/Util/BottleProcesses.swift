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
    nonisolated static func serverDirectory(ofBottleAt bottle: URL) -> URL? {
        let path = bottle.path(percentEncoded: false)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let device = attrs[.systemNumber] as? Int,
              let inode = attrs[.systemFileNumber] as? Int else { return nil }
        return URL(fileURLWithPath:
            "/private/tmp/.wine-\(getuid())/server-\(String(device, radix: 16))-\(String(inode, radix: 16))")
    }

    nonisolated struct Running {
        let pid: pid_t
        let name: String
    }

    /// Which of the condemned are still there.
    ///
    /// A second scan of a bottle finds whatever is in it now, which is not the
    /// same set as the one that was asked to leave. Anything that arrived in
    /// between never received the request, so killing it for ignoring one is
    /// both wrong and silent -- and the thing that arrives in practice is a fix
    /// installer, which starts a short-lived wineserver to run `reg.exe add`.
    /// Killing that between `add` returning 0 and the flush leaves the script
    /// reporting success with some of its keys missing.
    ///
    /// Matched on pid AND name, so a pid the system has reused since the first
    /// scan is not condemned for the sins of whoever held it before.
    static func stillThere(_ current: [Running], of condemned: [Running]) -> [Running] {
        let sentenced = Dictionary(condemned.map { ($0.pid, $0.name) },
                                   uniquingKeysWith: { first, _ in first })
        return current.filter { sentenced[$0.pid] == $0.name }
    }

    /// Everything holding this bottle's server open.
    ///
    /// `nonisolated`, with the two below it: a scan runs lsof and waits for
    /// it, and the wait before a launch asks from off the main actor.
    nonisolated static func running(inBottleAt bottle: URL) -> [Running] {
        guard let server = serverDirectory(ofBottleAt: bottle),
              FileManager.default.fileExists(atPath: server.path(percentEncoded: false))
        else { return [] }
        return processes(holding: server)
    }

    /// Everything holding one wineserver directory open.
    nonisolated static func processes(holding server: URL) -> [Running] {
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
    nonisolated static let wineFurniture: Set<String> = [
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

    /// The Epic launcher's own executables, by the same reasoning as Steam's:
    /// the launcher, its web helper, the overlay and the EOS service all run
    /// while a game does and after it, and none of them is the game. Left in
    /// the count, the teardown after an Epic title would have refused forever
    /// -- "EpicGamesLauncher.exe is running in this bottle" -- and the window
    /// would never have been released.
    static func launchersOwnExecutables(inBottleAt bottle: URL) -> Set<String> {
        let key = "epic:" + bottle.path(percentEncoded: false)
        steamCacheLock.lock()
        if let known = steamCache[key] { steamCacheLock.unlock(); return known }
        steamCacheLock.unlock()

        // The whole of "Epic Games", not just "Launcher".
        //
        // Epic Online Services installs beside the launcher, not inside it:
        // the EOS host is a registered wine service in this prefix
        // (System\CurrentControlSet\Services\EpicOnlineServices, demand
        // start), and it, its three helpers and the overlay renderer all
        // outlive a title. Scanning only Launcher/ left every one of them
        // counted as the game, so an Epic session never read as over: the
        // bottle stayed up, the loader never released, and playingID stayed
        // pinned so the title could not be played again. Exactly the failure
        // the Steam comment above records for the missing overlay, repeated.
        // DirectXRedist and any Launcher.old-* copy come along, which is
        // right: none of them is a game either.
        let launcher = bottle.appendingPathComponent("drive_c/Program Files (x86)/Epic Games")
        var names: Set<String> = []
        if let walker = FileManager.default.enumerator(
            at: launcher, includingPropertiesForKeys: nil,
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

    /// Anything running in this bottle that belongs to neither wine, nor
    /// Steam, nor the Epic launcher.
    ///
    /// The last word before a teardown. Every judgement above this one is made
    /// from a log, and a log can be misread or be a minute out of date -- which
    /// is how a relaunched MGS4 got killed by a decision taken about the attempt
    /// before it. This asks the machine instead of the record.
    /// How much of a process name lsof will tell us.
    ///
    /// Its -F command field is capped, and the cap is the kernel's, so it
    /// cannot be worked around by asking differently: measured on this
    /// machine, every name of 31 characters or more comes back at exactly 31.
    /// It matters here because Epic ships names past it --
    /// `EOSOverlayRenderer-Win64-Shipping.exe` is 37 -- and a name compared
    /// at full length against a truncated one never matches, so the overlay
    /// would have been counted as the game however wide the walk above went.
    nonisolated static let lsofNameLimit = 31

    /// Anything running in this bottle that belongs to neither wine, nor
    /// Steam, nor the Epic launcher.
    ///
    /// The last word before a teardown. Every judgement above this one is made
    /// from a log, and a log can be misread or be a minute out of date -- which
    /// is how a relaunched MGS4 got killed by a decision taken about the attempt
    /// before it. This asks the machine instead of the record.
    static func gamesRunning(inBottleAt bottle: URL) -> [String] {
        let known = wineFurniture
            .union(steamsOwnExecutables(inBottleAt: bottle))
            .union(launchersOwnExecutables(inBottleAt: bottle))
        // Compared at the length lsof is willing to report, in both
        // directions: a known name longer than the cap is stored cut down to
        // it, and the running name is cut the same way before the comparison.
        let knownAtLimit = Set(known.map { String($0.prefix(lsofNameLimit)) })
        return running(inBottleAt: bottle)
            .map(\.name)
            .filter { name in
                let lower = name.lowercased()
                return !known.contains(lower) && !knownAtLimit.contains(String(lower.prefix(lsofNameLimit)))
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

    /// May this launch rewrite the bottle's registry files?
    ///
    /// Not while a wineserver is alive in the bottle. wineserver holds its own
    /// copy of the registry in memory and flushes it when it shuts down, so a
    /// write underneath it is lost at best -- its copy wins -- and at worst
    /// lands in the middle of that flush, on a file of 160,000 lines that the
    /// bottle cannot be repaired without. It is the same rule the fix installer
    /// keeps (`EpicImport` refuses a live bottle outright), and it costs
    /// nothing: winebus reads the values we set when the bottle boots, so a
    /// bottle that is already up is using what it booted with whatever we
    /// write. The answer for the owner is to close the launcher and start
    /// again, not for us to write harder.
    static func registryIsOursToWrite(inBottleAt bottle: URL) -> Bool {
        registryIsOursToWrite(serverIsAlive: serverIsAlive(inBottleAt: bottle))
    }

    /// The rule itself, taking the measurement rather than making it, so both
    /// of its answers can be read and tested without a live bottle.
    static func registryIsOursToWrite(serverIsAlive alive: Bool) -> Bool { !alive }

    /// What wine puts up in a bottle for its own sake: the furniture above,
    /// and the short-lived tools a fix installer runs through wine, taken from
    /// the list `MGVFCoordinator` already keeps for the same judgement rather
    /// than written out a second time. Not one of them is the user's.
    nonisolated static let wineOwn: Set<String> = wineFurniture.union(MGVFCoordinator.Running.furniture)

    /// Whose a bottle is at this moment, as far as a launch into it cares.
    nonisolated enum Occupancy: Equatable {
        /// No wineserver is alive in it, so the next wine command starts one
        /// of its own. Anything still holding the directory outlived its
        /// server, and that is `clearOrphans`'s business, not a session.
        case notRunning
        /// Up, and everything in it is wine's own: a prefix nothing of the
        /// user's is in.
        case onlyWine
        /// Up with something else in it -- Steam, the Epic launcher, a game,
        /// or a name nobody has listed -- by the names lsof gave, each once.
        case inUse(by: [String])
    }

    /// The classification itself, taking the scan rather than making it, so
    /// every answer can be read and tested without a live bottle.
    ///
    /// The known names are a parameter only so a test can hand it one this
    /// list does not have, such as a name longer than lsof reports. Steam's
    /// and the Epic launcher's executables are deliberately not among them:
    /// `gamesRunning` excuses them because they are not a game, but they are
    /// the user's, and a bottle with Steam in it is not coming down because a
    /// launch is waiting for it.
    nonisolated static func occupancy(of processes: [Running],
                                      wineOwn names: Set<String> = BottleProcesses.wineOwn) -> Occupancy {
        guard processes.contains(where: { $0.name.contains("wineserver") }) else { return .notRunning }
        // Compared lowercased and at the length lsof is willing to report, in
        // both directions, for the reason `gamesRunning` gives.
        let namesAtLimit = Set(names.map { String($0.lowercased().prefix(lsofNameLimit)) })
        // The server is recognised by the guard's own test, not by the set: an
        // engine can name it for its architecture, and CrossOver Preview on
        // this machine ships wineserver-x86 and wineserver-arm64 with no plain
        // wineserver beside them. Left to the set, wine's own server would be
        // reported as something of the user's.
        let others = processes.map(\.name).filter { name in
            !name.contains("wineserver")
                && !namesAtLimit.contains(String(name.lowercased().prefix(lsofNameLimit)))
        }
        return others.isEmpty ? .onlyWine : .inUse(by: Set(others).sorted())
    }

    /// What waiting for a bottle came to, in terms a launch can report.
    nonisolated enum Settling: Equatable {
        /// There was no server to wait for.
        case notRunning
        /// Only wine's own processes were up, and they went on their own.
        case cameDown(afterSeconds: Int)
        /// Only wine's own processes were up, and they were still there at the
        /// bound. Named, so the console can say which.
        case stillUp(afterSeconds: Int, names: [String])
        /// Something that is not wine's own is in the bottle. Not waited for.
        case inUse(by: [String])
    }

    /// Let a prefix that only wine's own processes are keeping up come down
    /// before a launch, up to a point.
    ///
    /// A short wine command leaves its prefix up behind it -- `PatchAll`
    /// waits out exactly that after an installer's `reg.exe` -- and a launch
    /// that lands in that window joins the prefix instead of starting it. Two
    /// things go with it. `registryIsOursToWrite` refuses while any wineserver
    /// is alive, so this title's controller settings are skipped with nothing
    /// of the user's in the bottle. And winebus runs inside winedevice.exe,
    /// which takes its debug channels from the environment of whatever started
    /// the prefix and its standard error from the same place: a HID trace
    /// launched into a prefix another wine command had started five seconds
    /// earlier came out without a single winebus line.
    ///
    /// Twenty seconds, the bound `PatchAll.waitForQuiet` already gives a
    /// bottle to settle after an installer: it is the wait this application
    /// accepts for this kind of prefix, not a measurement of how long one
    /// lives. Past it the launch goes ahead into the bottle as it did before,
    /// and the result says what was found.
    ///
    /// Anything that is not wine's own is not going to leave because a launch
    /// is waiting, so a bottle with one in it is reported at once. And this
    /// only watches: nothing here ends or signals a process, because a live
    /// server is somebody's session -- the rule `clearOrphans` keeps.
    ///
    /// The bound, the interval between scans and the scan itself are
    /// parameters only so a test can drive every branch of the loop without a
    /// live bottle or a twenty-second wait. The launch passes none of them.
    static func letShortLivedPrefixComeDown(inBottleAt bottle: URL,
                                            upTo bound: Duration = .seconds(20),
                                            every interval: Duration = .seconds(1),
                                            scan: @escaping @Sendable (URL) -> [Running] = { BottleProcesses.running(inBottleAt: $0) }) async -> Settling {
        let clock = ContinuousClock()
        let start = clock.now
        var waited: Int { Int(((clock.now - start) / .seconds(1)).rounded()) }
        var first = true
        while true {
            // Off the main actor, as PatchAll asks: each scan runs lsof and
            // waits for it, and a launch is started from the window.
            let here = await Task.detached(priority: .utility) {
                scan(bottle)
            }.value
            switch occupancy(of: here) {
            case .notRunning:
                return first ? .notRunning : .cameDown(afterSeconds: waited)
            case .inUse(let names):
                return .inUse(by: names)
            case .onlyWine:
                break
            }
            // A cancelled sleep returns at once, and ignoring that would turn
            // the rest of the bound into lsof in a tight loop.
            guard clock.now < start + bound,
                  (try? await Task.sleep(for: interval)) != nil else {
                return .stillUp(afterSeconds: waited, names: Set(here.map(\.name)).sorted())
            }
            first = false
        }
    }

    /// What a HID trace of this launch will be missing, or nil when nothing.
    ///
    /// A bottle whose server is still alive when the launch goes ahead was
    /// started by another command, and winedevice.exe -- where winebus runs --
    /// takes its debug channels and its standard error from that command, not
    /// from this one. So the file this launch opens will not have winebus's
    /// lines, and the console says so before the absence is read as a pad
    /// that did nothing. Kept apart from the wait so every answer can be
    /// tested.
    nonisolated static func hidTraceWarning(after settling: Settling) -> String? {
        let why: String
        switch settling {
        case .notRunning, .cameDown:
            return nil
        case .inUse(let names):
            why = "it is in use by " + names.joined(separator: ", ")
        case .stillUp(let seconds, _):
            why = "wine's own processes in it did not go within \(seconds) s"
        }
        return "HID trace: this bottle was already up (\(why)), so its controller driver was started before this launch and this trace file will not contain winebus's lines. Close what runs in this bottle and launch again to capture them."
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

        // Only what was condemned, never what arrived meanwhile.
        //
        // `running(inBottleAt:)` is a fresh scan of the bottle's server
        // directory, so anything that entered during the grace period was in
        // the second list too -- and got a SIGKILL for ignoring a request it
        // was never sent. A fix installer is exactly such a newcomer: it starts
        // a short-lived wineserver to run `reg.exe add`, and the window is
        // reachable because the guard that forbids installing while a bottle is
        // busy is a one-shot check. Teardown asks wineserver to go, waits two
        // seconds, then calls this -- and once `wineserver -k` has landed there
        // is no wineserver left for that check to find, so an install becomes
        // permitted while this is still inside its grace.
        //
        // The damage would not look like a crash. If the kill lands after
        // `reg.exe add` returned 0 but before the server flushed user.reg, the
        // script reports success, the fix is recorded as applied, and some of
        // the keys are simply not there -- the half-applied state the installer
        // has its own comment calling the dangerous one.
        //
        // Matched on pid AND name so a pid the system has since reused is not
        // condemned for the sins of the process that held it.
        let stubborn = stillThere(running(inBottleAt: bottle), of: doomed)
        for process in stubborn {
            console.warn("\(process.name) ignored the request; ending it")
            kill(process.pid, SIGKILL)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        // Filtered too: a newcomer reported here would be logged as a process
        // that would not end, which is a false accusation and a misleading log.
        return stillThere(running(inBottleAt: bottle), of: doomed)
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
            console.log("a wineserver is alive in this bottle; leaving its processes alone")
            return
        }
        console.warn("clearing \(left.count) orphan(s) from a previous session: "
                     + left.map(\.name).joined(separator: ", "))
        await end(inBottleAt: bottle)
    }
}
