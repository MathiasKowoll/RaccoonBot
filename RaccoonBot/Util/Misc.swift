//
//  Util.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 03/02/2026.
//

import UniformTypeIdentifiers
import Combine
import AppKit

let AUTOFILL_CUSTOM_GAME_ENABLED: Bool = {
    let env = ProcessInfo.processInfo.environment["PROCYON_AUTOFILL_CUSTOM_GAME_ENABLED"]?.lowercased()
    switch env {
    case "1", "true", "yes":
        return true
    case "0", "false", "no":
        return false
    default:
        return false
    }
}()

/// Where each supported CrossOver keeps the files the patcher writes.
///
/// Hardcoded per release rather than probed. The layouts differ in more than
/// one directory name, and a probe looking for `lib/` would answer confidently
/// and wrongly on a 26 engine, which has both `lib/` and `lib64/`.
///
/// Supported: CrossOver 26.x and CrossOver 27 (Preview). Anything else returns
/// nil and the caller refuses, rather than writing into a path that does not
/// exist -- which is how a patch silently half-applied before: the copy came
/// out with no DXMT, no bottle redirection and no patch marker, and nothing
/// said so.
///
/// Measured on 26.3.0.39832 and 27.0.0.40921:
///
///                   apple_gptk          libMoltenVK.dylib     dxmt
///     26.x          lib64/apple_gptk    lib64/                lib/dxmt
///     27 (Preview)  lib/apple_gptk      lib/<arch>/           lib/dxmt
/// Whether the interface offers the ARM bottle at all.
///
/// Off for now: the engine in use is a 26.3 base, which has no aarch64
/// libraries, and nothing here runs on ARM. The machinery is untouched --
/// the per-game flag, the second bottle, the launch path -- so this is one
/// line to put back when an ARM engine is in play again.
let showArmSupport = false

enum EngineLayout {
    case cx26
    case cx27

    /// Directory holding the `apple_gptk` tree.
    var gptkRoot: String {
        switch self {
        case .cx26: return "lib64"
        case .cx27: return "lib"
        }
    }

    /// Directory holding `libMoltenVK.dylib`. On 26 there is one copy and the
    /// architecture is not part of the path; on 27 there is one per arch.
    func moltenVKRoot(arch: String = "x86_64") -> String {
        switch self {
        case .cx26: return "lib64"
        case .cx27: return "lib/\(arch)"
        }
    }

    /// Read from the bundle's own CFBundleVersion. A patched copy keeps the
    /// version of the CrossOver it was copied from, which is exactly what we
    /// want: the copy has the layout of its source.
    static func of(_ appURL: URL) -> EngineLayout? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let d = NSDictionary(contentsOf: plist),
              let version = d["CFBundleVersion"] as? String,
              let first = version.split(separator: ".").first,
              let major = Int(first)
        else { return nil }
        switch major {
        case 26: return .cx26
        case 27: return .cx27
        default: return nil
        }
    }
}

struct UnsupportedEngine: LocalizedError {
    let path: String
    var errorDescription: String? {
        "Unsupported CrossOver at \(path) -- this build supports CrossOver 26.x and 27 (Preview)."
    }
}

let DEFAULT_BOTTLE_PATH = "Library/Application Support/CrossOver/Bottles/"
let BLACKLIST = [
    "228980", // Steamworks
]
/// Whether the run keeps a log.
///
/// Three names answer. `RaccoonBotDebug` is ours and is the one to use;
/// `RACCOONBOT_DEBUG` because that is how an environment variable is usually
/// spelled and somebody will try it; `PROCYON_DEBUG` because it is what this
/// was called upstream and anyone arriving from there already knows it.
///
/// Accepting the three costs nothing. Accepting only one and saying nothing
/// costs an evening of "I set it and it did not work".
/// Whether this run keeps a log.
///
/// Two ways in, and the switch in the window is the one that matters. Asking
/// somebody to open a terminal and set a variable before they can tell you
/// what went wrong is asking too much -- of them, and of anyone giving
/// support. The environment variable stays because it is the only way to have
/// logging on from the very first line, before any window exists.
///
/// Read each time rather than decided once, so the switch takes effect without
/// a restart.
nonisolated var debugLoggingEnabled: Bool {
    if debugLoggingFromEnvironment { return true }
    return UserDefaults(suiteName: suiteName)?.bool(forKey: namespacedKey("debugLogging", "app")) ?? false
}

func setDebugLogging(_ on: Bool) {
    UserDefaults(suiteName: suiteName)?.set(on, forKey: namespacedKey("debugLogging", "app"))
    console.enableLogFile = on
    console.warn(on ? "logging on" : "logging off")
}

/// `RaccoonBotDebug=1` in the environment. Also answers to
/// `RACCOONBOT_DEBUG`, because that is how a variable is usually spelled, and
/// to `PROCYON_DEBUG`, because that is what it was called upstream.
nonisolated let debugLoggingFromEnvironment: Bool = {
    let env = ProcessInfo.processInfo.environment
    for name in ["RaccoonBotDebug", "RACCOONBOT_DEBUG", "PROCYON_DEBUG"] {
        switch env[name]?.lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: continue
        }
    }
    return false
}()

