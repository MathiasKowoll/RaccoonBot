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

    var canInstall: Bool { entry != nil && state.isActionable && !busy }
    var canRemove: Bool { entry != nil && state == .patched && !busy }

    /// Load the catalogue and look this folder up.
    ///
    /// The bundle is fetched if it is missing and refreshed on its own
    /// schedule; neither blocks the interface, and neither writes to a game
    /// folder. Downloading is safe, applying is not, and only one of the two
    /// happens without being asked for.
    func load(folder: String?) async {
        guard let folder else {
            state = .noFix; entry = nil; return
        }
        self.folder = folder
        do {
            let directory = try await MGVFBundle.shared.ensureAvailable()
            let manifest = try MGVFBundle.shared.manifest(at: directory)
            let catalog = MGVFCatalog(manifest: manifest, directory: directory)
            self.catalog = catalog
            self.entry = catalog.entry(forFolder: folder)
            self.state = await catalog.state(forFolder: folder)
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
    static func reasonNotToWrite() -> String? {
        let running = NSWorkspace.shared.runningApplications.compactMap {
            $0.executableURL?.lastPathComponent.lowercased()
        }
        if running.contains(where: { $0.hasSuffix(".exe") }) {
            return "A Windows game is running. Close it first — the fix renames a file it may have open."
        }
        if running.contains(where: { $0.contains("wineserver") || $0 == "steam" }) {
            return "Steam is running. Close it first — the fix renames a file it may have open."
        }
        return nil
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
