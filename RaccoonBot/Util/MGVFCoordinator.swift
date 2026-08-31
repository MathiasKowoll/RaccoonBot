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
        self.steamFullBoot = nil
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
        if let reason = Self.reasonNotToWrite() { blocked = reason; return }
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
            if outcome.succeeded { catalog.recordApplied(folder: folder, game: entry) }
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
        if let reason = Self.reasonNotToWrite() { blocked = reason; return }
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
                catalog.recordApplied(folder: folder, game: entry)
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
        if let reason = Self.reasonNotToWrite() { blocked = reason; return }
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
    static func reasonNotToWrite(because: String = "the fix renames a file it may have open") -> String? {
        if pgrepMatches("[.]exe") {
            return "A Windows game is running. Close it first — \(because)."
        }
        if pgrepMatches("wineserver") {
            return "Steam or CrossOver is still running. Close it first — \(because)."
        }
        return nil
    }

    /// True when at least one process matches. A failure to ask is not a
    /// licence to write: it returns true, so the refusal stands.
    private static func pgrepMatches(_ pattern: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", pattern]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return true
        }
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
