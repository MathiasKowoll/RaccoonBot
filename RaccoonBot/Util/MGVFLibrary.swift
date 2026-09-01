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

    /// What is actually loaded, so "which fixes ran" is answerable without
    /// archaeology.
    ///
    /// Today ten unpacked versions sit under Application Support, 153 MB of
    /// them, and nothing said which one was in use -- so a fix that misbehaved
    /// could only be traced by reading directory dates. The version is read
    /// out of the manifest that was actually loaded, never from a tag we asked
    /// for, because those diverge exactly when it matters.
    @Published private(set) var loaded: LoadedFixes?

    struct LoadedFixes: Equatable {
        let version: String
        let directory: URL

        /// True when the payload came from inside this application rather than
        /// from a download. Derived by asking where it is, so it keeps telling
        /// the truth when the payload moves into the bundle.
        var isBundled: Bool {
            guard let resources = Bundle.main.resourceURL?.path(percentEncoded: false) else { return false }
            return directory.path(percentEncoded: false).hasPrefix(resources)
        }

        var describedSource: String { isBundled ? "bundled" : "downloaded" }
    }

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
            loaded = LoadedFixes(version: manifest.version, directory: directory)
            console.log("fixes \(manifest.version) loaded, \(loaded!.describedSource)")
            noteNewTitles()
            generation += 1
        } catch {
            console.warn("Fixes catalogue unavailable: \(error.localizedDescription)")
        }
    }

    /// Ask whether a newer fixes bundle exists, and take it if so.
    ///
    /// MGVFBundle has had this check, with its tests and its six-hour throttle,
    /// since before tonight -- and nothing called it. Its own comment says
    /// "called at startup and then on an interval", which described an
    /// intention rather than the code: the catalogue was fetched once per
    /// launch and a bundle published while the application was open was never
    /// seen. This machine sat on v4.8.6 while v4.11.1 was out.
    ///
    /// Throttled by the bundle itself, so calling this on every start costs one
    /// request a day rather than one a launch, and a failure leaves what is on
    /// disk exactly where it is.
    func checkForNewFixes(force: Bool = false) async {
        switch await MGVFBundle.shared.checkForUpdate(force: force) {
        case .newer(let tag), .nothingCached(let tag):
            console.log("a newer fixes bundle is available: \(tag)")
            // Dropping the catalogue is what lets the new one take effect
            // without a restart, which is the whole point of asking.
            catalog = nil
            await loadIfNeeded()
        case .upToDate(let tag):
            console.log("fixes are up to date (\(tag))")
        case .throttled:
            break
        case .unknown(let why):
            console.warn("could not check for newer fixes: \(why)")
        }
    }

    /// Asks once on opening, then keeps asking for an application left open.
    ///
    /// The first ask ignores the six-hour throttle. That throttle exists so an
    /// application does not phone home on every launch, and Mathias asked for
    /// the opposite: he publishes fixes and wants the machine that runs them
    /// current the moment it opens, not up to six hours later. One request per
    /// launch against a limit of sixty an hour is not the cost the throttle was
    /// written to avoid, and a failure changes nothing -- what is on disk stays
    /// on disk.
    ///
    /// Every ask after the first honours it, so an application left open for a
    /// week asks about thirty times rather than a hundred and sixty-eight.
    func watchForNewFixes(every interval: TimeInterval = 3600) async {
        var first = true
        while !Task.isCancelled {
            await checkForNewFixes(force: first)
            first = false
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private let seenTitlesKey = "mgvf.titlesSeen"

    /// Titles that have appeared in a catalogue this machine has read.
    private var titlesSeen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: seenTitlesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: seenTitlesKey) }
    }

    /// Titles the newest catalogue has that no catalogue read here ever did.
    ///
    /// A new bundle usually means a new game rather than a change to an old
    /// one, and that is the part worth saying out loud: somebody who fixed a
    /// title last week has no way of knowing this machine now knows about it.
    ///
    /// The first catalogue a machine ever reads announces nothing -- eighteen
    /// titles are not eighteen pieces of news -- it just records what it saw.
    @discardableResult
    func noteNewTitles() -> [String] {
        guard let catalog else { return [] }
        let now = Set(catalog.allTitles)
        let before = titlesSeen
        titlesSeen = before.union(now)
        guard !before.isEmpty else { return [] }
        let added = now.subtracting(before).sorted()
        if !added.isEmpty {
            console.log("fixes exist for \(added.count) title(s) that did not have one: "
                        + added.joined(separator: ", "))
        }
        return added
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
    /// Why a title wants attention, which is not one question.
    ///
    /// "Needs its video fix" and "has an older one" are different facts and
    /// were being reported as the same. After the payload moved from 4.12.x to
    /// the bundled 5.0.2, every title whose fix had changed in between became
    /// outdated -- correctly -- and the screen said five titles needed a fix
    /// they already had. A row that overstates is the same defect as one that
    /// understates: the person acts on what it says.
    enum FixNeed: Equatable {
        case none
        case missing
        case outdated
    }

    func need(folder: String?) -> FixNeed {
        guard let folder, let catalog, let entry = catalog.entry(forFolder: folder) else { return .none }
        if catalog.isDismissed(folder) { return .none }
        if entry.installsIntoBottle {
            guard catalog.hasApplied(folder: folder) else { return .missing }
            return catalog.isOutdated(folder: folder, game: entry) ? .outdated : .none
        }
        var url = URL(fileURLWithPath: folder)
        if !entry.carrierDir.isEmpty { url.appendPathComponent(entry.carrierDir) }
        let keptAside = url.appendingPathComponent(entry.keptAs).path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: keptAside) { return .missing }
        return catalog.isOutdated(folder: folder, game: entry) ? .outdated : .none
    }

    func needsPatch(folder: String?) -> Bool {
        guard let folder, let catalog, let entry = catalog.entry(forFolder: folder) else { return false }
        if catalog.isDismissed(folder) { return false }
        // A fix that goes into the bottle leaves nothing beside the game, so
        // there is no kept-aside original to look for: the test below would be
        // asking about a file that was never going to be there.
        //
        // What this application knows instead is what it did. A successful
        // install records a fingerprint and a restore clears it, so the answer
        // is already on disk and costs nothing -- where asking the installer
        // costs a process, and a list of fifty-eight titles redraws often.
        //
        // A memory is not the fact. The bottle can be changed by other means,
        // and --status is the only thing that can say so -- which is why it is
        // asked before installing or restoring, where being wrong matters, and
        // not while drawing a row, where it does not.
        if entry.installsIntoBottle {
            guard catalog.hasApplied(folder: folder) else { return true }
            return catalog.isOutdated(folder: folder, game: entry)
        }
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