/// Kept for the places that still say it.
nonisolated var DEBUG_ENABLED: Bool { debugLoggingEnabled }
let useLogger: Bool = false

func prettyPrinted(dict: Dictionary<String, Any>) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
       let str = String(data: data, encoding: .utf8) {
        return str
    }
    return "{}"
}

func addSteamFolderPaths(_ url: URL) {
    do {
        if (try getIDsFromFolder(dest: url).isEmpty) {
            console.warn("\(url) folder is empty")
            return
        }
    } catch {
        console.warn("Failed to validate steam folder \(url.path())")
        console.error(String(reflecting: error))
//        console.error(String(reflecting: error))
    }
    do {
        try persistFolderAccess(url: url)
    } catch {
        console.error("Failed to save steam folder")
        console.error(String(reflecting: error))
    }
}

func removeSteamFolderPath(_ path: String) {
    let url = URL(string: path)!
    removePersistedFolderAccess(url: url)
}

func getSteamFolderPaths() -> [String] {
    return resolvePersistedFolders().map { $0.absoluteString }
}

func extractAppIDRegex(from filename: String) -> String? {
    let pattern = #"^appmanifest_(\d+)\.acf$"#
    let regex = try? NSRegularExpression(pattern: pattern)
    let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
    guard let match = regex?.firstMatch(in: filename, options: [], range: range),
          match.numberOfRanges == 2,
          let idRange = Range(match.range(at: 1), in: filename) else { return nil }
    return String(filename[idRange])
}

func extractFolderNameRegex(_ path: String) -> String {
    let pattern = #"^file:\/\/\/Volumes\/(.+)\/steamapps\/$"#
    let regex = try? NSRegularExpression(pattern: pattern)
    let decodedpath = path.removingPercentEncoding ?? path
    let range = NSRange(decodedpath.startIndex..<decodedpath.endIndex, in: decodedpath)
    guard let match = regex?.firstMatch(in: decodedpath, options: [], range: range),
          match.numberOfRanges == 2,
          let idRange = Range(match.range(at: 1), in: decodedpath) else { return decodedpath }
    return String(decodedpath[idRange])
}

//let id = extractAppIDRegex(from: "appmanifest_8870.acf") // "8870"

func getIDsFromFolder(dest: URL) throws -> [String] {
    /**
     scans a folder and returns an array of steam games ids
     */
//    try withSecurityScope(for: dest) {
        let f = FileManager.default
        let urls = try f.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants])
        return urls
        .filter { acfFileURL in
            acfFileURL.pathExtension == "acf"
        }
        .map { acfFileURL in
            extractAppIDRegex(from: acfFileURL.lastPathComponent) ?? "0"
        }
        .filter {
            gameID in !BLACKLIST.contains(gameID)
        }
//    } ?? []
}

func getIsNative(fromURL: URL) -> Bool {
    if !folderContainsFile(withExtension: "exe", at: fromURL) && folderContainsFile(withExtension: "app", at: fromURL) {
        return true
    }
    return false
}

/// Run a command and do not wait for it.
///
/// Debug mode used to route this through safeShellWithOutput, which calls
/// readDataToEndOfFile -- it blocks until the child closes its output. The
/// command here is a game launch, so the application sat waiting for the game
/// to exit: the window froze, and the Download logs button could not be
/// reached. Turning on logging made the thing you wanted to look at
/// unreachable.
///
/// So debug no longer changes WHETHER we wait. It changes what is written
/// down. The command itself is logged before it runs -- that is the line
/// worth having -- and its output is streamed as it arrives.
func safeShell(_ command: String) throws {
    let task = Process()
    task.standardInput = FileHandle.nullDevice
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")

    if DEBUG_ENABLED {
        console.log("running: \(command)")
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        // Streamed, never drained in one go. A game writes for as long as it
        // runs, and something has to read the pipe or the child stalls once
        // the buffer fills.
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                console.log(text.trimmingCharacters(in: .newlines))
            }
        }
        task.terminationHandler = { _ in
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    } else {
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
    }

    try task.run()
}

func safeShellWithOutput(_ command: String) throws -> String {
    let task = Process()
    let pipe = Pipe()
    
    task.standardInput = nil
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")

    try task.run()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    // Not force-unwrapped. A command that writes anything not valid UTF-8 --
    // a path in another encoding, a binary byte in an error -- would have
    // killed the process rather than returned nothing.
    return String(data: data, encoding: .utf8)
        ?? String(decoding: data, as: UTF8.self)
}

let DEFAULT_STEAM_MAC_PATH = "/Library/Application Support/Steam/"
let DEFAULT_STEAM_MAC_CONFIG_PATH = DEFAULT_STEAM_MAC_PATH + "config/"
nonisolated let DEFAULT_STEAM_WINE_PATH = "/drive_c/Program Files (x86)/Steam/"
nonisolated let DEFAULT_STEAM_WINE_CONFIG_PATH = DEFAULT_STEAM_WINE_PATH + "config/"

func getSteamUserID (usingURL: URL) -> String? {
    let steamLoginUsersPath = usingURL.appendingPathComponent("loginusers.vdf")
    guard let steamSettingsFile = try? String(contentsOfFile: steamLoginUsersPath.path(percentEncoded: false), encoding: .utf8) else { return nil }
    let parsed = parseVDFToDict(from: steamSettingsFile)
    let users = parsed["users"] as? [String: Any]
    return users?.keys.first?.description
}

