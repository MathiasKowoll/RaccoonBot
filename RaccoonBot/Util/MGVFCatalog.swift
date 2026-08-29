//
//  MGVFCatalog.swift
//  RaccoonBot
//
//  Which fix belongs to which game, and what state that game is in.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// What RaccoonBot can say about one game folder.
enum GameFixState: Equatable {
    /// Nothing in the catalogue matches this title. Most of a library.
    case noFix
    /// A fix exists and is applied.
    case patched
    /// A fix exists, is applied, and the bundle now carries a different one.
    ///
    /// Not `needsPatch`: nothing is broken and nothing is missing. It is the
    /// case that used to be invisible -- a title fixed from an old bundle
    /// stayed "patched" forever, and an improved fix only ever reached people
    /// who had not applied the old one yet.
    case outdated
    /// A fix exists and is not applied.
    case needsPatch
    /// A fix exists, was applied, and the user removed it on purpose.
    ///
    /// Kept apart from `needsPatch` because a patch can stop being necessary --
    /// an engine that starts shipping the codec, a game that gets updated --
    /// and re-offering it on every launch would turn a decision into a nag.
    case dismissed
    /// The installer could not answer. NOT `needsPatch`: "we could not look" and
    /// "it is not there" are different facts, and only one of them is a reason
    /// to write to the user's game folder.
    case unknown(String)

    var isActionable: Bool {
        switch self {
        case .needsPatch, .outdated: return true
        default: return false
        }
    }

    /// True where there is a fix on disk, current or not.
    var isApplied: Bool {
        switch self {
        case .patched, .outdated: return true
        default: return false
        }
    }
}

/// Remembers the decisions a user made about a folder.
///
/// Keyed by folder path rather than by title or app id: two copies of the same
/// game in two Steam libraries are two installations, and a decision about one
/// is not a decision about the other.
protocol MGVFDecisionStore: AnyObject {
    /// By TITLE, not by script: four scripts serve more than one game --
    /// install-runtime-fix.sh serves four -- so a pairing kept by script name
    /// shows the wrong title and the wrong reason.
    func pairedTitle(for folder: String) -> String?
    func setPairedTitle(_ title: String?, for folder: String)
    func isDismissed(_ folder: String) -> Bool
    func setDismissed(_ dismissed: Bool, for folder: String)
    /// The fingerprint of the fix that was applied to this folder, if we wrote
    /// it. Nil for a folder patched by a build that did not record one.
    func appliedFingerprint(for folder: String) -> String?
    func setAppliedFingerprint(_ fingerprint: String?, for folder: String)
}

final class MGVFUserDefaultsStore: MGVFDecisionStore {
    private let defaults: UserDefaults
    private let pairKey = "mgvf.pairedTitles"
    private let dismissKey = "mgvf.dismissedFolders"
    private let appliedKey = "mgvf.appliedFingerprints"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var pairs: [String: String] {
        get { defaults.dictionary(forKey: pairKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: pairKey) }
    }
    private var dismissed: Set<String> {
        get { Set(defaults.stringArray(forKey: dismissKey) ?? []) }
        set { defaults.set(Array(newValue), forKey: dismissKey) }
    }

    func pairedTitle(for folder: String) -> String? { pairs[folder] }
    func setPairedTitle(_ title: String?, for folder: String) {
        var p = pairs
        if let title { p[folder] = title } else { p.removeValue(forKey: folder) }
        pairs = p
    }
    private var applied: [String: String] {
        get { defaults.dictionary(forKey: appliedKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: appliedKey) }
    }

    func appliedFingerprint(for folder: String) -> String? { applied[folder] }
    func setAppliedFingerprint(_ fingerprint: String?, for folder: String) {
        var a = applied
        if let fingerprint { a[folder] = fingerprint } else { a.removeValue(forKey: folder) }
        applied = a
    }

    func isDismissed(_ folder: String) -> Bool { dismissed.contains(folder) }
    func setDismissed(_ value: Bool, for folder: String) {
        var d = dismissed
        if value { d.insert(folder) } else { d.remove(folder) }
        dismissed = d
    }
}

