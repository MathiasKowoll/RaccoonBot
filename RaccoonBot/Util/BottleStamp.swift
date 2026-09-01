//
//  BottleStamp.swift
//  RaccoonBot
//
//  What a bottle looked like when we last wrote into it.
//
//  A fix that installs into a bottle leaves nothing beside the game, so the
//  only record that it happened is the one this application keeps. That record
//  is a memory rather than a fact, and the bottle can change without us: wine
//  updates a bottle whenever it meets an engine that is not the one the bottle
//  was built with, and an update rewrites the bottle's own system files.
//
//  Measured on 2026-08-31: one such update rewrote 1,475 files under
//  `drive_c/windows` of this application's Steam bottle, put back three of the
//  four DLLs the NINJA GAIDEN 3 fix had installed, and left the registry
//  override naming all four. Nothing failed and nothing was logged. The fix was
//  gone and the record still said it was there.
//
//  `--status` is the only thing that can answer properly, and asking it costs a
//  process per title -- too much while drawing a list of fifty-eight rows. This
//  is the cheap question that says WHEN to ask the expensive one: wine stamps
//  `.update-timestamp` in the bottle every time it updates one, so a stamp that
//  has moved since we patched means the record can no longer be vouched for.
//
//  It says the record is stale, never that the fix is gone. Those are different
//  claims and only the installer can make the second.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated enum BottleStamp {

    /// Wine writes this in a bottle each time it updates one.
    static let fileName = ".update-timestamp"

    /// The stamp of every bottle a fix would be written into, as one string.
    ///
    /// All of them together rather than one each, because a fix is applied to
    /// the configured set and reverted by an update to any member of it. Sorted
    /// by name so the same set of bottles always produces the same string, and
    /// the name is included so that adding or removing a bottle counts as a
    /// change -- it is one, for a fix that is meant to be in all of them.
    ///
    /// A bottle with no stamp reads as `-`, which is a value like any other: a
    /// bottle that acquires one has changed, and so has a bottle that loses it.
    static func current(for bottles: [BottleReference]) -> String {
        bottles
            .map { bottle in "\(bottle.name)=\(read(bottle) ?? "-")" }
            .sorted()
            .joined(separator: ";")
    }

    /// One bottle's stamp, or nil when there is nothing to read.
    ///
    /// A reference built from a bare name has no directory, so there is nowhere
    /// to look; that reads as absent rather than as an error, because the caller
    /// is comparing two answers and "could not look" has to compare equal to
    /// itself.
    static func read(_ bottle: BottleReference) -> String? {
        guard let directory = bottle.directory else { return nil }
        let url = directory.appendingPathComponent(fileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