func getSteamUserDataFallback (usingPath: URL) -> UserInfo? {
    let steamLoginUsersPath = usingPath.appendingPathComponent("loginusers.vdf")
    guard let steamSettingsFile = try? String(contentsOfFile: steamLoginUsersPath.path(percentEncoded: false), encoding: .utf8) else { return nil }
    let parsed = parseVDFToDict(from: steamSettingsFile)
    let users = parsed["users"] as? [String: Any]
    if let key = users?.keys.first {
        let user = users![key] as? [String: Any]
        let personaName = user?["PersonaName"] as? String ?? ""
        let avatar = usingPath
            .appendingPathComponent(DEFAULT_STEAM_WINE_CONFIG_PATH)
            .appendingPathComponent("avatarcache")
            .appendingPathComponent(key)
            .appendingPathExtension("png")
            .absoluteString
        let fallbackProfileData = UserInfo(
            steamID: "",
            communityVisibilityState: 0,
            profileState: 0,
            personaName: personaName,
            profileURL: "",
            avatar: avatar,
            avatarMedium: avatar,
            avatarFull: avatar,
            avatarHash: "",
            lastLogOff: 0,
            personaState: 0,
            primaryClanID: "",
            timeCreated: 0,
            personaStateFlags: 0,
            locCountryCode: nil,
            locStateCode: nil
        )
        return fallbackProfileData
    }
    return nil
}

/// Steam's own list of where it keeps games, read through the bottle's drives.
///
/// Returns every library the configuration names, including ones whose disk is
/// not plugged in at the moment. An external drive that is unplugged is still a
/// library, and dropping it here is how a game ends up looking uninstalled.
func getSteamLibraryFolders(bottleURL: URL, from: URL) -> [URL] {
    let f = FileManager.default
    var steamLibraries: [URL] = []
    var offline: [URL] = []
    // Read once for the whole scan rather than once per library.
    let drives = BottleDrives(bottle: bottleURL)
    console.log("drives: \(drives.letters.keys.sorted().joined(separator: " "))")

    let steamSettingsPaths = [
        from.appendingPathComponent("libraryfolders.vdf"),
        f.homeDirectoryForCurrentUser
            .appendingPathComponent(DEFAULT_STEAM_MAC_CONFIG_PATH)
            .appendingPathComponent("libraryfolders.vdf")
    ].filter { f.fileExists(atPath: $0.path(percentEncoded: false)) }

    for steamSettingsPath in steamSettingsPaths {
        do {
            let steamSettingsFile = try String(contentsOfFile: steamSettingsPath.path(percentEncoded: false),
                                               encoding: .utf8)
            let parsed = parseVDFToDict(from: steamSettingsFile)
            guard let libraries = parsed["libraryfolders"] as? [String: Any] else { continue }

            for (_, value) in libraries {
                guard let val = value as? [String: Any],
                      let path = val["path"] as? String else { continue }

                // A macOS Steam writes an absolute POSIX path; a Windows one
                // writes a drive letter. Only the second needs the bottle.
                if path.hasPrefix("/") {
                    steamLibraries.append(URL(fileURLWithPath: path).appendingPathComponent("steamapps"))
                    continue
                }

                switch drives.resolve(path) {
                case .resolved(let url):
                    steamLibraries.append(url.appendingPathComponent("steamapps"))
                case .volumeOffline(let url):
                    // Kept. The disk comes back and so does the library.
                    offline.append(url)
                    steamLibraries.append(url.appendingPathComponent("steamapps"))
                case .missing(let url):
                    // The drive is mounted and the folder is not on it, so
                    // Steam's configuration is stale rather than the disk absent.
                    console.log("steam library no longer at \(url.path(percentEncoded: false))")
                case .noSuchDrive(let letter):
                    console.log("no drive \(letter) in this bottle for steam library \(path)")
                }
            }
        } catch {
            console.error(String(reflecting: error))
            return []
        }
    }
    if !offline.isEmpty {
        console.log("\(offline.count) steam librar\(offline.count == 1 ? "y is" : "ies are") on a disk that is not mounted")
    }
    console.log("all steam libraries \(steamLibraries.debugDescription)")
    return steamLibraries
}

func validateAddSteamFolder(_ url: URL, to folders: inout [String]) {
    if folders.contains(url.absoluteString) {
        console.log("\(url.absoluteString) folder exists!")
        return
    }
    addSteamFolderPaths(url)
    folders.append(url.absoluteString)
}

func mapPersonaState(_ state: Int) -> String {
    let states = ["Offline", "Online", "Busy", "Away", "Snooze", "looking to trade", "looking to play"]
    if (0..<states.count).contains(state){
        return states[state]
    }
    return "Unknown"
}

func getAppNames(isNative: Bool, gameURL: URL?) -> [String] {
    let ext = isNative ? "app" : "exe"
    let f = FileManager.default
    var results: [String] = []
    if(gameURL == nil) {
        return []
    }
    guard let enumerator = f.enumerator(at: gameURL!, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
        return []
    }
    for case let fileURL as URL in enumerator  {
        if(fileURL.pathExtension == ext) {
            results.append(fileURL.lastPathComponent)
        }
    }
    return results
}

