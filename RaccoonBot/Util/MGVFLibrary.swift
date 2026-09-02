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

    /// A library over a known catalogue, for a test to ask the same questions
    /// the rows ask without loading a bundle. Not for the application: there
    /// is one library and it loads its own.
    init(catalog: MGVFCatalog) {
        self.catalog = catalog
        self.generation = 1
    }

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
        /// A fix we recorded installing, into a bottle that has been updated
        /// since. Not "gone" -- an update reverts a bottle's own system files
        /// and may or may not have taken this fix with it. Only the installer
        /// can say which, and this is what says it is worth asking.
        case unverified
    }

    /// The bottles anything that writes into a bottle is allowed to touch.
    ///
    /// Read here rather than handed in, because the two callers that most need
    /// the answer -- a row being drawn and a game about to launch -- have no
    /// bottle to hand. These are the same defaults `AppGlobals` initialises
    /// from and `OptionsView` persists on change, parsed by the one accessor
    /// that is allowed to parse them.
    private var configuredBottles: [BottleReference] {
        ConfiguredBottles.configured(selected: readUsrDefOptionString(key: "selectedBottle") ?? "",
                                     arm: readUsrDefOptionString(key: "selectedArmBottle") ?? "")
    }

    // MARK: - What a bottle fix's row says

    /// The installer's answer for a bottle-scoped fix, kept per title.
    ///
    /// A fix that installs into a bottle leaves nothing beside the game, so a
    /// row used to read the record of "we installed it" -- and that record is
    /// per application identity and only ever written from here. NINJA GAIDEN
    /// 3, installed from the released application and fully present in the
    /// bottle, read as unpatched in the development build; a fix installed by
    /// hand read as unpatched in both. The disk was right and the row was not.
    ///
    /// So the row asks the installer, which is the only thing that can say,
    /// and keeps the answer. The key is the bottles' stamp joined to the
    /// record: wine moves the stamp when it updates a bottle, and installing
    /// or restoring from here moves the record, so either kind of change asks
    /// again and nothing else does. One process per real change, not one per
    /// redraw, which is the cost the old comment was right to refuse.
    private var bottleAnswers: [String: (key: String, need: FixNeed)] = [:]
    private var asking: Set<String> = []

    private func bottleNeed(folder: String, entry: MGVFGame, catalog: MGVFCatalog) -> FixNeed {
        let bottles = configuredBottles
        let key = BottleStamp.current(for: bottles) + "|" + (catalog.appliedFingerprint(folder: folder) ?? "-")
        if let known = bottleAnswers[folder], known.key == key { return known.need }
        if !asking.contains(folder) {
            asking.insert(folder)
            Task { @MainActor in
                let state = await catalog.state(forFolder: folder, bottles: bottles)
                bottleAnswers[folder] = (key, Self.need(from: state))
                asking.remove(folder)
                generation += 1
            }
        }
        // Not known yet. Said as such rather than guessed either way.
        return .unverified
    }

    /// The installer's word, as the row's.
    static func need(from state: GameFixState) -> FixNeed {
        switch state {
        case .patched:            return .none
        case .outdated:           return .outdated
        case .needsPatch:         return .missing
        case .unknown:            return .unverified
        case .noFix, .dismissed:  return .none
        }
    }

    func need(folder: String?) -> FixNeed {
        guard let folder, let catalog, let entry = catalog.entry(forFolder: folder) else { return .none }
        if catalog.isDismissed(folder) { return .none }
        if entry.installsIntoBottle {
            return bottleNeed(folder: folder, entry: entry, catalog: catalog)
        }
        // Where the installer actually put the original, not where the
        // manifest says the carrier lives: for the Unreal titles that is one
        // subfolder further down, and looking only where told refused four
        // patched titles at launch.
        guard entry.keptAsideOriginal(inGameFolder: folder) != nil else { return .missing }
        return catalog.isOutdated(folder: folder, game: entry) ? .outdated : .none
    }

    /// Is the fix NOT on this title? Only that.
    ///
    /// This drives the card's badge and the launch gate, and both used to
    /// fire for an older fix as well as for none: the badge is one icon and
    /// the gate says "needs its video fix", so a title whose fix was on and
    /// working read as unpatched the day the bundle moved. It happened to NINJA
    /// GAIDEN 3 the moment 5.0.5 was embedded -- its installer had changed,
    /// so its fingerprint had, and a fix that played video yesterday was
    /// refused at launch as absent today.
    ///
    /// An older fix is present. It is reported by need(folder:) as .outdated,
    /// counted in the summary, and offered to the sweep; it is not a reason
    /// to refuse a launch or to mark a card as broken.
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
            // The launch gate and the sweep. "Not checked yet" is not a reason
            // to refuse a launch, so only a known absence or a known older fix
            // counts here; the sweep offers the unverified ones separately,
            // through need(folder:), and the coordinator asks properly.
            return bottleNeed(folder: folder, entry: entry, catalog: catalog) == .missing
        }
        // Same lookup as need(folder:), through the entry, so the two cannot
        // disagree about where a fix leaves its evidence.
        // The fix is on or it is not. Whether it is the newest is a different
        // question, answered by need(folder:), and not this one's to conflate.
        return entry.keptAsideOriginal(inGameFolder: folder) == nil
    }
}
