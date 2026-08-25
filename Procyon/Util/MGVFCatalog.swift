//
//  MGVFCatalog.swift
//  Procyon
//
//  Which fix belongs to which game, and what state that game is in.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// What Procyon can say about one game folder.
enum GameFixState: Equatable {
    /// Nothing in the catalogue matches this title. Most of a library.
    case noFix
    /// A fix exists and is applied.
    case patched
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
        case .needsPatch: return true
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
}

final class MGVFUserDefaultsStore: MGVFDecisionStore {
    private let defaults: UserDefaults
    private let pairKey = "mgvf.pairedTitles"
    private let dismissKey = "mgvf.dismissedFolders"

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
    func state(forFolder folder: String) async -> GameFixState {
        guard let game = entry(forFolder: folder) else { return .noFix }
        // Nothing to install and nothing to ask: what this title needs is a
        // staged codec, which is a property of the engine, not of the folder.
        if game.isCodecOnly { return .noFix }
        if store.isDismissed(folder) { return .dismissed }
        do {
            let result = try await MGVFRunner.shared.run(script: scriptPath(for: game),
                                                         gameFolder: folder,
                                                         verb: .status)
            return Self.state(from: result)
        } catch {
            return .unknown(error.localizedDescription)
        }
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