class SteamLogWatcher {
    var steamID: String
    var steamPath: String
    var fileName: String
    var logPath: String {
        return "\(steamPath)/logs/\(fileName)"
    }
    
    init (steamID: String, steamPath: String, fileName: String) {
        self.steamID = steamID
        self.steamPath = steamPath
        self.fileName = fileName
    }
}

class SteamCloudSyncWatcher: SteamLogWatcher {
    private let tail: SteamLogTail

    /// Create this when the game starts, not when it ends.
    ///
    /// Steam writes the exit sync within the same second the game stops, so a
    /// watcher built at teardown time would begin reading after the lines it
    /// needs have already gone by.
    init (steamID: String, steamPath: String) {
        tail = SteamLogTail(url: URL(fileURLWithPath: "\(steamPath)/logs/cloud_log.txt"))
        super.init(steamID: steamID, steamPath: steamPath, fileName: "cloud_log.txt")
    }

    /// The lines Steam ends an exit sync with.
    ///
    /// Counted in this machine's two cloud logs rather than guessed at, which
    /// is how the first version of this went wrong: it knew "Upload complete in
    /// build list" and not "Upload complete, result OK", so a real upload that
    /// finished in six seconds went unrecognised and the teardown sat waiting
    /// for three minutes. Hence the prefix, and hence the quiet fallback below:
    /// a phrase list is only ever as complete as the logs you have read.
    /// Exposed so the vocabulary can be checked against real log lines.
    static func isTerminalForTesting(_ line: String) -> Bool { isTerminal(line) }

    private static func isTerminal(_ line: String) -> Bool {
        line.contains("Successfully synced")
            || line.contains("Upload complete")
            || line.contains("Failed sync for")
    }

    /// Wait for Steam to finish the save-data upload it runs when a game exits.
    ///
    /// This used to scan the whole of `cloud_log.txt` for "Successfully synced"
    /// belonging to this AppID. That log is cumulative, so it matched a line
    /// from an earlier session and returned after one tenth of a second,
    /// having waited for nothing at all -- and then the launcher killed Steam.
    ///
    /// It cost real uploads. In this bottle's log, an exit sync announced
    /// "Need to upload file ..." three times and then stopped mid-sentence;
    /// those files were still listed as needing upload twenty-five minutes
    /// later, at the next launch.
    ///
    /// So: only lines written since the game started count, and finished means
    /// Steam said so -- uploaded, synced, or failed -- not merely that the
    /// words appear somewhere in the file.
    func waitForSteamCloudSync() async throws {
        let appIDMarker = "[AppID \(self.steamID)]"
        let deadline = Date().addingTimeInterval(60)
        // If no exit sync has even begun after this long, there is not going to
        // be one -- cloud saves are off for this title, or Steam is not logged
        // in. Waiting the full deadline for it would just delay the teardown.
        let patienceForItToBegin = Date().addingTimeInterval(15)

        var sawExitSync = false
        var pendingUploads = 0
        // When this app last said anything. Steam writes an exit sync in one
        // burst; once it has been quiet for a few seconds it is done, whatever
        // words it finished with.
        var lastHeardFrom = Date()

        while Date() < deadline {
            for line in tail.newLines() where line.contains(appIDMarker) {
                lastHeardFrom = Date()
                if line.contains("Starting sync (") && line.contains("AC Exit") {
                    sawExitSync = true
                    console.log("\(self.steamID): steam is syncing save data on exit")
                } else if line.contains("Need to upload file") {
                    pendingUploads += 1
                } else if sawExitSync && Self.isTerminal(line) {
                    if line.contains("Failed sync") {
                        console.warn("\(self.steamID): steam could not sync save data: \(line)")
                    } else if pendingUploads > 0 {
                        console.log("\(self.steamID): save data uploaded (\(pendingUploads) file(s))")
                    } else {
                        console.log("\(self.steamID): save data already up to date")
                    }
                    return
                }
            }
            if !sawExitSync && Date() > patienceForItToBegin {
                console.log("\(self.steamID): steam started no exit sync; nothing to wait for")
                return
            }
            if sawExitSync && Date().timeIntervalSince(lastHeardFrom) > 6 {
                console.log("\(self.steamID): steam has gone quiet; the sync is done")
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        console.warn("\(self.steamID): steam did not finish syncing save data in time; closing anyway")
    }
}

class SteamLaunchWatcher: SteamLogWatcher {
    init (steamID: String, steamPath: String) {
        super.init(steamID: steamID, steamPath: steamPath, fileName: "gameprocess_log.txt")
    }
    
    func getGameExe() async throws -> String {
        let appIDMarker = "AppID \(self.steamID) adding PID"
        var appExe = ""
        let deadline = Date().addingTimeInterval(90)
        var polling = true
        let pattern = /[^\\]+\.exe/
        while polling {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            do {
                let content = try String(contentsOfFile: logPath, encoding: .utf8)
                for fileContentLine in content.split(separator: "[") {
                    if(fileContentLine.contains(appIDMarker)) {
                        let match = fileContentLine.firstMatch(of: pattern)
                        print(fileContentLine)
                        appExe = String(match?.output ?? "not found")
                        polling = false
                    }
                }
                console.log("File \(self.fileName) found")
            } catch {
                console.error(String(describing: error))
                console.error("File \(self.fileName) seems missing, retrying...")
            }
            if(Date() > deadline) {
                console.log("\(self.steamID): App name fetching timed out")
                polling = false
            }
        }
        return appExe
    }
    
    func trackLaunch() async throws -> String {
        var polling = true
        var returnedValue = ""
        let appName = try await getGameExe()
        let deadline = Date().addingTimeInterval(90)
        console.log("App name found: \(appName)")
        while polling {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            if(Date() > deadline) {
                console.log("\(self.steamID): Launch tracking timed out")
                polling = false
            }
            let appNames = NSWorkspace.shared.runningApplications
                .flatMap{ app in [app.executableURL?.lastPathComponent ?? "none", app.bundleURL?.lastPathComponent ?? "none"] }
                .filter { lastpathcomponent in lastpathcomponent.contains(".exe")}
            if appNames.contains(appName) {
                returnedValue = appName
                polling = false
            }
        }
        return returnedValue
    }
}

/// The executable Steam actually started, once it is known.
///
/// Written from the tracking task and read from a workspace notification, so
/// it carries its own lock rather than relying on where either happens to run.
final class LoadedGame: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private var closing = false

    var name: String? {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }

    /// True exactly once. Two signals now watch the same session -- Steam's own
    /// record and the executable exiting -- and either may arrive first. They
    /// must not both tear the bottle down.
    func claimShutdown() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if closing { return false }
        closing = true
        return true
    }
}

