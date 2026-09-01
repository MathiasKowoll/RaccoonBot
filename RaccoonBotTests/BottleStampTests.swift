//
//  BottleStampTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Whether the record of a bottle-scoped fix can still be vouched for.
///
/// A fix that installs into a bottle leaves nothing beside the game, so the
/// only evidence it happened is the record this application keeps -- and wine
/// can revert it without us. Measured 2026-08-31: an update rewrote 1,475
/// files under one bottle's `drive_c/windows`, put back three of the four DLLs
/// the NINJA GAIDEN 3 fix had installed, and left the record saying it was
/// there.
struct BottleStampTests {

    private func makeBottle(_ name: String, stamp: String?) throws -> BottleReference {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stamp-\(UUID().uuidString)")
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let stamp {
            try stamp.write(to: dir.appendingPathComponent(BottleStamp.fileName),
                            atomically: true, encoding: .utf8)
        }
        return try #require(BottleReference(dir.path(percentEncoded: false)))
    }

    @Test func aStampIsReadFromTheBottle() throws {
        let bottle = try makeBottle("Steam", stamp: "1784108640")
        #expect(BottleStamp.read(bottle) == "1784108640")
        #expect(BottleStamp.current(for: [bottle]) == "Steam=1784108640")
    }

    /// Absent is a value, not an error: a bottle that later acquires a stamp
    /// has changed, and so has one that loses it.
    @Test func aBottleWithNoStampReadsAsAbsentRatherThanFailing() throws {
        let bottle = try makeBottle("Steam", stamp: nil)
        #expect(BottleStamp.read(bottle) == nil)
        #expect(BottleStamp.current(for: [bottle]) == "Steam=-")
    }

    /// The order the settings happen to list bottles in is not a change.
    @Test func theOrderOfTheBottlesDoesNotChangeTheStamp() throws {
        let steam = try makeBottle("Steam", stamp: "111")
        let epic = try makeBottle("Epic", stamp: "222")
        #expect(BottleStamp.current(for: [steam, epic]) == BottleStamp.current(for: [epic, steam]))
    }

    /// The name is in the string, so adding a bottle counts as a change -- it
    /// is one, for a fix that is meant to be in all of them.
    @Test func addingABottleIsAChange() throws {
        let steam = try makeBottle("Steam", stamp: "111")
        let epic = try makeBottle("Epic", stamp: "222")
        #expect(BottleStamp.current(for: [steam]) != BottleStamp.current(for: [steam, epic]))
    }

    /// A bare name has nowhere to look. That has to compare equal to itself,
    /// or every redraw would report a change.
    @Test func aBottleWithNoDirectoryIsStableRatherThanUnknown() throws {
        let bare = try #require(BottleReference("Steam"))
        #expect(BottleStamp.read(bare) == nil)
        #expect(BottleStamp.current(for: [bare]) == BottleStamp.current(for: [bare]))
    }
}