final class MGVFCatalog: @unchecked Sendable {
    let manifest: MGVFManifest
    /// The unpacked bundle: the scripts, their DLLs and pe.pl, all in one flat
    /// directory because they resolve each other with `dirname "$0"`.
    let directory: URL
    private let store: MGVFDecisionStore
    private let fileManager: FileManager

    init(manifest: MGVFManifest,
         directory: URL,
         store: MGVFDecisionStore = MGVFUserDefaultsStore(),
         fileManager: FileManager = .default) {
        self.manifest = manifest
        self.directory = directory
        self.store = store
        self.fileManager = fileManager
    }

    // MARK: - Which fix belongs to this folder

    /// Match by the shipping executable, then by what the user chose.
    ///
    /// The executable is the identity. Not a Steam app id -- neither repository
    /// records one -- and not the folder name, which Valve chooses: Mortal
    /// Shell 2 installs into a folder called "Sparta".
    ///
    /// The manual pairing is not a fallback for a bad guess; it is the answer
    /// for every title whose entry carries no executable, which today is eight
    /// of the ten. It is remembered so the question is asked once.
    func entry(forFolder folder: String) -> MGVFGame? {
        if let automatic = automaticEntry(forFolder: folder) { return automatic }
        guard let title = store.pairedTitle(for: folder) else { return nil }
        return manifest.games.first { $0.name == title }
    }

    func automaticEntry(forFolder folder: String) -> MGVFGame? {
        manifest.games.first { game in
            guard !game.exe.isEmpty else { return false }
            return executableExists(game.exe, under: folder)
        }
    }