/// How long everything belonging to a game must stay stopped before the bottle
/// comes down -- given how long it had been running.
///
/// The wait exists for one thing: a launcher chain that restarts itself,
/// emptying Steam's tracked set for a moment in the middle of starting up. Every
/// such gap in this machine's history -- nine of them -- happened while the
/// session was less than sixty-three seconds old, and most inside the first
/// twenty. None has ever happened to a game that had been running for minutes.
///
/// So a game that ran for a while and then stopped has stopped, and making
/// somebody watch two minutes of Steam processes to prove it is a cost with
/// nothing bought. A game that stopped seconds after starting is the ambiguous
/// one, and that is where the patience belongs.
func steamIdleGrace(forSessionLasting duration: TimeInterval,
                    crashed: Bool = false) -> TimeInterval {
    // A game that fell over is not a launcher chain about to come back, however
    // briefly it ran. Waiting two minutes to accept that helps nobody, and it
    // is the case somebody testing a patch hits over and over.
    if crashed { return 15 }
    return duration > 5 * 60 ? 15 : 120
}

/// Which of `names` is running right now, if any.
func runningExecutable(among names: [String]) -> String? {
    let running = Set(NSWorkspace.shared.runningApplications.flatMap {
        [$0.executableURL?.lastPathComponent, $0.bundleURL?.lastPathComponent]
    }.compactMap { $0 })
    return names.first { running.contains($0) }
}

/// Wait until Steam says the session is over.
///
/// It insists on seeing the game running first. The registry trails what Steam
/// has actually done by a few seconds, so a game that has just been asked to
/// start still reads as not running -- and acting on that would tear the bottle
/// down at the worst possible moment, during startup. A 1 that becomes a 0 is
/// a session; a 0 on its own is only ignorance.
///
/// If Steam never records the game at all, this waits and nothing happens: the
/// executable-name path is still armed, and lingering is the failure worth
/// having.
func watchSteamSession(_ state: SteamAppState,
                       appID: Int,
                       every interval: UInt64 = 2_000_000_000,
                       then shutDown: @escaping (String) async -> Void) async {
    var seenRunning = false
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: interval)
        switch state.liveness(ofAppID: appID) {
        case .running:
            if !seenRunning {
                console.log("steam reports \(appID) running; watching for it to finish")
                seenRunning = true
            }
        case .notRunning where seenRunning:
            await shutDown("steam reports \(appID) is no longer running, closing steam...")
            return
        case .notRunning, .unknown:
            continue
        }
    }
}

