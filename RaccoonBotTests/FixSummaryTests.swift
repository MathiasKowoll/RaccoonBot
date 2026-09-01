//
//  FixSummaryTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// The sentence under the fix row.
///
/// It used to be built with `^[...](inflect: true)`, which is resolved by the
/// localisation system -- and this application ships no localisation
/// resources: no .lproj, no .xcstrings, no .stringsdict. With nothing to
/// resolve against, the markup went through untouched and the panel showed its
/// own source to the user. Spelling the plurals out is more words and cannot
/// do that.
struct FixSummaryTests {

    /// The guard that would have caught it. Nothing this returns may contain
    /// markup, for any combination of counts.
    @Test func noSentenceEverContainsMarkup() {
        for missing in 0...2 {
            for outdated in 0...2 {
                for unverified in 0...2 {
                    let text = FixSummary.sentence(missing: missing,
                                                   outdated: outdated,
                                                   unverified: unverified)
                    #expect(!text.contains("^["), "markup reached the sentence: \(text)")
                    #expect(!text.contains("inflect"), "markup reached the sentence: \(text)")
                }
            }
        }
        #expect(!FixSummary.patched(1).contains("^["))
        #expect(!FixSummary.patched(4).contains("^["))
    }

    /// One and many, including the verb -- which is the half automatic
    /// agreement would have had to get right too.
    @Test func oneReadsAsOneAndManyAsMany() {
        #expect(FixSummary.sentence(missing: 1, outdated: 0, unverified: 0)
                == "1 installed title needs its video fix.")
        #expect(FixSummary.sentence(missing: 4, outdated: 0, unverified: 0)
                == "4 installed titles need their video fix.")
        #expect(FixSummary.patched(1) == "Patched 1 title")
        #expect(FixSummary.patched(3) == "Patched 3 titles")
    }

    /// Nothing to say is said, rather than left blank.
    @Test func nothingWrongSaysSo() {
        #expect(FixSummary.sentence(missing: 0, outdated: 0, unverified: 0) == FixSummary.allWell)
        #expect(FixSummary.allWell.hasSuffix("."))
    }

    /// Three facts, never a subtraction. A title with an older fix is patched,
    /// and one whose bottle moved may still be.
    @Test func eachCountIsSaidSeparately() {
        let all = FixSummary.sentence(missing: 2, outdated: 3, unverified: 1)
        #expect(all.contains("2 installed titles need their video fix"))
        #expect(all.contains("3 have an older one"))
        #expect(all.contains("1 is in a bottle that has been updated since it was patched"))
        #expect(all.hasSuffix("."))
        // The outdated ones are not folded into the ones that need a fix.
        #expect(!all.contains("5"))
    }

    /// A count of zero contributes no clause at all, rather than "0 titles".
    @Test func aZeroIsNotMentioned() {
        let one = FixSummary.sentence(missing: 0, outdated: 2, unverified: 0)
        #expect(one == "2 have an older one.")
        #expect(!one.contains("0"))
    }
}
