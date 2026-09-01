//
//  MGVFCoordinator.swift
//  RaccoonBot
//
//  Holds the fix state for the game whose options are open, and is the only
//  place that decides whether writing to a game folder is allowed right now.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import AppKit
import Combine

@MainActor
extension GameOptionsData {
    /// A patch with nothing in it.
    ///
    /// The other initialiser, `init(data:)`, is a SNAPSHOT: it copies a whole
    /// `GameOptions`, and 19 of that class's 23 fields are not optional, so a
    /// freshly constructed one arrives carrying nineteen concrete defaults
    /// rather than nineteen absences. `importAutoConfig` writes every non-nil
    /// field it is given. Building a one-field recommendation on top of a
    /// snapshot therefore overwrites every other setting the user had saved for
    /// that game -- silently, because each written value is a legal one.
    ///
    /// A recommendation is a patch. It has to start empty.
    init() {
        self.cxGraphicsBackend = nil
        self.wineMSync = nil
        self.mtlHudEnabled = nil
        self.d3dMtl4Enabled = nil
        self.x87PatchEnabled = nil
        self.useArmBottle = nil
        self.dx9PatchEnabled = nil
        self.gameArguments = nil
        self.dxmtPreferredMaxFrameRate = nil
        self.dxmtMetalFXSpatial = nil
        self.dxmtMetalSpatialUpscaleFactor = nil
        self.advertiseAVX = nil
        self.envVariables = nil
        self.enableSDL = nil
        self.disableHidraw = nil
        self.ue4Hack = nil
        self.mvkArgBuff = nil
        self.vulkanLib = nil
        self.dxvk = nil
        self.wineEsync = nil
        self.d3dMEnableMetalFX = nil
        self.d3dSupportDXR = nil
        self.d3dMaxFPS = nil
    }
}

final class MGVFCoordinator: ObservableObject {
    @Published private(set) var state: GameFixState = .noFix
    @Published private(set) var entry: MGVFGame?
    @Published private(set) var busy = false
    @Published private(set) var lastError: String?
    /// Set when an action was refused rather than attempted -- the game is
    /// running, Steam is running. Not an error: a reason.
    @Published private(set) var blocked: String?

    private var catalog: MGVFCatalog?
    private var folder: String?

    /// The bottles this fix may touch, handed in by whoever loaded us.
    ///
    /// Never discovered here. An installer that was told nothing once went
    /// looking and found four bottles of its own choosing, none of them ours.
    /// Empty means "we were told nothing", which is a refusal to act and not
    /// an empty day's work -- see `runEverywhere`.
    private var bottles: [BottleReference] = []

    /// Installing is offered whenever there is something to install, and that
    /// includes a fix the user removed on purpose.
    ///
    /// Dismissing exists to stop the NAGGING -- no alert at launch, not swept
    /// up by "patch everything" -- not to take the action away. A first version
    /// of this treated `dismissed` as final, which left the only place that can
    /// act on a title showing "removed on purpose" and no button at all.
    /// Deliberately not `state.isActionable`. Outdated is actionable -- there
    /// is something to do about it -- but the thing to do is `update()`, and
    /// a plain install over a fix that is already there is a no-op the
    /// installer refuses by design.
    var canInstall: Bool {
        guard entry != nil, !busy else { return false }
        return state == .needsPatch || state == .dismissed
    }
    var canRemove: Bool { entry != nil && state.isApplied && !busy }

    /// A fix is on and the bundle carries a different one.
    var canUpdate: Bool { entry != nil && state == .outdated && !busy }

