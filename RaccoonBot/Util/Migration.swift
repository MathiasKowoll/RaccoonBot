//
//  Migration.swift
//  RaccoonBot
//
//  Carries this application's own settings across the change of bundle
//  identifier.
//
//  The identifier changed because the fork shared `itmandar.Procyon` with the
//  application it came from: two bundles claiming one identity, which is why
//  Spotlight and the Dock kept opening whichever they found first. Separating
//  them is the fix, and the cost is that UserDefaults.standard is now a
//  different domain -- so what was written before would simply not be there.
//
//  Only OUR keys move. The per-game options live in the shared app group,
//  which is declared in code rather than derived from the identifier, so they
//  were never at risk. And nothing touches ~/Library/Application Support --
//  the bottles live there.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum Migration {
    private static let doneKey = "mgvf.migratedFrom.itmandar.Procyon"
    private static let previousDomain = "itmandar.Procyon"

    /// Keys this application owns. Listed rather than copied wholesale: the old
    /// domain also holds things that belong to the application it forked from,
    /// and taking those would be inheriting somebody else's state.
    private static let ours = [
        "mgvf.pairedTitles",
        "mgvf.pairedScripts",      // what pairings were called before schema 3
        "mgvf.dismissedFolders",
        "mgvf.lastUpdateCheck",
    ]

    /// Copies the per-game options out of the domain this fork used to share
    /// with upstream.
    ///
    /// A copy, not a move: the original is left intact, so a build from before
    /// the change still finds its settings. Written only where the new domain
    /// has nothing, so re-running cannot overwrite a setting changed since.
    static func carryGameOptions() {
        let key = "mgvf.migratedGroupDomain"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        defer { UserDefaults.standard.set(true, forKey: key) }

        guard let old = UserDefaults(suiteName: previousSuiteName),
              let new = UserDefaults(suiteName: suiteName) else { return }

        var carried = 0
        for (name, value) in old.dictionaryRepresentation() {
            // Skip what the system puts in every domain.
            guard !name.hasPrefix("Apple"), !name.hasPrefix("NS"), !name.hasPrefix("com.apple")
            else { continue }
            guard new.object(forKey: name) == nil else { continue }
            new.set(value, forKey: name)
            carried += 1
        }
        if carried > 0 {
            console.log("Carried \(carried) game setting(s) over from \(previousSuiteName)")
        }
    }

    static func run(into defaults: UserDefaults = .standard) {
        carryGameOptions()
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        guard let old = UserDefaults(suiteName: previousDomain) else { return }
        var moved: [String] = []
        for key in ours {
            guard defaults.object(forKey: key) == nil,
                  let value = old.object(forKey: key) else { continue }
            defaults.set(value, forKey: key)
            moved.append(key)
        }

        // Pairings were keyed by script name until the catalogue started
        // describing titles. A script that serves four games cannot say which
        // one was meant, so those are dropped rather than guessed at.
        if defaults.object(forKey: "mgvf.pairedTitles") == nil,
           defaults.object(forKey: "mgvf.pairedScripts") != nil {
            defaults.removeObject(forKey: "mgvf.pairedScripts")
            console.warn("Old pairings were kept by script name and could not be resolved to a title; they were dropped")
        }

        if !moved.isEmpty {
            console.log("Carried \(moved.count) setting(s) over from \(previousDomain)")
        }
    }
}
