//
//  GridFocus.swift
//  RaccoonBot
//
//  Where the selection is in a grid, and where a direction takes it.
//
//  Kept apart from the view and from the controller on purpose. SwiftUI on
//  macOS has no focus engine that walks a LazyVGrid in two dimensions -- that
//  is tvOS -- so this application has to own the answer, and owning it in a
//  view means it can only be checked by looking at a window with a controller
//  in hand. Here it is arithmetic, and the awkward cases are the ones a test
//  can state: a last row that is not full, a window resize that changes the
//  column count under a selection, a library that shrinks while something is
//  selected.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated struct GridFocus: Equatable {

    enum Direction { case up, down, left, right }

    /// How many items the grid is showing. Zero is a real state: a filter that
    /// matches nothing still has to be navigable back out of.
    private(set) var count: Int

    /// How many fit across. Never below one, whatever the window does.
    private(set) var columns: Int

    /// The selected item, or nil when there is nothing to select.
    private(set) var index: Int?

    init(count: Int = 0, columns: Int = 1, index: Int? = nil) {
        self.count = max(0, count)
        self.columns = max(1, columns)
        self.index = Self.clamp(index, to: self.count)
    }

    private static func clamp(_ index: Int?, to count: Int) -> Int? {
        guard count > 0, let index else { return nil }
        return min(max(0, index), count - 1)
    }

    /// The grid changed shape or contents.
    ///
    /// The selection is kept by INDEX rather than dropped, because a resize
    /// that moved the columns should not also move what you were looking at.
    /// It is clamped instead: a library that shrank under a selection leaves
    /// the last item selected rather than nothing.
    mutating func update(count: Int, columns: Int) {
        self.count = max(0, count)
        self.columns = max(1, columns)
        self.index = Self.clamp(self.index, to: self.count)
    }

    /// Select the first thing, if there is one. Called when a controller
    /// arrives and nothing is selected yet.
    mutating func selectFirstIfNeeded() {
        if index == nil, count > 0 { index = 0 }
    }

    mutating func clear() { index = nil }

    /// Move, and answer whether anything moved.
    ///
    /// False is the useful half: a press at the edge that changes nothing is
    /// what a caller needs to know in order to hand the press somewhere else
    /// -- to a row of filters above the grid, later on.
    @discardableResult
    mutating func move(_ direction: Direction) -> Bool {
        guard count > 0 else { return false }
        guard let current = index else { index = 0; return true }
        let next: Int
        switch direction {
        case .left:
            // Stops at the start of the row rather than wrapping to the end of
            // the row above. Wrapping reads as a jump when you cannot see the
            // whole grid, and this grid scrolls.
            next = (current % columns == 0) ? current : current - 1
        case .right:
            next = (current % columns == columns - 1) ? current : min(current + 1, count - 1)
        case .up:
            next = current - columns
        case .down:
            // A last row that is not full: coming down from a column that has
            // no item lands on the last one there is, rather than refusing.
            // Refusing is what makes a grid feel broken at the bottom.
            next = current + columns < count ? current + columns
                 : (current / columns == (count - 1) / columns ? current : count - 1)
        }
        guard next >= 0, next < count, next != current else { return false }
        index = next
        return true
    }
}
