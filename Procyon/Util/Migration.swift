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

    static func run(into defaults: UserDefaults = .standard) {
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
