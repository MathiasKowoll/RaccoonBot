import Foundation

/// Unreal's per-title configuration, written before the title has ever run.
///
/// Every Unreal game on D3DMetal opens with the same dialog:
///
///     WARNING: Known issues with graphics driver
///     AMD Compatibility Mode
///     Installed: 010.00   Recommended: 610.88 or latest driver available
///
/// It is cosmetic and it is ours, not the game's. D3DMetal presents the
/// adapter as "AMD Compatibility Mode" carrying NVIDIA's vendor id with a
/// user-mode driver version of "10.00", so Unreal matches its NVIDIA
/// deny-list and warns. The check is one console variable,
/// `r.WarnOfBadDrivers`, and Unreal reads it from the title's own
/// `Engine.ini` under `[SystemSettings]` -- the highest-priority layer there
/// is, above `-dpcvars=` on the command line.
///
/// There is no engine-wide switch. Unreal reads configuration per install, so
/// "turn it off for every game" has to be done per game, by us, at launch.
///
/// The whole difficulty is *which directory*. The file belongs at
///
///     drive_c/users/<user>/AppData/Local/<Project>/Saved/Config/Windows/Engine.ini
///
/// where `<Project>` is the Unreal project name compiled into the build. It is
/// not the Steam folder, and it is not reliably the directory on disk:
///
///     Crash Bandicoot 4   on disk "Lava"      in AppData "CrashBandicoot4"
///     SILENT HILL 2       on disk "SHProto"   in AppData "SilentHill2"
///
/// so `ProjectResolution` asks the sources in order of how much they know, and
/// `reconcile(after:)` repairs a wrong guess once the title has run and the
/// real directory exists.
enum UnrealConfig {

    /// The one setting this writes today. A dictionary rather than a constant
    /// because the next one costs a line here and nothing anywhere else.
    static let systemSettings: [String: String] = [
        "r.WarnOfBadDrivers": "0",
    ]

    // MARK: - Recognising an Unreal title

    /// True when `exe` is an Unreal shipping executable.
    ///
    /// Matched on the path rather than the name: `Binaries/Win64` is Unreal's
    /// own staging layout and every cooked build has it, while the executable
    /// may be `<Project>-Win64-Shipping.exe` or plainly `<Project>.exe`
    /// (Dawnwalker, Crash Bandicoot 4, Mortal Kombat 1 all ship the latter).
    static func isUnreal(exe: URL) -> Bool {
        let parts = exe.pathComponents
        guard parts.count >= 3 else { return false }
        let n = parts.count
        return parts[n - 2].caseInsensitiveCompare("Win64") == .orderedSame
            && parts[n - 3].caseInsensitiveCompare("Binaries") == .orderedSame
    }

    // MARK: - Which directory

    /// Where a project name came from, so the caller can say how much to trust
    /// it and the log can say why we wrote where we wrote.
    enum ProjectSource: String {
        /// Steam's own cloud-save path for this app id. Authoritative: it is
        /// the directory Steam syncs, which is the directory Unreal writes.
        case steamCloud = "Steam cloud path"
        /// Epic's `CloudSaveFolder`, in the one shape that names a project.
        /// Not yet confirmed against a directory on disk, because no Epic
        /// Unreal title here has run and written one.
        case epicCloudSave = "Epic cloud-save attribute"
        /// The executable's name with Unreal's build suffix removed. Correct
        /// for every title on this machine that could be checked, including
        /// the two the on-disk directory gets wrong.
        case executable = "executable name"
        /// A directory Unreal itself created, found after the title ran.
        case observed = "observed after a run"
    }

    struct ProjectResolution {
        let name: String
        let source: ProjectSource
        /// True only for a name read from something that already knows where
        /// the title writes. Everything else is a good guess, and
        /// `reconcile(bottle:guessed:launchedAt:)` is what settles it.
        var isCertain: Bool { source == .steamCloud || source == .observed }
    }

