//
//  MGVFCoordinator.swift
//  Procyon
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

    /// Installing is offered whenever there is something to install, and that
    /// includes a fix the user removed on purpose.
    ///
    /// Dismissing exists to stop the NAGGING -- no alert at launch, not swept
    /// up by "patch everything" -- not to take the action away. A first version
    /// of this treated `dismissed` as final, which left the only place that can
    /// act on a title showing "removed on purpose" and no button at all.
    var canInstall: Bool {
        guard entry != nil, !busy else { return false }
        return state.isActionable || state == .dismissed
    }
    var canRemove: Bool { entry != nil && state == .patched && !busy }

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
    func load(folder: String?, hasGame: Bool = true) async {
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
            self.state = await catalog.state(forFolder: folder)
            console.log("MGVF folder=\(MGVFRunner.redacted(folder)) readable=\(FileManager.default.isReadableFile(atPath: folder)) entry=\(entry?.name ?? "none") state=\(state) catalog=\(manifest.games.count)")
        } catch {
            self.entry = nil
            self.state = .unknown(error.localizedDescription)
        }
    }

    func refresh() async {
        guard let folder, let catalog else { return }
        entry = catalog.entry(forFolder: folder)
        state = await catalog.state(forFolder: folder)
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

    /// Apply the fix. Refuses rather than forces.
    func install() async {
        guard let folder, let catalog, let entry else { return }
        if let reason = Self.reasonNotToWrite() { blocked = reason; return }
        blocked = nil; lastError = nil; busy = true
        defer { busy = false }
        do {
            let result = try await MGVFRunner.shared.run(script: catalog.scriptPath(for: entry),
                                                         gameFolder: folder,
                                                         verb: .install)
            if result.exitCode != 0 {
                lastError = MGVFRunner.redacted(result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            catalog.undismiss(folder: folder)
            await refresh()
        } catch {
            lastError = error.localizedDescription
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
            let result = try await MGVFRunner.shared.run(script: catalog.scriptPath(for: entry),
                                                         gameFolder: folder,
                                                         verb: .restore)
            if result.exitCode != 0 {
                lastError = MGVFRunner.redacted(result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            catalog.dismiss(folder: folder)
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
    static func reasonNotToWrite() -> String? {
        if pgrepMatches("[.]exe") {
            return "A Windows game is running. Close it first — the fix renames a file it may have open."
        }
        if pgrepMatches("wineserver") {
            return "Steam or CrossOver is still running. Close it first — the fix renames a file it may have open."
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
        case .needsPatch:  return "Needs the video fix"
        case .dismissed:   return "Video fix removed on purpose"
        case .unknown:     return "Could not check the video fix"
        }
    }

    var detail: String? {
        switch state {
        case .unknown(let why): return why
        case .needsPatch, .patched: return entry?.why
        default: return nil
        }
    }
}
