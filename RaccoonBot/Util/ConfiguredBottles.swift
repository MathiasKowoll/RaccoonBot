//
//  ConfiguredBottles.swift
//  RaccoonBot
//
//  Which bottles this application is configured with -- one question, and one
//  place that answers it.
//
//  There was no such place before, and the cost was visible. The launcher
//  picked a bottle with one expression, the three Stop buttons with another
//  (`selectedBottle` unconditionally, so stopping an ARM title asked the wrong
//  bottle's Steam to quit), and the patch path with none at all. Having asked
//  nobody, a Kingdom Hearts fix went and found bottles for itself: four of
//  them, none of them ours, one with something open, and six executables that
//  "did not take every override" in a bottle we do not own and must not touch.
//
//  So the rule, in the owner's words: a patch installs into the bottles
//  RaccoonBot defines, and if there are ten it is ten. The set is DERIVED from
//  the configuration and never DISCOVERED from the disk. That distinction is
//  the whole defect: four bottles chosen by a script's own criterion, against
//  N read from what somebody actually configured.
//

import Foundation

nonisolated enum ConfiguredBottles {

    /// ARM is deliberately out of scope for now (decided 2026-08-29).
    ///
    /// A named constant rather than a scattered condition, so that letting ARM
    /// in later is one edit with one test beside it -- not a search through
    /// every site that quietly assumed a single bottle. It is also why nothing
    /// below counts: Epic arrives this week and takes the set to two, and code
    /// that says "one" or "two" anywhere would have to be found again then.
    static let armIncluded = false

    enum Failure: LocalizedError, Equatable {
        case noneConfigured
        case noneOnDisk([String])

        var errorDescription: String? {
            switch self {
            case .noneConfigured:
                return "No bottle is configured. Choose one in the options before installing a fix."
            case .noneOnDisk(let names):
                return "Configured, but not on disk: \(names.joined(separator: ", ")). "
                     + "Nothing was installed rather than installing somewhere else."
            }
        }
    }

    /// What was asked for, and what of it is actually there.
    struct Selection: Equatable {
        /// Bottles that are configured and present, in configuration order.
        let usable: [BottleReference]
        /// Configured, but nothing at that path. Reported rather than skipped:
        /// a fix that quietly passes over a bottle somebody configured leaves
        /// them believing it was patched.
        let missing: [String]
    }

    /// Every bottle the settings name, parsed.
    ///
    /// Through `BottleReference` and never by hand. These are stored as
    /// `file://` URLs, and hand-rolled `URL(string:)?.lastPathComponent` is
    /// what once handed `wine` a URL where a bottle NAME belonged.
    ///
    /// Empty strings are dropped rather than becoming a bottle named "": the
    /// ARM entry is empty until somebody chooses one, and on this machine it
    /// currently names a directory that does not exist at all.
    static func configured(selected: String, arm: String) -> [BottleReference] {
        var entries = [selected]
        if armIncluded { entries.append(arm) }
        return entries.compactMap(BottleReference.init)
    }

    /// The same, checked against the disk.
    ///
    /// Matched by the configured PATH, never by name. Names are not unique
    /// here: stock CrossOver already carries a bottle called `Epic Games
    /// Store`, so once Epic is integrated a name match would pick exactly the
    /// neighbour we must never write into. A reference with no directory came
    /// from a bare name and cannot be checked, so it counts as missing rather
    /// than being taken on trust.
    static func onDisk(_ references: [BottleReference]) -> Selection {
        var usable: [BottleReference] = []
        var missing: [String] = []
        for reference in references {
            guard let directory = reference.directory,
                  FileManager.default.fileExists(
                      atPath: directory.appendingPathComponent("drive_c").path(percentEncoded: false))
            else {
                missing.append(reference.name)
                continue
            }
            usable.append(reference)
        }
        return Selection(usable: usable, missing: missing)
    }

    /// What a patch is allowed to touch.
    ///
    /// Throws rather than returning nothing. An empty list handed to something
    /// that installs is the shape that invites a fallback, and the fallback is
    /// what went looking for bottles on its own.
    static func forPatching(selected: String, arm: String) throws -> Selection {
        try forPatching(configured(selected: selected, arm: arm))
    }

    static func forPatching(_ references: [BottleReference]) throws -> Selection {
        guard !references.isEmpty else { throw Failure.noneConfigured }
        let selection = onDisk(references)
        guard !selection.usable.isEmpty else { throw Failure.noneOnDisk(selection.missing) }
        if !selection.missing.isEmpty {
            console.warn("configured but not on disk, skipped: \(selection.missing.joined(separator: ", "))")
        }
        return selection
    }
}