    /// The options this title is known to need, for Auto configure to apply.
    ///
    /// Empty today: the manifest describes what to install, not what to
    /// configure. The measurements exist on the other side -- NINJA GAIDEN 4
    /// needs D3DMetal 3.0 and goes to a black screen on 4.0b2 -- and have been
    /// asked for as fields. Until they arrive this returns nothing rather than
    /// guessing, because a wrong backend is worse than none.
    var recommendedOptions: GameOptionsData? {
        guard let entry else { return nil }
        var data = GameOptionsData()   // a patch, never a snapshot -- see init() above
        var touched = false

        // The backend id the picker uses folds the two together: DXMT is one
        // choice, D3DMetal is two. A title that names d3dmetal without naming a
        // generation is one that runs on either, so its choice is left alone --
        // setting one would pin a toolkit the game does not care about.
        switch (entry.backend, entry.gptk) {
        case ("dxmt", _):            data.cxGraphicsBackend = "dxmt";       touched = true
        case ("d3dmetal", "3"?):     data.cxGraphicsBackend = "d3dmetal3";  touched = true
        case ("d3dmetal", "4"?):     data.cxGraphicsBackend = "d3dmetal4";  touched = true
        default: break
        }

        if let env = entry.env, !env.isEmpty {
            data.envVariables = env.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
            touched = true
        }
        return touched ? data : nil
    }

    /// What the catalogue asks be said about how far `gptk` reaches.
    ///
    /// Shown rather than filed away: the toolkit is installed into the shared
    /// CrossOver application, so whichever game was launched last leaves its
    /// generation in place for every other one. Honouring the field is right;
    /// implying it isolates anything is not.
    private(set) var scopeWarning: String?

    /// Only for tests: the mapping from a catalogue entry to options is worth
    /// testing on its own, and reaching it otherwise would mean a download.
    func setEntryForTesting(_ game: MGVFGame) { entry = game }

    /// Load the catalogue and look this folder up.
    ///
    /// The bundle is fetched if it is missing and refreshed on its own
    /// schedule; neither blocks the interface, and neither writes to a game
    /// folder. Downloading is safe, applying is not, and only one of the two
    /// happens without being asked for.
    func load(folder: String?, bottles: [BottleReference], hasGame: Bool = true) async {
        self.bottles = bottles
        guard let folder else {
            // Silence here is indistinguishable from "this title needs
            // nothing", and the two are very different. If there is a game on
            // screen and we cannot work out where it lives, say that.
            entry = nil
            state = hasGame
                ? .unknown("Could not work out where this game is installed")
                : .noFix
            return
        }
        self.folder = folder
        do {
            let directory = try await MGVFBundle.shared.ensureAvailable()
            let manifest = try MGVFBundle.shared.manifest(at: directory)
            let catalog = MGVFCatalog(manifest: manifest, directory: directory)
            self.catalog = catalog
            self.scopeWarning = manifest.scopeWarning
            self.entry = catalog.entry(forFolder: folder)
            self.state = await catalog.state(forFolder: folder, bottles: bottles)
            console.log("MGVF folder=\(MGVFRunner.redacted(folder)) readable=\(FileManager.default.isReadableFile(atPath: folder)) entry=\(entry?.name ?? "none") state=\(state) catalog=\(manifest.games.count)")
        } catch {
            self.entry = nil
            self.state = .unknown(error.localizedDescription)
        }
    }

    func refresh() async {
        guard let folder, let catalog else { return }
        entry = catalog.entry(forFolder: folder)
        state = await catalog.state(forFolder: folder, bottles: bottles)
    }

    /// Pair this folder with a title by hand, for the entries a folder cannot
    /// identify itself against.
    func pair(with game: MGVFGame) async {
        guard let folder, let catalog else { return }
        catalog.pair(folder: folder, to: game)
        await refresh()
    }

    var pairableGames: [MGVFGame] { catalog?.pairableGames ?? [] }

    // MARK: - Writing

    /// Everything one verb did, everywhere this fix belongs.
    private struct Everywhere {
        let results: [MGVFResult]
        /// The first target that refused. One failure is a failure: a fix that
        /// went on in one bottle and not the other is not installed.
        var failure: MGVFResult? { results.first { $0.exitCode != 0 } }
        var succeeded: Bool { !results.isEmpty && failure == nil }
    }


