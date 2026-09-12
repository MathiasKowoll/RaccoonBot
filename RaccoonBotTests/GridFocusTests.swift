//
//  GridFocusTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Moving a selection around a grid of cards.
///
/// All of this is arithmetic so that it can be wrong here rather than in a
/// window with a controller in hand. The cases worth stating are the ragged
/// ones: a last row that is not full, a resize that changes the column count
/// under a selection, and a library that shrinks while something is selected.
struct GridFocusTests {

    /// 7 items, 3 across:
    ///     0 1 2
    ///     3 4 5
    ///     6
    private func ragged(at index: Int) -> GridFocus {
        GridFocus(count: 7, columns: 3, index: index)
    }

    @Test func rightAndLeftWalkTheRow() {
        var f = ragged(at: 0)
        let moved1 = f.move(.right)
        #expect(moved1)
        #expect(f.index == 1)
        let moved2 = f.move(.left)
        #expect(moved2)
        #expect(f.index == 0)
    }

    /// The end of a row is a wall, not a wrap. Wrapping to the next row reads
    /// as a jump when the grid scrolls and you cannot see all of it.
    @Test func aRowEndsRatherThanWrapping() {
        var f = ragged(at: 2)
        let moved3 = f.move(.right)
        #expect(moved3 == false)
        #expect(f.index == 2)
        var g = ragged(at: 3)
        let moved4 = g.move(.left)
        #expect(moved4 == false)
        #expect(g.index == 3)
    }

    @Test func downAndUpMoveAWholeRow() {
        var f = ragged(at: 1)
        let moved5 = f.move(.down)
        #expect(moved5)
        #expect(f.index == 4)
        let moved6 = f.move(.up)
        #expect(moved6)
        #expect(f.index == 1)
    }

    /// Coming down into a last row that is not full lands on the last item
    /// there is. Refusing is what makes a grid feel broken at the bottom.
    @Test func downIntoARaggedLastRowLandsOnTheLastItem() {
        var f = ragged(at: 4)          // middle of the second row
        let moved7 = f.move(.down)
        #expect(moved7)
        #expect(f.index == 6)          // the only item in the third row
    }

    /// And once on that last row, down does nothing rather than wrapping.
    @Test func theLastRowIsTheEnd() {
        var f = ragged(at: 6)
        let moved8 = f.move(.down)
        #expect(moved8 == false)
        #expect(f.index == 6)
    }

    @Test func theTopRowIsTheTop() {
        var f = ragged(at: 1)
        let moved9 = f.move(.up)
        #expect(moved9 == false)
        #expect(f.index == 1)
    }

    /// A resize moves the columns, not what you were looking at.
    @Test func aResizeKeepsTheSelectedIndex() {
        var f = GridFocus(count: 20, columns: 4, index: 9)
        f.update(count: 20, columns: 6)
        #expect(f.index == 9)
        #expect(f.columns == 6)
    }

    /// A library that shrank under a selection leaves the last item selected,
    /// rather than nothing at all.
    @Test func aShrinkingLibraryClampsRatherThanClears() {
        var f = GridFocus(count: 20, columns: 4, index: 19)
        f.update(count: 5, columns: 4)
        #expect(f.index == 4)
    }

    /// An empty grid is a real state -- a filter that matches nothing -- and
    /// nothing can be selected in it.
    @Test func anEmptyGridSelectsNothing() {
        var f = GridFocus(count: 0, columns: 3, index: nil)
        #expect(f.index == nil)
        let moved10 = f.move(.right)
        #expect(moved10 == false)
        f.selectFirstIfNeeded()
        #expect(f.index == nil)
    }

    /// A controller arriving at a grid with nothing selected picks the first.
    @Test func aFirstPressSelectsSomething() {
        var f = GridFocus(count: 7, columns: 3, index: nil)
        f.selectFirstIfNeeded()
        #expect(f.index == 0)

        var g = GridFocus(count: 7, columns: 3, index: nil)
        let moved11 = g.move(.down)
        #expect(moved11)
        #expect(g.index == 0, "the first press selects rather than moving")
    }

    /// One column is a list, and has to keep working.
    @Test func oneColumnIsAList() {
        var f = GridFocus(count: 3, columns: 1, index: 0)
        let moved12 = f.move(.right)
        #expect(moved12 == false)
        let moved13 = f.move(.down)
        #expect(moved13)
        #expect(f.index == 1)
    }

    /// Nonsense in, something sane out: a zero column count would divide by
    /// zero and a negative index would crash a collection.
    @Test func theShapeIsAlwaysUsable() {
        let f = GridFocus(count: -4, columns: 0, index: -9)
        #expect(f.count == 0)
        #expect(f.columns == 1)
        #expect(f.index == nil)
    }
}

/// How many cards fit across, which is what makes "up" and "down" mean a row.
///
/// Derived from the same constants the grid is built from, so the two cannot
/// disagree -- a second copy of the numbers would drift the first time
/// somebody changed one.
struct GridColumnCountTests {

    @Test func aNarrowWindowIsOneColumn() {
        #expect(gridColumnCount(forWidth: 0) == 1)
        #expect(gridColumnCount(forWidth: cardMinWidth - 1) == 1)
        #expect(gridColumnCount(forWidth: cardMinWidth) == 1)
    }

    @Test func columnsAppearWhenOneMoreCardFits() {
        #expect(gridColumnCount(forWidth: cardMinWidth * 2 + cardSpacing) == 2)
        #expect(gridColumnCount(forWidth: cardMinWidth * 3 + cardSpacing * 2) == 3)
    }

    /// The window's own minimum has to give the grid its constant promises:
    /// this is the narrowest RaccoonBot can be, so it is the case most likely
    /// to be wrong. The inset is the named one the grid actually uses -- an
    /// earlier version of this test assumed 40 where the real figure was 32,
    /// asked for "at least three", and so could not see that the fourth
    /// column the constant promised arrived two points above the floor.
    @Test func theSmallestWindowHasTheFourthColumnItPromises() {
        let grid = windowMinWidth - 2 * gridInset
        #expect(gridColumnCount(forWidth: grid) == 4)
        #expect(gridColumnCount(forWidth: grid - 1) == 3, "the floor is exactly where the column arrives")
    }

    /// Cards grow with the window rather than only multiplying, which is what
    /// keeps the Play button on each one readable.
    @Test func cardsAreAllowedToGrow() {
        #expect(cardMaxWidth > cardMinWidth)
        #expect(cardMaxWidth >= cardMinWidth * 1.4)
    }

    /// Nonsense width cannot produce a zero, which would divide by zero when
    /// the selection moves a row.
    @Test func aNegativeWidthIsStillOneColumn() {
        #expect(gridColumnCount(forWidth: -500) == 1)
    }
}
