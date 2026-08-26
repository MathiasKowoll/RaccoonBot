//
//  MGVFLibrary.swift
//  RaccoonBot
//
//  The cheap half of the question, for the whole library at once.
//
//  Asking an installer is a process, a shell and several registry queries
//  through wine. Doing that for every card at load would spawn dozens of wine
//  processes to draw a grid. So the library asks a question that costs a
//  stat(2): does the catalogue know this folder, and is its carrier still the
//  game's own file? That is enough to mark a card and to decide whether to say
//  anything before a launch. The authoritative answer -- which also checks the
//  registry -- is asked once, in the game's own options.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Combine

@MainActor
final class MGVFLibrary: ObservableObject {
    static let shared = MGVFLibrary()

    /// Bumped when the catalogue arrives, so views redraw once it is known.
    @Published private(set) var generation = 0

    private var catalog: MGVFCatalog?
    private var loading = false

    private init() {}

    /// Load the catalogue once. Safe to call from every view that appears.
    func loadIfNeeded() async {
        guard catalog == nil, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let directory = try await MGVFBundle.shared.ensureAvailable()
            let manifest = try MGVFBundle.shared.manifest(at: directory)
            catalog = MGVFCatalog(manifest: manifest, directory: directory)
            generation += 1
        } catch {
            console.warn("Fixes catalogue unavailable: \(error.localizedDescription)")
        }
    }

    /// Does a fix exist for this folder at all?
    func entry(for folder: String?) -> MGVFGame? {
        guard let folder, let catalog else { return nil }
        return catalog.entry(forFolder: folder)
    }

    /// Should this title be marked as needing its fix?
    ///
    /// File-level only, and deliberately so. The carrier is renamed rather than
    /// replaced, so the presence of the kept-aside original is a good proxy for
    /// "the fix is on" without asking wine anything. It can be wrong in one
    /// direction -- files in place while the registry override is missing -- and
    /// that case is caught by the real check in the game's options, which is
    /// also the only place that can do anything about it.
    func needsPatch(folder: String?) -> Bool {
        guard let folder, let catalog, let entry = catalog.entry(forFolder: folder) else { return false }
        if catalog.isDismissed(folder) { return false }
        var url = URL(fileURLWithPath: folder)
        if !entry.carrierDir.isEmpty { url.appendPathComponent(entry.carrierDir) }
        let keptAside = url.appendingPathComponent(entry.keptAs).path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: keptAside) { return true }
        // The fix is on. Is it the one the bundle carries now? The catalogue
        // memoises the answer, so this stays a dictionary lookup per row
        // rather than a hash of every file the fix installs.
        return catalog.isOutdated(folder: folder, game: entry)
    }
}
