//
//  FixSummary.swift
//  RaccoonBot
//
//  One sentence for what the fix row has counted.
//
//  Written out rather than inflected. `^[...](inflect: true)` is automatic
//  grammar agreement, resolved by the localisation system -- and this
//  application ships no localisation resources at all: no .lproj, no
//  .xcstrings, no .stringsdict, measured on the built bundle. With nothing to
//  resolve against, the markup is passed through, and what reached the panel
//  was its own source: "^[4 installed title](inflect: true) needs its video
//  fix".
//
//  So the plurals are spelled here, including the verbs, which agreement would
//  have had to handle anyway -- "1 title needs" and "4 titles need". It is more
//  words than the markup and it cannot fail silently into being read out loud.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated enum FixSummary {

    static let allWell = "Every installed title that needs a fix has one."

    /// What the three counts add up to, in one sentence.
    ///
    /// Three facts and never a subtraction. A title with an older fix IS
    /// patched, and calling that "needs its video fix" reads as though nothing
    /// is installed -- five titles were described that way once. A title whose
    /// bottle has been updated may still be patched, and saying nothing about
    /// it would be claiming that it is. The version that derived the second
    /// count as `total - missing` was right only while there were two answers.
    static func sentence(missing: Int, outdated: Int, unverified: Int) -> String {
        var said: [String] = []
        if missing > 0 {
            said.append(missing == 1
                ? "1 installed title needs its video fix"
                : "\(missing) installed titles need their video fix")
        }
        if outdated > 0 {
            said.append(outdated == 1 ? "1 has an older one" : "\(outdated) have an older one")
        }
        if unverified > 0 {
            said.append(unverified == 1
                ? "1 is in a bottle that has been updated since it was patched"
                : "\(unverified) are in bottles that have been updated since they were patched")
        }
        guard !said.isEmpty else { return allWell }
        return said.joined(separator: "; ") + "."
    }

    /// What a finished sweep reports.
    static func patched(_ count: Int) -> String {
        count == 1 ? "Patched 1 title" : "Patched \(count) titles"
    }
}
