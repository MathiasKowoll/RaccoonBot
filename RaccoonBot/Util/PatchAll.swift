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
        if let reason = MGVFCoordinator.refusal() {
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

            // A refusal partway through a sweep is usually the sweep's own
            // doing. Three of the installers write their per-application
            // overrides by running reg.exe through wine, which leaves a
            // wineserver and its services up for a few seconds afterwards --
            // and the guard cannot tell those from a game. One run patched six
            // titles and reported the remaining nine as refused, with nothing
            // running but what it had started itself. So let the bottle settle
            // and offer the title once more.
            if coordinator.blocked != nil, await Self.waitForQuiet() {
                if coordinator.canUpdate {
                    await coordinator.update()
                } else if coordinator.canInstall {
                    await coordinator.install()
                }
            }

            if let blocked = coordinator.blocked {
                // Still busy after waiting it out, so it is not our own
                // furniture: something is genuinely open, and every title left
                // would say the same thing. Nine identical failures read as
                // nine separate problems, so stop and say where we reached.
                failures.append(Failure(title: target.title, reason: blocked))
                refusedReason = blocked
                return
            }
            if let error = coordinator.lastError {
                failures.append(Failure(title: target.title, reason: error))
            } else {
                patched.append(target.title)
            }
            done += 1
        }
    }

    /// Wait for the bottle to go quiet, up to a point.
    ///
    /// A wineserver an installer started goes away on its own once its last
    /// process has, which is seconds. Waiting much longer would mean waiting
    /// out somebody's actual game, and that is not this button's business --
    /// so it gives up, and the caller says so rather than guessing.
    private static func waitForQuiet(upTo seconds: Int = 20) async -> Bool {
        for _ in 0..<seconds {
            try? await Task.sleep(for: .seconds(1))
            // Off the main actor. Asking spawns pgrep twice and waits for
            // both, and asking twenty times from the thread that draws the
            // progress would stall the window this sweep is reporting into.
            let quiet = await Task.detached(priority: .utility) {
                MGVFCoordinator.reasonNotToWrite() == nil
            }.value
            if quiet { return true }
        }
        return false
    }
}