    /// Resolves the Unreal project directory name, in order of confidence.
    ///
    /// `steamAppID` is for Steam titles. `epicCloudSaveFolder` is the raw
    /// `customAttributes.CloudSaveFolder` value from Epic's catalogue cache,
    /// which `EpicCatalog` already reads -- Epic's installed-title `.item`
    /// manifests carry no save directory, but the catalogue does. It is passed
    /// in rather than looked up here so this stays testable on its own.
    /// `exe` is optional because a Steam launch does not have one: the command
    /// is `steam.exe -applaunch <id>`, and the app id is the whole of what is
    /// known. Epic launches the executable, so there it is real.
    static func resolveProject(exe: URL?,
                               steamAppID: String? = nil,
                               steamRoot: URL? = nil,
                               epicCloudSaveFolder: String? = nil,
                               bottleForLibrary: URL? = nil) -> ProjectResolution? {
        if let id = steamAppID, let root = steamRoot,
           let name = SteamAppInfo.savedGamesProject(appID: id, steamRoot: root) {
            return ProjectResolution(name: name, source: .steamCloud)
        }
        if let raw = epicCloudSaveFolder, let name = projectFromEpicCloudSave(raw) {
            return ProjectResolution(name: name, source: .epicCloudSave)
        }
        if let exe, let name = projectFromExecutable(exe) {
            return ProjectResolution(name: name, source: .executable)
        }
        // A Steam launch arrives with no executable, so find it: the app id
        // names a manifest, the manifest names a directory, and the directory
        // holds an Unreal executable whose name is the project. This is what
        // takes the coverage from "the titles Steam syncs saves for" to "every
        // Unreal title installed".
        if let id = steamAppID, let root = steamRoot, let bottle = bottleForLibrary,
           let found = SteamLibrary.unrealExecutable(appID: id, steamRoot: root, bottle: bottle),
           let name = projectFromExecutable(found) {
            return ProjectResolution(name: name, source: .executable)
        }
        return nil
    }

    /// The project directory out of an Epic `CloudSaveFolder` template, and
    /// only when the template actually names one.
    ///
    /// `{AppData}` is the bottle's `AppData/Local`, so `{AppData}/X/...` looks
    /// promising -- but the first component is only the Unreal project when a
    /// `Saved` follows it. Measured against the catalogue cache on this
    /// machine, the same prefix carries three other shapes:
    ///
    ///     {AppData}/Sifu/Saved/SaveGames/{EpicID}/      Sifu      an Unreal project
    ///     {AppData}/Saber/WWZ/client/storage/           Saber     a publisher
    ///     {AppData}/Remedy/AlanWake2/{EpicID}/          Remedy    a publisher
    ///     {AppData}/../Roaming/IO Interactive/...       ..        not Local at all
    ///
    /// Taking the first component of any `{AppData}` path would send two of
    /// those to a publisher's directory with full confidence. Requiring the
    /// `Saved` segment is what makes this safe, and it is also what makes it
    /// Unreal-specific, which is all this file wants.
    ///
    /// The other shape Epic uses, `My Games/X/Saved/...`, is deliberately not
    /// accepted: that `X` is the display name, not the project -- Borderlands 3
    /// gives "Borderlands 3" where the directory is `OakGame`.
    static func projectFromEpicCloudSave(_ raw: String) -> String? {
        let parts = raw.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3, parts[0] == "{AppData}", parts[2] == "Saved" else { return nil }
        let name = parts[1]
        return SteamAppInfo.isPlausibleProjectName(name) ? name : nil
    }

