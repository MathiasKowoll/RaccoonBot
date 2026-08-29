//
//  MGVFNewTitlesTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Telling one catalogue from the one before it.
///
/// A new bundle usually means a new game rather than a change to an old one,
/// and somebody who fixed a title last week has no way of knowing this machine
/// now knows about it.
@Suite("Noticing a title that did not have a fix before")
struct MGVFNewTitlesTests {

    private func added(seen: Set<String>, now: Set<String>) -> [String] {
        seen.isEmpty ? [] : now.subtracting(seen).sorted()
    }

    /// The first catalogue a machine ever reads is not nineteen pieces of news.
    @Test func theFirstCatalogueAnnouncesNothing() {
        #expect(added(seen: [], now: ["Nioh", "NINJA GAIDEN 4", "Wo Long"]).isEmpty)
    }

    /// The case this exists for: v4.11.1 adding Ninja Gaiden 3 to a machine
    /// that had read v4.11.0.
    @Test func aTitleThatWasNotThereBeforeIsNews() {
        #expect(added(seen: ["Nioh", "NINJA GAIDEN 4"],
                      now: ["Nioh", "NINJA GAIDEN 4", "NINJA GAIDEN 3: Razor's Edge"])
                == ["NINJA GAIDEN 3: Razor's Edge"])
    }

    @Test func thesameCatalogueTwiceIsNotNews() {
        let titles: Set<String> = ["Nioh", "NINJA GAIDEN 4"]
        #expect(added(seen: titles, now: titles).isEmpty)
    }

    /// A withdrawn fix -- MGS4 went in 4.11.0 -- is not an addition, and must
    /// not make the titles around it look new either.
    @Test func aWithdrawnTitleIsNotAnAddition() {
        #expect(added(seen: ["Nioh", "METAL GEAR SOLID 4"], now: ["Nioh"]).isEmpty)
    }

    /// Withdrawing one and adding another in the same release reports only the
    /// addition.
    @Test func aWithdrawalAndAnAdditionTogetherReportOnlyTheAddition() {
        #expect(added(seen: ["Nioh", "METAL GEAR SOLID 4"],
                      now: ["Nioh", "NINJA GAIDEN 3: Razor's Edge"])
                == ["NINJA GAIDEN 3: Razor's Edge"])
    }

    /// A title withdrawn and later restored is news again, which is right: the
    /// machine was told it had gone.
    @Test func aTitleThatComesBackIsNewsAgain() {
        var seen: Set<String> = ["Nioh", "MGS4"]
        seen.formUnion(["Nioh"])                       // a catalogue without MGS4
        #expect(added(seen: seen, now: ["Nioh", "MGS4"]).isEmpty,
                "still remembered, because the record is what was ever seen")
    }
}
