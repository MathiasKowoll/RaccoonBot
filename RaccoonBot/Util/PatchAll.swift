//
//  PatchAll.swift
//  RaccoonBot
//
//  Applying every fix a library needs, in one go.
//
//  Built on the same per-title coordinator the options screen uses rather than
//  beside it: the install path already knows how to check the state, refuse
//  while a game is running, and report what went wrong. A batch that reached
//  past it would be a second install path to keep in step.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Combine

@MainActor
final class PatchAll: ObservableObject {

    struct Target: Identifiable {
        let title: String
        let folder: String
        var id: String { folder }
    }

    struct Failure: Identifiable {
        let title: String
        let reason: String
        var id: String { title }
    }

    @Published private(set) var running = false
    @Published private(set) var current: String?
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var patched: [String] = []
    @Published private(set) var failures: [Failure] = []
    @Published private(set) var refusedReason: String?

    /// Titles that are actually installed, in any library, and need their fix.
    ///
    /// `metas` is every library folder's scan, so this walks all of them. Three
    /// things are checked rather than assumed:
    ///
    ///   installdir      an entry with none is an owned title, not an installed one
    ///   isDownloaded()  a half-downloaded game has no executable to patch yet
    ///   the folder      Steam libraries live on external drives, and an entry
    ///                   for an unmounted one is a path that is simply not there
    ///
    /// Dismissed titles are deliberately excluded. Dismissing exists to stop the
    /// nagging -- and a button that sweeps them back up is the nagging.
    /// Takes the question as a closure rather than the catalogue itself: what
    /// this decides is which titles are ELIGIBLE, which is a separate matter
    /// from which ones the catalogue knows about, and it can then be checked
    /// without one.
    nonisolated static func targets(from metas: [GamesMeta],
                        needsPatch: (String) -> Bool,
                        fileManager: FileManager = .default) -> [Target] {
        metas.compactMap { meta in
            guard !meta.installdir.isEmpty, meta.installdir != "unknown" else { return nil }
            guard meta.isDownloaded() else { return nil }
            guard let folder = meta.gameURL?.path(percentEncoded: false),
                  fileManager.fileExists(atPath: folder) else { return nil }
            guard needsPatch(folder) else { return nil }
            return Target(title: meta.name ?? meta.installdir, folder: folder)
        }
    }

    /// The bottles are handed in rather than read here, so that a sweep over
    /// the whole library cannot reach a bottle the caller did not name.
    func run(_ targets: [Target], bottles: [BottleReference]) async {
        guard !running else { return }

        // Asked once, before touching anything. Applying a fix renames files in
        // a game folder, and doing that to a running game is how a library ends
        // up half-patched.
        if let reason = MGVFCoordinator.reasonNotToWrite() {
            refusedReason = reason
            return
        }

        running = true
        refusedReason = nil
        patched = []
        failures = []
        done = 0
        total = targets.count
        defer { running = false; current = nil }

        for target in targets {
            current = target.title
            let coordinator = MGVFCoordinator()
            await coordinator.load(folder: target.folder, bottles: bottles)

            // Two different jobs. A title with no fix gets one installed; a
            // title whose fix the bundle has since changed gets the old one
            // taken off and the new one put on, because every installer
            // refuses to write over a fix that is already there.
            if coordinator.canUpdate {
                await coordinator.update()
            } else if coordinator.canInstall {
                await coordinator.install()
            } else {
                // Not a failure: nothing to do, or already done.
                done += 1
                continue
            }

            if let blocked = coordinator.blocked {
                failures.append(Failure(title: target.title, reason: blocked))
            } else if let error = coordinator.lastError {
                failures.append(Failure(title: target.title, reason: error))
            } else {
                patched.append(target.title)
            }
            done += 1
        }
    }
}