    /// The executable sits either in the folder itself, or under an Unreal
    /// project's Binaries/Win64. Bounded on purpose: a full recursive walk of a
    /// game folder is thousands of files for a question with two answers.
    private func executableExists(_ exe: String, under folder: String) -> Bool {
        let root = URL(fileURLWithPath: folder)
        if fileManager.fileExists(atPath: root.appendingPathComponent(exe).path(percentEncoded: false)) {
            return true
        }
        guard let children = try? fileManager.contentsOfDirectory(atPath: folder) else { return false }
        for child in children {
            let candidate = root.appendingPathComponent(child)
                .appendingPathComponent("Binaries/Win64")
                .appendingPathComponent(exe)
            if fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) { return true }
        }
        return false
    }

    /// Titles the user can be offered when the automatic match finds nothing.
    var pairableGames: [MGVFGame] { manifest.games }

    /// Every title this catalogue knows a fix for, for telling one catalogue
    /// from the one before it.
    var allTitles: [String] { manifest.games.map(\.name) }

    /// The fingerprint of a title's fix as this bundle carries it.
    ///
    /// Memoised: it reads and hashes the script and every file the fix
    /// installs, and the library asks the same question once per row.
    private var fingerprints: [String: String] = [:]
    private let fingerprintLock = NSLock()

    func currentFingerprint(for game: MGVFGame) -> String {
        fingerprintLock.lock()
        defer { fingerprintLock.unlock() }
        if let cached = fingerprints[game.name] { return cached }
        let value = game.fingerprint(inDirectory: directory)
        fingerprints[game.name] = value
        return value
    }

    /// Record which fix a folder now has. Called after applying one.
    func recordApplied(folder: String, game: MGVFGame) {
        store.setAppliedFingerprint(currentFingerprint(for: game), for: folder)
    }

    /// Is the fix on this folder one the bundle no longer carries?
    ///
    /// False when nothing was recorded. A folder patched by a build that did
    /// not write a fingerprint is a folder we cannot speak about, and "we did
    /// not look" is not "it is stale" -- the same distinction `unknown` makes
    /// against `needsPatch`.
    func isOutdated(folder: String, game: MGVFGame) -> Bool {
        guard let applied = store.appliedFingerprint(for: folder) else { return false }
        return applied != currentFingerprint(for: game)
    }

    func forgetApplied(folder: String) { store.setAppliedFingerprint(nil, for: folder) }

    /// Did this application install a fix here, and does it still say so?
    ///
    /// The record is written on a successful install and cleared on restore, so
    /// for a fix that leaves nothing beside the game it is what we know without
    /// asking anybody. Its installer can still be asked -- and must be, before
    /// acting, since a record is a memory and the bottle is the fact -- but not
    /// once per row while a list of fifty-eight titles is drawn.
    func hasApplied(folder: String) -> Bool { store.appliedFingerprint(for: folder) != nil }

    func pair(folder: String, to game: MGVFGame) { store.setPairedTitle(game.name, for: folder) }
    func unpair(folder: String) { store.setPairedTitle(nil, for: folder) }

    // MARK: - Decisions

    func isDismissed(_ folder: String) -> Bool { store.isDismissed(folder) }
    func dismiss(folder: String) { store.setDismissed(true, for: folder) }
    func undismiss(folder: String) { store.setDismissed(false, for: folder) }

    // MARK: - State

    func scriptPath(for game: MGVFGame) -> String {
        directory.appendingPathComponent(game.script).path(percentEncoded: false)
    }

    /// Ask the installer, and translate its answer into something the interface
    /// can show without overstating it.
    /// Asked of the right thing.
    ///
    /// A bottle-scoped fix is asked about the BOTTLE, not the game folder.
    /// Passing the folder is why `--status` answered `error: not a bottle` and
    /// exited 1, which became `.unknown`, which made `canInstall` false -- so
    /// the gate could never be cleared from inside the interface for a fix that
    /// was already installed and working on disk.
    ///
    /// With several bottles the answer is the worst of them. "Installed in one
    /// of the two" is not installed, and reporting the better half would hide
    /// precisely the case this change exists to stop.
    func state(forFolder folder: String, bottles: [BottleReference]) async -> GameFixState {
        guard let game = entry(forFolder: folder) else { return .noFix }
        // Nothing to install and nothing to ask: what this title needs is a
        // staged codec, which is a property of the engine, not of the folder.
        if game.isCodecOnly { return .noFix }
        if store.isDismissed(folder) { return .dismissed }
        let placements = game.placements(gameFolder: folder, bottles: bottles)
        guard !placements.isEmpty else { return .unknown("No bottle is configured for this fix") }
        do {
            var worst: GameFixState?
            for placement in placements {
                let result = try await MGVFRunner.shared.run(script: scriptPath(for: game),
                                                             target: placement.target,
                                                             bottle: placement.bottle,
                                                             verb: .status)
                let state = Self.state(from: result)
                if worst == nil || Self.isWorse(state, than: worst!) { worst = state }
            }
            guard let state = worst else { return .unknown("the installer gave no answer") }
            // The script answers whether a fix is on, which is not whether it
            // is the one the bundle now carries.
            if state == .patched, isOutdated(folder: folder, game: game) { return .outdated }
            return state
        } catch {
            return .unknown(error.localizedDescription)
        }
    }

    /// Which answer to believe when the bottles disagree. Ordered by how much
    /// it should stop us: not knowing beats needing a patch, which beats being
    /// patched. Never the other way round.
    static func isWorse(_ lhs: GameFixState, than rhs: GameFixState) -> Bool {
        func rank(_ state: GameFixState) -> Int {
            switch state {
            case .unknown: return 3
            case .needsPatch: return 2
            case .outdated: return 1
            default: return 0
            }
        }
        return rank(lhs) > rank(rhs)
    }

    /// `broken` and `half` are both "a fix is here and it is not working", which
    /// is a reason to offer applying it again -- not a reason to claim it is
    /// absent, and not an error to hide.
    static func state(from result: MGVFResult) -> GameFixState {
        switch result.state {
        case .installed: return .patched
        case .absent, .broken, .half: return .needsPatch
        case nil:
            let detail = MGVFRunner.redacted(result.stderr.isEmpty ? result.stdout : result.stderr)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .unknown(detail.isEmpty ? "the installer gave no answer" : detail)
        }
    }
}