func getGameTracker(appNames: [String], cxAppPath: String, bottle: String, onLoad: @escaping (_ appName: String) -> Void, onTerminate: @escaping () -> Void, isNative: Bool, steamID: Int?, steamPath: String) async throws -> TerminationObserver {
    // `appNames` lists every executable a game is known by, and for a game with
    // a launcher that is two: the launcher, and the game the launcher starts.
    // The launcher exits as soon as it has handed off -- that is its whole job.
    //
    // Treating any of those names exiting as the game closing tore the bottle
    // down while the game was still coming up. Nioh died this way every time:
    // `nioh_launcher.exe` handed off, Steam and explorer were killed, and
    // `nioh.exe` finished starting seconds later into a bottle with nothing
    // left in it.
    //
    // Two things now say when the session is over, and the bottle comes down
    // only when one of them is sure.
    //
    // The better one is Steam's own record. Steam keeps a `Running` flag per
    // AppID in the bottle registry; it is about the app we launched, not about
    // processes, so a launcher handing off does not disturb it and no per-game
    // knowledge is needed for it to work.
    //
    // The other is the executable Steam named as the game, kept as a fallback
    // for when there is no AppID to ask about -- a custom game -- or when Steam
    // never records one.
    let loaded = LoadedGame()

    var steamState: SteamAppState? = nil
    if let ref = BottleReference(bottle), let dir = ref.directory {
        steamState = SteamAppState(bottleDirectory: dir)
    }

    // Both of these must exist before the game can exit: they read their logs
    // forward from wherever the file is now, and Steam writes the whole exit
    // sequence within the same second the game stops.
    var cloudSync: SteamCloudSyncWatcher? = nil
    var processLog: SteamGameProcessLog? = nil
    if !isNative, let steamID {
        cloudSync = SteamCloudSyncWatcher(steamID: String(steamID), steamPath: steamPath)
        processLog = SteamGameProcessLog(steamPath: steamPath, steamID: String(steamID))
    }

    func shutDown(because reason: String) async {
        guard loaded.claimShutdown() else { return }
        console.log(reason)
        do {
            // Steam uploads save data when a game exits. Killing it mid-upload
            // leaves the cloud copy behind whatever was actually played, and it
            // has already happened here.
            if let cloudSync { // not for native steam games
                try await cloudSync.waitForSteamCloudSync()
            }
            try await quitSteam(cxAppPath: cxAppPath, bottle: bottle, isNative: isNative)
            // Steam has been asked, not told. Give it time to finish writing
            // its own state before ending anything.
            try await closeBottle(cxAppPath: cxAppPath, bottle: bottle)
        } catch {
            // Whatever failed on the way out, the game is over as far as the
            // window is concerned. Leaving the loader spinning helps nobody.
            console.error("while closing down: \(error.localizedDescription)")
        }
        onTerminate()
        console.log("onTerminate() was called")
    }

    let tOb = TerminationObserver(then: { output in
        let terminatedAppProcessName = output.userInfo?[AnyHashable("NSApplicationName")] as? String ?? "unknown"
        let terminatedAppPath = output.userInfo?[AnyHashable("NSApplicationPath")] as? String ?? "unknown"
        let terminatedAppName = String(terminatedAppPath.split(separator: "/").last ?? "unknown")
        guard appNames.contains(terminatedAppName) || appNames.contains(terminatedAppProcessName) else { return }
        console.log(output.userInfo?.description ?? "no userInfo")

        guard let game = loaded.name else {
            if steamID != nil {
                // Steam will tell us what the game is; until it does, an exit
                // is a launcher handing off, not the game closing.
                console.log("\(terminatedAppProcessName) exited before the game was up; waiting for the game itself")
                return
            }
            // No Steam to ask, so go by what can be seen: if another name we
            // know is still running, the thing that exited was not the game.
            if let stillUp = runningExecutable(among: appNames) {
                console.log("\(terminatedAppProcessName) exited but \(stillUp) is still running; leaving the bottle alone")
                return
            }
            Task { await shutDown(because: "\(appNames) -> \(terminatedAppName) or \(terminatedAppProcessName) has been terminated, closing steam...") }
            return
        }

        guard terminatedAppName == game || terminatedAppProcessName == game else {
            console.log("\(terminatedAppProcessName) exited, but the game is \(game); leaving the bottle alone")
            return
        }
        Task { await shutDown(because: "\(game) has been terminated, closing steam...") }
    })
    if let processLog {
        Task(priority: .background) {
            // Steam names every executable it starts for this app and the code
            // each one exits with. What it does not reliably say is when the
            // app is over: "Remove <id> from running list" fires whenever the
            // tracked set momentarily empties, which for Red Dead Redemption 2
            // is one second into every launch -- the Rockstar chain exits
            // completely and restarts, and the game itself arrives
            // forty-four seconds later.
            //
            // So the set emptying only asks the question. Staying empty
            // answers it.
            var reportedIdle = false
            while !Task.isCancelled {
                for event in processLog.poll() {
                    switch event {
                    case .started(let pid, let path):
                        console.log("steam started \(URL(fileURLWithPath: path).lastPathComponent) as pid \(pid)")
                    case .stopped(let pid, let code):
                        console.log("steam says pid \(pid) ended \(describeExit(code: code))")
                    case .sessionEnded:
                        // Informative only. It is right more often than not,
                        // and acting on it is what broke RDR2.
                        console.log("steam removed the game from its running list")
                    }
                }
                if processLog.emptySince != nil {
                    if !reportedIdle {
                        // Two different questions, and they were tied together
                        // by mistake. Whether somebody may play something else
                        // is answered the moment nothing of this game is left.
                        // Whether it is safe to destroy the bottle is not.
                        console.log("nothing of the game is running; the window is free again")
                        onTerminate()
                        reportedIdle = true
                    }
                    let grace = steamIdleGrace(forSessionLasting: processLog.sessionLength,
                                                       crashed: processLog.lastExitWasACrash)
                    if processLog.hasBeenIdle(for: grace) {
                        // The bottle is shared. Tearing it down for a game that
                        // finished would take down a game that has not.
                        if let other = processLog.otherAppRunning {
                            console.log("app \(other) is using the bottle; leaving it up")
                            return
                        }
                        await shutDown(because: "nothing has run for this game in \(Int(grace))s, closing down...")
                        return
                    }
                } else if reportedIdle {
                    console.log("the game is running again; it was still starting")
                    onLoad(loaded.name ?? "")
                    reportedIdle = false
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    if let steamID = steamID {
        do {
            let appName = try await SteamLaunchWatcher(steamID: String(steamID), steamPath: steamPath).trackLaunch()
            if appName != "" {
                console.log("found game \(appName), loading...")
                loaded.name = appName
                onLoad(appName)
                // The registry flag is deliberately not a trigger. Steam
                // clears it in the same instant it logs the removal, so it
                // dips mid-launch exactly as that line does. It is kept for
                // games where Steam writes no process log at all, and even
                // then only after the same idle wait.
                if let steamState, processLog == nil {
                    Task(priority: .background) {
                        await watchSteamSession(steamState, appID: steamID, then: shutDown)
                    }
                }
            } else {
                // Nothing ever came up. The observer is now waiting for a game
                // that does not exist, so say so here instead of leaving the
                // window on its loader forever.
                await shutDown(because: "no game came up for \(appNames.joined(separator: ", ")), giving up")
            }
        } catch {
            console.log("\(appNames.joined(separator: ", ")), timeout...")
            onTerminate()
        }
    }
    return tOb
}

//func getGameTracker(appNames: [String], cxAppPath: String, bottleName: String, onLoad: @escaping (_ game: String) -> Void, onTerminate: @escaping () -> Void, isNative: Bool, steamID: Int, steamPath: String) async throws -> TerminationObserver {
//    let tOb = TerminationObserver(then: { output in
//        console.log(output.userInfo?.description ?? "no userInfo")
//        let terminatedAppProcessName = output.userInfo?[AnyHashable("NSApplicationName")] as? String ?? "unknown"
//        let terminatedAppPath = output.userInfo?[AnyHashable("NSApplicationPath")] as? String ?? "unknown"
//        let terminatedAppName = String(terminatedAppPath.split(separator: "/").last ?? "unknown")
//        if (appNames.contains(terminatedAppName) || appNames.contains(terminatedAppProcessName)) {
//            console.log("\(appNames) -> \(terminatedAppName) or \(terminatedAppProcessName) has been terminated, closing steam...")
//            Task {
//                if(!isNative){
//                    let cloudSyncWatcher = SteamCloudSyncWatcher(steamID: String(steamID), steamPath: steamPath)
//                    try await cloudSyncWatcher.waitForSteamCloudSync()
//                }
//                try await quitSteam(cxAppPath: cxAppPath, bottleName: bottleName, isNative: isNative)
//                try await closeWineActivities()
//                onTerminate()
//                console.log("onTerminate() was called")
//            }
//        }
//    })
//    do {
//        let appName = try await SteamLaunchWatcher(steamID: String(steamID), steamPath: steamPath).trackLaunch()
//        console.log("found game \(appName), loading...")
//        onLoad(appName)
//    } catch {
//        console.log("\(appNames.joined(separator: ", ")), timeout...")
//        onTerminate()
//    }
//    return tOb
//}

func isSameFile(_ file1URL: URL, _ file2URL: URL) -> Bool {
    let f = FileManager.default
    do {
        let attrs1 = try f.attributesOfItem(atPath: file1URL.path())
        let attrs2 = try f.attributesOfItem(atPath: file2URL.path())
        let sameSize = attrs1[.size] as? Int == attrs2[.size] as? Int
        let sameDate = attrs1[.modificationDate] as? Date == attrs2[.modificationDate] as? Date
        if(sameSize && sameDate) {
            // just comparing attributes for now
            return true
        }
    } catch {
        console.error("couldn't get file attributes")
        console.error(String(reflecting: error))
        return false
    }
    return false
}

func getSystemWOW64URL(from: URL) -> URL {
    return from
        .appending(path: "drive_c")
        .appending(path: "windows")
        .appending(path: "syswow64")
}

func getSystem32URL(from: URL) -> URL {
    return from
        .appending(path: "drive_c")
        .appending(path: "windows")
        .appending(path: "system32")
}

func cpyd8d9DLLs(to url: URL, enable: Bool = true) throws -> Void {
    let f = FileManager.default
    let files = ["d3d9.dll", "d3d8.dll"]
    
    func copyByBitness(dllsUrl: URL, file: String, is32Bit: Bool) throws {
        let dllPathComponentByBitness = "drive_c" + (is32Bit ? "/windows/SysWOW64": "/windows/System32")
        let dllPath = dllsUrl.appendingPathComponent(file)
        let dllDest = url.appendingPathComponent(dllPathComponentByBitness).appendingPathComponent(file) // the logic seems flipped but it's actually how the winwos logic works System32 is for 64 bits libs
        console.log("\(file) exists")
        if(enable) {
            if(!isSameFile(dllPath, dllDest)){
                if(!f.fileExists(atPath: dllDest.appendingPathExtension("old").path())){
                    try? f.moveItem(at: dllDest, to: dllDest.appendingPathExtension("old"))
                } else {
                    try? f.removeItem(at: dllDest)
                }
                try f.copyItem(at: dllPath, to: dllDest)
            } else {
                console.log("already patched with the latest dx9 skipping copy")
            }
        } else {
            if(!f.fileExists(atPath: dllDest.path())){
                try? f.removeItem(at: dllDest)
            }
            try f.copyItem(at: dllDest.appendingPathExtension("old"), to: dllDest)
        }
        
    }
    
    for file in files {
        if let dllsUrl = Bundle.main.url(forResource: "d9vk/x32", withExtension: nil) {
            try copyByBitness(dllsUrl: dllsUrl, file: file, is32Bit: true)
        } else {
            console.log("Couldn't find \(file)")
        }
        if let dllsUrl = Bundle.main.url(forResource: "d9vk/x64", withExtension: nil) {
            try copyByBitness(dllsUrl: dllsUrl, file: file, is32Bit: false)
        } else {
            console.log("Couldn't find \(file)")
        }
    }
}

class TarDownloader: NSObject, URLSessionDownloadDelegate {
    /**
     Class that takes 3 mandatory arguments
     fromUrl: the http url from where we download
     onProgress: (Double) called as the download progresses progress is passed to the function
     onComplete: (URL) called when download + extraction is complete the URL
     onError: (Error) called at any point there's an error
     */
    var fromUrl: URL
    var downloadDir: URL
    var onProgress: (Double) -> Void
    var onComplete: (URL) -> Void
    var onError: (Error) -> Void
    
    /// What must be inside downloadDir for a cached download to count, relative
    /// to it. Nil means the caller cannot say, and the cache is then trusted on
    /// the archive alone.
    ///
    /// This exists because the cache lives in ~/Library/Caches, which macOS
    /// empties whenever it likes -- that is what the directory is for -- while
    /// the "already downloaded" flag lives in preferences, which it does not.
    /// The two drift apart on their own, and the drift used to be silent.
    var expecting: String?

    init(fromUrl: URL, expecting: String? = nil, onProgress: @escaping (Double) -> Void, onComplete: @escaping (URL) -> Void, onError: @escaping (Error) -> Void) {
        self.downloadDir = TarDownloader.getDownloadsDir()
        self.expecting = expecting
        self.fromUrl = fromUrl
        self.onProgress = onProgress
        self.onError = onError
        self.onComplete = onComplete
        super.init()
    }
    
    public static func getDownloadsDir() -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("\(appName)/downloads")
    }
    
    public static func deleteAllDownloadCache() {
        let downloadDir = TarDownloader.getDownloadsDir()
        try? FileManager.default.removeItem(at: downloadDir)
        deleteUsrDefOptionStartsWith(prefix: "downloads")
    }
    
    func download() {
        let f = FileManager.default
        console.log(self.fromUrl.debugDescription)
        if let lastDownloadedPath = readUsrDefOptionString(key: namespacedKey("downloads", self.fromUrl.lastPathComponent)),
           lastDownloadedPath == self.fromUrl.path(percentEncoded: false) {
            // The flag is not the evidence. Ask the disk.
            let present = expecting.map {
                f.fileExists(atPath: downloadDir.appendingPathComponent($0).path(percentEncoded: false))
            } ?? f.fileExists(atPath: downloadDir.appendingPathComponent(fromUrl.lastPathComponent).path(percentEncoded: false))
            if present {
                console.log("download cache found, skipping download")
                return self.onComplete(self.downloadDir)
            }
            console.warn("download cache flag is set but \(expecting ?? fromUrl.lastPathComponent) is gone; downloading again")
            deleteUsrDefOption(key: namespacedKey("downloads", self.fromUrl.lastPathComponent))
        }
        try? f.createDirectory(at: downloadDir, withIntermediateDirectories: true, attributes: nil)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session.downloadTask(with: fromUrl).resume()
    }
    
    private func extract() -> Process {
        let filename = fromUrl.lastPathComponent
        let dest = downloadDir.appendingPathComponent(filename) // assuming the file has the correct extension
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", dest.path, "-C", downloadDir.path] // just xf autodetects the compression format
        return process
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100
        DispatchQueue.main.async {
            self.onProgress(progress) // percentage
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let f = FileManager.default
        let destination = downloadDir.appendingPathComponent(fromUrl.lastPathComponent)
        
        do {
            if f.fileExists(atPath: destination.path) {
                try f.removeItem(at: destination)
            }
            try f.moveItem(at: location, to: destination)
            let process = extract()
            process.terminationHandler = { process in
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        self.onComplete(self.downloadDir)
                        persistUsrDefOptionString(key: namespacedKey("downloads", self.fromUrl.lastPathComponent), value: self.fromUrl.path(percentEncoded: false))
                    } else {
                        let error = NSError(domain: "TarDownloader", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "tar extraction failed"])
                        self.onError(error)
                    }
                }
            }
            // Not `try?`. The continuation that waits on this resumes only
            // from onComplete or onError, and terminationHandler never fires
            // for a process that failed to launch -- so swallowing this hung
            // the patching run for good.
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { self.onError(error) }
            }
        } catch {
            DispatchQueue.main.async { self.onError(error) }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            DispatchQueue.main.async { self.onError(error) }
        }
    }
    
    func clearTemp() {
        try? FileManager.default.removeItem(at: downloadDir )
    }
}