    /// `MortalShell2-Win64-Shipping.exe` -> `MortalShell2`, `Dawnwalker.exe`
    /// -> `Dawnwalker`.
    ///
    /// The suffixes are Unreal's own build-target names. Only a trailing match
    /// is stripped, so a title genuinely called `Shipping` keeps its name.
    static func projectFromExecutable(_ exe: URL) -> String? {
        var name = exe.deletingPathExtension().lastPathComponent
        for suffix in ["-Win64-Shipping", "-Win64-Test", "-Win64-Development", "-Shipping"] {
            if name.hasSuffix(suffix) {
                name.removeLast(suffix.count)
                break
            }
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "_ -"))
        return name.isEmpty ? nil : name
    }

    // MARK: - The one call a launch makes

    /// Writes what Unreal titles need into the bottle, before the title starts.
    ///
    /// Called for every launch and quiet about the ones it does not apply to.
    /// It resolves the project directory from whatever the launch actually
    /// knows -- which is not the same for the two stores:
    ///
    ///   Steam    launches `steam.exe -applaunch <id>`, so there is no
    ///            executable path here, only the app id. Steam's own cloud-save
    ///            record is what answers.
    ///   Epic     launches the executable, so `exe` is real and its name
    ///            answers, with the catalogue's CloudSaveFolder ahead of it.
    ///
    /// When neither answers, this writes nothing and says so. Nothing is
    /// guessed into a directory that might be another title's.
    static func applyAtLaunch(bottle: URL,
                              steamAppID: String? = nil,
                              steamRoot: URL? = nil,
                              exe: URL? = nil,
                              epicCloudSaveFolder: String? = nil) {
        if let exe, !isUnreal(exe: exe) { return }

        guard let resolved = resolveProject(exe: exe,
                                            steamAppID: steamAppID,
                                            steamRoot: steamRoot,
                                            epicCloudSaveFolder: epicCloudSaveFolder,
                                            bottleForLibrary: bottle)
        else {
            // Only worth a line when there was reason to think it was Unreal.
            if exe != nil {
                console.log("Unreal config: no project directory could be named for \(exe!.lastPathComponent)")
            }
            return
        }

        do {
            if try ensureEngineIni(bottle: bottle, project: resolved.name) {
                console.log("Unreal config: \(resolved.name) (\(resolved.source.rawValue))"
                            + (resolved.isCertain ? "" : " -- a guess, checked after the run"))
            }
        } catch {
            console.error("Unreal config: could not write into \(resolved.name): \(error)")
        }
    }

    // MARK: - Writing it

    /// Ensures `Engine.ini` in `bottle` carries `systemSettings` for `project`,
    /// creating the directory tree when the title has never run.
    ///
    /// Idempotent on purpose, and deliberately *not* made read-only. A
    /// read-only file is the obvious way to stop Unreal dropping the section,
    /// and it also blocks any legitimate write the title makes to its own
    /// `Engine.ini`. Re-asserting the keys on every launch costs one small
    /// file read and survives the title rewriting the file, without taking
    /// anything away from it.
    ///
    /// Returns true when the file was created or changed.
    @discardableResult
    static func ensureEngineIni(bottle: URL, project: String) throws -> Bool {
        let dir = configDirectory(bottle: bottle, project: project)
        let file = dir.appendingPathComponent("Engine.ini")
        let f = FileManager.default

        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let merged = merge(systemSettings, into: existing)
        guard merged != existing else { return false }

        try f.createDirectory(at: dir, withIntermediateDirectories: true)
        // The title may have left it read-only; a previous version of this
        // code did exactly that, and so did the hand edit that preceded it.
        if f.fileExists(atPath: file.path), !f.isWritableFile(atPath: file.path) {
            try? f.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        }
        try merged.write(to: file, atomically: true, encoding: .utf8)
        return true
    }

    static func configDirectory(bottle: URL, project: String) -> URL {
        userDirectory(bottle: bottle)
            .appendingPathComponent("AppData/Local")
            .appendingPathComponent(project)
            .appendingPathComponent("Saved/Config/Windows")
    }

    /// The bottle's Windows user directory.
    ///
    /// `crossover` on every bottle this project makes, but read from disk
    /// rather than assumed, because a bottle made by something else names it
    /// after the macOS account.
    static func userDirectory(bottle: URL) -> URL {
        let users = bottle.appendingPathComponent("drive_c/users")
        let ignored: Set<String> = ["Public", "Default", "Default User", "All Users"]
        let found = (try? FileManager.default.contentsOfDirectory(atPath: users.path))?
            .filter { !ignored.contains($0) && !$0.hasPrefix(".") }
            .sorted()
        return users.appendingPathComponent(found?.first ?? "crossover")
    }

    /// Adds or updates `settings` under `[SystemSettings]`, leaving every other
    /// line of the file exactly as it was.
    ///
    /// Written as a line rewrite rather than a parse because these files are
    /// not quite INI: Unreal's own `;METADATA=(...)` first line, `+Key=`
    /// array syntax and duplicate keys all survive a rewrite that only touches
    /// the lines it recognises, and none of them survive a round trip through
    /// a strict parser.
    static func merge(_ settings: [String: String], into contents: String) -> String {
        var lines = contents.isEmpty ? [] : contents.components(separatedBy: "\n")
        var remaining = settings
        var sectionStart: Int?
        var sectionEnd = lines.count

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }
            if sectionStart == nil,
               trimmed.caseInsensitiveCompare("[SystemSettings]") == .orderedSame {
                sectionStart = i
            } else if sectionStart != nil {
                sectionEnd = i
                break
            }
        }

        guard let start = sectionStart else {
            // No section yet. A new file also wants Unreal's metadata line, or
            // the title rewrites the file wholesale on first save.
            var out: [String] = []
            if contents.isEmpty {
                out.append(";METADATA=(Diff=true, UseCommands=true)")
            } else {
                out = lines
                if out.last?.trimmingCharacters(in: .whitespaces).isEmpty == false { out.append("") }
            }
            out.append("[SystemSettings]")
            out.append(contentsOf: settings.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })
            out.append("")
            return out.joined(separator: "\n")
        }

        for i in (start + 1)..<min(sectionEnd, lines.count) {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "="), !trimmed.hasPrefix(";") else { continue }
            let key = String(trimmed[trimmed.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            guard let wanted = remaining[key] else { continue }
            lines[i] = "\(key)=\(wanted)"
            remaining.removeValue(forKey: key)
        }

        if !remaining.isEmpty {
            let insert = min(sectionEnd, lines.count)
            lines.insert(contentsOf: remaining.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" },
                         at: insert)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Repairing a wrong guess

    /// After a title has run, says which directory Unreal actually used.
    ///
    /// Once the title has started, the answer stops being a guess: Unreal
    /// writes `GameUserSettings.ini` into its own configuration directory. Any
    /// directory holding one that was written since `since` belongs to the
    /// title that just ran.
    static func observedProject(bottle: URL, since: Date) -> String? {
        let local = userDirectory(bottle: bottle).appendingPathComponent("AppData/Local")
        let f = FileManager.default
        guard let entries = try? f.contentsOfDirectory(atPath: local.path) else { return nil }
        var newest: (name: String, date: Date)?
        for name in entries {
            let marker = local.appendingPathComponent(name)
                .appendingPathComponent("Saved/Config/Windows/GameUserSettings.ini")
            guard let attrs = try? f.attributesOfItem(atPath: marker.path),
                  let modified = attrs[.modificationDate] as? Date,
                  modified >= since else { continue }
            if newest == nil || modified > newest!.date { newest = (name, modified) }
        }
        return newest?.name
    }

    /// Moves the setting to the directory the title really uses, when the guess
    /// was wrong, and removes the directory the guess created.
    ///
    /// Call after a session ends, with the time the title was launched. Does
    /// nothing in the common case where the guess was right.
    @discardableResult
    static func reconcile(bottle: URL, guessed: String, launchedAt: Date) -> String? {
        guard let real = observedProject(bottle: bottle, since: launchedAt),
              real.caseInsensitiveCompare(guessed) != .orderedSame else { return nil }

        do {
            try ensureEngineIni(bottle: bottle, project: real)
            console.log("Unreal config: the title uses \(real), not \(guessed); moved and applied there")
        } catch {
            console.error("Unreal config: could not write into \(real): \(error)")
            return nil
        }

        // Remove what the guess created, but only when it is ours and empty of
        // anything the title would miss -- a wrong guess that happens to name
        // another title's directory must not lose that title's settings.
        let orphan = userDirectory(bottle: bottle)
            .appendingPathComponent("AppData/Local").appendingPathComponent(guessed)
        let f = FileManager.default
        let saved = orphan.appendingPathComponent("Saved")
        let onlyOurs = (try? f.subpathsOfDirectory(atPath: saved.path))?
            .filter { !$0.hasSuffix(".ini") || $0.hasSuffix("Engine.ini") }
            .allSatisfy { var d: ObjCBool = false
                          return f.fileExists(atPath: saved.appendingPathComponent($0).path, isDirectory: &d) && d.boolValue }
        if onlyOurs == true { try? f.removeItem(at: orphan) }
        return real
    }
}

// MARK: - Steam's cloud-save path

/// The Unreal project name as Steam records it, read before the title has run.
///
/// Steam keeps per-app metadata in `appcache/appinfo.vdf`, and for a title
/// that syncs saves it records the path it syncs -- for an Unreal game,
/// `<Project>/Saved/SaveGames` under the `WinAppDataLocal` root. That is
/// exactly the directory this file needs, and it is right where the directory
/// on disk is wrong: `CrashBandicoot4` for a game installed into `Lava`,
/// `SilentHill2` for one installed into `SHProto`.
///
/// Only some titles carry it -- ten of forty-six installed on the machine this
/// was written against -- so this is the first source asked and never the only
/// one.
enum SteamAppInfo {

    /// `appinfo.vdf` is a length-delimited sequence of app records. Rather
    /// than decode Valve's binary VDF, this walks the record index to find the
    /// one blob belonging to `appID` and then scans that blob for the path.
    /// Scanning the whole file instead would happily return another game's
    /// directory, which is the one failure that would be worse than returning
    /// nothing.
    static func savedGamesProject(appID: String, steamRoot: URL) -> String? {
        guard let id = UInt32(appID) else { return nil }
        let url = steamRoot.appendingPathComponent("appcache/appinfo.vdf")
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 16 else { return nil }
        guard let blob = record(for: id, in: data) else { return nil }
        guard blob.range(of: Data("WinAppDataLocal".utf8)) != nil else { return nil }
        return firstSavedPathComponent(in: blob)
    }

    /// Walks `appid, size, <size bytes>` records and returns the one blob.
    private static func record(for appID: UInt32, in data: Data) -> Data? {
        // Past the magic and universe; newer files then carry a string-table
        // offset. Both layouts are tried, and a layout that does not produce a
        // terminating record is abandoned rather than trusted.
        for start in [8, 16] {
            var p = start
            while p + 8 <= data.count {
                let id = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: p, as: UInt32.self) }
                if id == 0 { break }
                let size = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: p + 4, as: UInt32.self) })
                guard size > 0, p + 8 + size <= data.count else { break }
                if id == appID { return data.subdata(in: (p + 8)..<(p + 8 + size)) }
                p += 8 + size
            }
        }
        return nil
    }

    /// Pulls `Dawnwalker` out of `Dawnwalker/Saved/SaveGames`.
    ///
    /// The project is the FIRST component of the recorded path, not the one
    /// before `Saved`. Most titles record `<Project>/Saved/SaveGames` and the
    /// two readings agree, but not all do: Returnal records
    /// `Returnal/Steam/Saved/SaveGames`, and reading backwards from `Saved`
    /// answers "Steam" -- a directory belonging to nothing, which is worse than
    /// no answer at all. Measured against this machine's appinfo.vdf.
    private static func firstSavedPathComponent(in blob: Data) -> String? {
        let needle = Data("/Saved/".utf8)
        var searchFrom = blob.startIndex
        while let hit = blob.range(of: needle, in: searchFrom..<blob.endIndex) {
            // Back up to the start of the null-terminated string, so the whole
            // recorded path is in hand rather than its tail.
            var begin = hit.lowerBound
            while begin > blob.startIndex, blob[blob.index(before: begin)] != 0 {
                begin = blob.index(before: begin)
            }
            if begin < hit.lowerBound,
               let path = String(data: blob[begin..<hit.lowerBound], encoding: .utf8) {
                let first = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).first.map(String.init)
                if let first, isPlausibleProjectName(first) { return first }
            }
            searchFrom = hit.upperBound
        }
        return nil
    }

    /// Guards against picking up a fragment. A project directory is a single
    /// path component of ordinary characters.
    static func isPlausibleProjectName(_ name: String) -> Bool {
        guard (2...64).contains(name.count) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-. "))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
            && name.rangeOfCharacter(from: .alphanumerics) != nil
    }
}