    /// Run one verb once per target, in configuration order, and nowhere else.
    ///
    /// The targets come from the entry and the configured bottles, so a
    /// folder-scoped fix still runs exactly once against its own folder and a
    /// bottle-scoped one runs against each bottle RaccoonBot defines. An empty
    /// target list throws rather than returning quietly: "nothing to do" and
    /// "we were told nothing" look identical at the call site, and treating the
    /// second as the first is how a patch ends up somewhere nobody chose.
    ///
    /// Sequential on purpose. Two writers on one bottle registry is as bad as
    /// two on one game folder, and the second bottle is not urgent.
    private func runEverywhere(script: String,
                               entry: MGVFGame,
                               folder: String,
                               verb: MGVFRunner.Verb) async throws -> Everywhere {
        // Validated against the disk before writing, and only for a fix that
        // touches a bottle -- by scope, or by writing registry overrides from a
        // folder-scoped installer, which is what KINGDOM HEARTS does and what
        // scope alone would have missed. `forPatching` throws when nothing is
        // configured and when nothing configured is there, and names what it
        // skipped when some of it is. A fix that only rewrites a game folder
        // needs none of that: the folder was found by being read, not by being
        // configured.
        let usable = entry.needsABottle ? try ConfiguredBottles.forPatching(bottles).usable : bottles
        let placements = entry.placements(gameFolder: folder, bottles: usable)
        guard !placements.isEmpty else { throw ConfiguredBottles.Failure.noneConfigured }
        var results: [MGVFResult] = []
        for placement in placements {
            results.append(try await MGVFRunner.shared.run(script: script,
                                                           target: placement.target,
                                                           bottle: placement.bottle,
                                                           verb: verb))
        }
        return Everywhere(results: results)
    }