// MARK: - Finding a Steam title's executable

/// Where Steam put a title, read from Steam's own bookkeeping.
///
/// A Steam launch is `steam.exe -applaunch <id>` and carries no executable
/// path, so without this the only thing that can name an Unreal project
/// directory is Steam's cloud-save record -- and only about half the titles
/// installed here carry one. This supplies the other half: the app id names a
/// manifest, the manifest names a directory, and the directory contains an
/// Unreal executable whose name is the project.
enum SteamLibrary {

    /// The Unreal shipping executable for `appID`, or nil.
    static func unrealExecutable(appID: String, steamRoot: URL, bottle: URL) -> URL? {
        for library in libraries(steamRoot: steamRoot, bottle: bottle) {
            let apps = library.appendingPathComponent("steamapps")
            let manifest = apps.appendingPathComponent("appmanifest_\(appID).acf")
            guard let text = try? String(contentsOf: manifest, encoding: .utf8),
                  let dir = value(of: "installdir", in: text) else { continue }
            let game = apps.appendingPathComponent("common").appendingPathComponent(dir)
            if let exe = unrealExecutable(inGameFolder: game) { return exe }
        }
        return nil
    }

    /// Unreal stages as `<Game>/<Project>/Binaries/Win64/<exe>`, and a few
    /// titles drop the project level. Only those two shapes are looked at:
    /// walking a game folder is walking tens of gigabytes on an external disk,
    /// and every second of it happens while somebody is waiting to play.
    static func unrealExecutable(inGameFolder game: URL) -> URL? {
        let f = FileManager.default
        var roots = [game]
        if let children = try? f.contentsOfDirectory(at: game, includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) {
            roots.append(contentsOf: children.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            })
        }
        for root in roots {
            let win64 = root.appendingPathComponent("Binaries/Win64")
            guard let entries = try? f.contentsOfDirectory(atPath: win64.path) else { continue }
            let exes = entries.filter { $0.lowercased().hasSuffix(".exe") }
            // The shipping build first; then anything, for the titles that ship
            // a plain <Project>.exe. Crash reporters and the online-services
            // helpers are never the title.
            let ignored = ["crashreport", "eosbootstrapper", "epicwebhelper", "eac", "_be.exe"]
            let usable = exes.filter { name in !ignored.contains { name.lowercased().contains($0) } }
            if let shipping = usable.first(where: { $0.lowercased().hasSuffix("-shipping.exe") }) {
                return win64.appendingPathComponent(shipping)
            }
            if usable.count == 1 { return win64.appendingPathComponent(usable[0]) }
        }
        return nil
    }

    /// Every library Steam knows about, as a path on this Mac.
    ///
    /// The paths in `libraryfolders.vdf` are the bottle's, not the Mac's:
    /// `Z:` is wine's name for the root of the filesystem and `C:` is the
    /// bottle's own `drive_c`. Anything else is skipped rather than guessed at.
    static func libraries(steamRoot: URL, bottle: URL) -> [URL] {
        var out: [URL] = []
        for name in ["config/libraryfolders.vdf", "steamapps/libraryfolders.vdf"] {
            guard let text = try? String(contentsOf: steamRoot.appendingPathComponent(name),
                                         encoding: .utf8) else { continue }
            for raw in values(of: "path", in: text) {
                guard let url = macPath(forWindowsPath: raw, bottle: bottle) else { continue }
                if !out.contains(url) { out.append(url) }
            }
        }
        if out.isEmpty { out = [steamRoot] }
        return out
    }

    static func macPath(forWindowsPath raw: String, bottle: URL) -> URL? {
        let path = raw.replacingOccurrences(of: "\\\\", with: "/")
                      .replacingOccurrences(of: "\\", with: "/")
        guard path.count >= 2, path.dropFirst().hasPrefix(":") else { return nil }
        let drive = path.first!.lowercased()
        let rest = String(path.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch drive {
        case "z": return URL(fileURLWithPath: "/" + rest)
        case "c": return bottle.appendingPathComponent("drive_c").appendingPathComponent(rest)
        default:  return nil
        }
    }

    /// Steam's key-value text is `"key"<whitespace>"value"`, one per line.
    static func values(of key: String, in text: String) -> [String] {
        var out: [String] = []
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            // "" key "" gap "" value ""  ->  indices 1 and 3
            guard parts.count >= 4, parts[1] == Substring(key) else { continue }
            out.append(String(parts[3]))
        }
        return out
    }

    static func value(of key: String, in text: String) -> String? { values(of: key, in: text).first }
}