    /// Apply the fix. Refuses rather than forces.
    func install() async {
        guard let folder, let catalog, let entry else { return }
        if let reason = Self.refusal() { blocked = reason; return }
        blocked = nil; lastError = nil; busy = true
        defer { busy = false }
        do {
            let outcome = try await runEverywhere(script: catalog.scriptPath(for: entry),
                                                  entry: entry, folder: folder, verb: .install)
            if let failed = outcome.failure {
                lastError = MGVFRunner.redacted(failed.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            catalog.undismiss(folder: folder)
            // What was applied, so a later bundle can be compared against it.
            // Only on success: recording a fix that failed to install would
            // claim this folder is current when nothing was written.
            if outcome.succeeded { catalog.recordApplied(folder: folder, game: entry, bottles: bottles) }
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Replace an applied fix with the one the bundle now carries.
    ///
    /// Restore, then install. Not install alone: every installer refuses to
    /// write over a fix that is already there -- "already installed, nothing
    /// to do", exit 0 -- and it is right to, because its first move is to
    /// rename whatever is live aside as the original. Run twice, that would
    /// bury somebody's irreplaceable DLL under a copy of our proxy. So the old
    /// one comes off first, by the same script that put it on.
    ///
    /// Without dismissing. Removing a fix by hand is a decision to be
    /// remembered; taking one off in order to put a better one on is not.
    func update() async {
        guard let folder, let catalog, let entry else { return }
        if let reason = Self.refusal() { blocked = reason; return }
        blocked = nil; lastError = nil; busy = true
        defer { busy = false }
        do {
            let script = catalog.scriptPath(for: entry)
            let restored = try await runEverywhere(script: script, entry: entry,
                                                   folder: folder, verb: .restore)
            guard restored.succeeded else {
                // Stop here. A failed restore leaves the old fix in place,
                // which still works; carrying on would install over it.
                lastError = MGVFRunner.redacted(restored.failure?.stderr ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                catalog.forgetApplied(folder: folder)
                await refresh()
                return
            }
            // The old fix is off, so what was recorded is no longer true --
            // said before the install, so an install that fails does not leave
            // a fingerprint claiming a fix that is not there.
            catalog.forgetApplied(folder: folder)

            let installed = try await runEverywhere(script: script, entry: entry,
                                                    folder: folder, verb: .install)
            if let failed = installed.failure {
                lastError = MGVFRunner.redacted(failed.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                catalog.recordApplied(folder: folder, game: entry, bottles: bottles)
            }
            await refresh()
        } catch {
            lastError = error.localizedDescription
            await refresh()
        }
    }

    /// Take the fix off, and remember that it was on purpose.
    ///
    /// A patch can stop being necessary -- an engine that starts shipping the
    /// codec, a game that gets updated -- so removing one is a decision. It is
    /// recorded so the title is not offered again on every launch.
    func remove() async {
        guard let folder, let catalog, let entry else { return }
        if let reason = Self.refusal() { blocked = reason; return }
        blocked = nil; lastError = nil; busy = true
        defer { busy = false }
        do {
            let outcome = try await runEverywhere(script: catalog.scriptPath(for: entry),
                                                  entry: entry, folder: folder, verb: .restore)
            if let failed = outcome.failure {
                lastError = MGVFRunner.redacted(failed.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            catalog.dismiss(folder: folder)
            // The fix is off, so there is nothing to be current or stale.
            if outcome.succeeded { catalog.forgetApplied(folder: folder) }
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - When writing is not allowed

    /// Why the folder must not be touched right now, or nil.
    ///
    /// The installers rename a DLL the running game may have mapped, and `cp`
    /// opens its destination with O_TRUNC. So this refuses with a sentence and
    /// leaves the closing to the user: terminating wine processes to make room
    /// for a patch would end somebody's unsaved game.
    ///
    /// Asked with pgrep, not NSWorkspace. NSWorkspace lists applications with a
    /// bundle, and the processes that matter here have none -- wineserver and
    /// the Windows executables are started from inside CrossOver, so a check
    /// against runningApplications answers "nothing is running" while a game is
    /// very much running. Measured on this machine with wineserver-x86 and
    /// services.exe live and invisible to it.
    /// `because` names the consequence, because the two callers have different
    /// ones: applying a fix renames a file inside a game folder, restaging the
    /// codecs deletes the directory a running bottle has dylibs mapped from.
    /// Every case here still refuses. What changed is that the sentence names
    /// what was found instead of asserting what it means. The old one asked
    /// "does any command line contain `.exe`" and reported the answer as "a
    /// Windows game is running" -- a claim about a program's purpose made from
    /// evidence that only ever showed a suffix. Wine's own services carry that
    /// suffix, and a sweep creates them itself: three installers write their
    /// per-application overrides through `reg.exe`, so a run once patched six
    /// titles and reported the remaining nine as a running game, with no game
    /// anywhere on the machine.
    ///
    /// Asking runs pgrep twice and waits for it, so this is `nonisolated`: on
    /// the main actor those two waits are two stalls of the window, and the
    /// sweep asks once a second while it waits for a bottle to settle. It also
    /// writes nothing -- a question that logs cannot be asked from a thread
    /// where `console` is not safe, and `refusal(because:)` below is where the
    /// three callers that act on the answer record it.
    nonisolated static func reasonNotToWrite(because: String = "the fix renames a file it may have open") -> String? {
        reason(for: whatIsRunning(), because: because)
    }

    /// The sentence for a state, kept apart from measuring one.
    ///
    /// Separate because a caller that measures and then asks again has asked
    /// about two different instants: a process can arrive or leave in between,
    /// and the two answers then disagree for a reason nobody can see. That is
    /// not hypothetical -- a test written that way failed about one run in two.
    nonisolated static func reason(for running: Running,
                                   because: String = "the fix renames a file it may have open") -> String? {
        if running.unknown {
            return "Could not check what is running, so nothing was written."
        }

        let named = running.games
        if !named.isEmpty {
            return "\(list(named)) \(named.count == 1 ? "is" : "are") running. "
                 + "Close it first — \(because)."
        }

        if !running.executables.isEmpty || running.server {
            let what = running.executables.isEmpty ? "wineserver" : list(running.executables)
            return "The bottle is still open — \(what) still running. "
                 + "Give it a moment, or close CrossOver — \(because)."
        }

        return nil
    }

    /// The same answer, recorded. On the main actor, where `console` is only
    /// ever touched from, and beside the callers that are about to act on it.
    /// Until this existed a refusal left no trace at all, which is why a run
    /// that reported nine of them could not be diagnosed afterwards.
    static func refusal(because: String = "the fix renames a file it may have open") -> String? {
        guard let reason = reasonNotToWrite(because: because) else { return nil }
        console.warn("MGVF refused to write: \(reason)")
        return reason
    }

    /// What is alive right now, named rather than counted.
    nonisolated struct Running {
        /// Windows executables, by their own name.
        let executables: Set<String>
        /// A wineserver, with or without anything under it.
        let server: Bool
        /// pgrep could not be asked at all, which is not the same answer as
        /// finding nothing and must not be reported as one.
        let unknown: Bool

        /// The processes wine puts up for its own sake. Not one of them is a
        /// game, and every one of them can be this application's own doing.
        static let furniture: Set<String> = [
            "services.exe", "winedevice.exe", "plugplay.exe", "rpcss.exe",
            "svchost.exe", "conhost.exe", "explorer.exe", "start.exe",
            "wineboot.exe", "winemenubuilder.exe", "reg.exe", "regedit.exe",
            "rundll32.exe", "tabtip.exe", "cmd.exe",
        ]

        /// Everything that is not furniture. Steam and a game land here alike,
        /// which is why the sentence names them rather than calling them a
        /// game: the only thing measured is that they are running.
        var games: Set<String> { executables.subtracting(Self.furniture) }
    }

    /// Ask for each thing once, and keep the names.
    ///
    /// A failure to ask is carried as `unknown` rather than folded into a
    /// match, so the refusal can say which of the two happened. It refuses
    /// either way: not being able to look is not a licence to write.
    nonisolated static func whatIsRunning() -> Running {
        guard let executables = pgrepNames("[.]exe") else {
            return Running(executables: [], server: false, unknown: true)
        }
        guard let servers = pgrepNames("wineserver") else {
            return Running(executables: executables, server: false, unknown: true)
        }
        return Running(executables: executables, server: !servers.isEmpty, unknown: false)
    }

    /// The names of the processes matching a pattern, or nil when pgrep could
    /// not be run. An empty set means asked and found nothing, which is why
    /// this is optional rather than just a set.
    nonisolated private static func pgrepNames(_ pattern: String) -> Set<String>? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "-l", pattern]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            // Read before waiting. The output is a few lines, but a pipe that
            // fills while nobody reads it deadlocks, and the habit is free.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            // 0 found something, 1 found nothing. Anything else is pgrep
            // itself failing, and that is the unknown answer, not "nothing".
            guard p.terminationStatus == 0 || p.terminationStatus == 1 else { return nil }
            var names: Set<String> = []
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                // "pid  command line". Wine writes the executable as a Windows
                // path in the middle of the line, so take the token that looks
                // like one; for wineserver, which has no .exe, take the command.
                let command = line.split(separator: " ").dropFirst()
                if let exe = command.first(where: { $0.lowercased().hasSuffix(".exe") }) {
                    names.insert(lastComponent(of: String(exe)))
                } else if let first = command.first {
                    names.insert(lastComponent(of: String(first)))
                }
            }
            return names
        } catch {
            return nil
        }
    }

    /// Last component of a path written with either separator, because wine
    /// reports both: a unix path for its loader, `C:\\windows\\...` for what it runs.
    nonisolated private static func lastComponent(of path: String) -> String {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
    }

    /// Names in a sentence, in a fixed order so the same state reads the same
    /// way twice, and capped so a bottle full of services is still a sentence.
    nonisolated private static func list(_ names: Set<String>) -> String {
        let sorted = names.sorted()
        guard sorted.count > 3 else { return sorted.joined(separator: ", ") }
        return sorted.prefix(3).joined(separator: ", ") + " and \(sorted.count - 3) more"
    }

    // MARK: - Wording

    /// What to show for the current state. Kept here so the view does not
    /// invent its own phrasing for "we could not look".
    var summary: String {
        switch state {
        case .noFix:       return "No video fix for this title"
        case .patched:     return "Video fix installed"
        case .outdated:    return "A newer version of this fix is available"
        case .needsPatch:  return "Needs the video fix"
        case .dismissed:   return "Video fix removed on purpose"
        case .unknown:     return "Could not check the video fix"
        }
    }

    var detail: String? {
        switch state {
        case .unknown(let why): return why
        case .needsPatch, .patched, .outdated: return entry?.why
        default: return nil
        }
    }
}
