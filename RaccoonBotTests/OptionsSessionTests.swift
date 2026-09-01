//
//  OptionsSessionTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// What a title's options panel owes the file when it closes.
///
/// The file is the truth the launcher reads; five defects came from a launch
/// using what the form held instead. Closing brings the file up to the form,
/// so the last thing somebody looked at is the thing that runs.
@MainActor
struct OptionsSessionTests {

    /// A session whose writes land in a dictionary rather than in defaults.
    private func make() -> (OptionsSession, () -> [String: GameOptionsData]) {
        var written: [String: GameOptionsData] = [:]
        let box = Box(); box.written = written
        let session = OptionsSession { key, data in box.written[key] = data }
        return (session, { box.written })
    }
    private final class Box { var written: [String: GameOptionsData] = [:] }

    private func form(hud: Bool = true) -> GameOptions {
        let f = GameOptions()
        f.mtlHudEnabled = hud
        return f
    }

    @Test func nothingIsDirtyUntilThePanelHasLoaded() {
        let (s, written) = make()
        let f = form()
        #expect(s.isDirty(f) == false)
        #expect(s.closing(f) == false)
        #expect(written().isEmpty, "a panel that never loaded must not write defaults over a file")
    }

    @Test func aChangeIsMeasuredNotFlagged() {
        let (s, _) = make()
        let f = form(hud: true)
        s.begin(key: "k", form: f)
        #expect(s.isDirty(f) == false)
        f.mtlHudEnabled = false
        #expect(s.isDirty(f) == true)
        f.mtlHudEnabled = true
        #expect(s.isDirty(f) == false, "put back by hand is not dirty either")
    }

    /// The whole point: closing writes, and only when there is something to
    /// write.
    @Test func closingWritesExactlyWhenDirty() {
        let (s, written) = make()
        let f = form(hud: true)
        s.begin(key: "k", form: f)
        #expect(s.closing(f) == false)
        #expect(written().isEmpty)
        f.mtlHudEnabled = false
        #expect(s.closing(f) == true)
        #expect(written()["k"]?.mtlHudEnabled == false)
    }

    /// Reached twice -- onChange and onDisappear both call it -- the second
    /// call finds nothing to do and moves no baseline.
    @Test func closingTwiceWritesOnce() {
        let (s, written) = make()
        let f = form(hud: true)
        s.begin(key: "k", form: f)
        f.mtlHudEnabled = false
        #expect(s.closing(f) == true)
        let after = s.baseline
        #expect(s.closing(f) == false)
        #expect(s.baseline == after)
        #expect(written().count == 1)
    }

    @Test func undoReturnsToTheFile() {
        let (s, _) = make()
        let f = form(hud: true)
        s.begin(key: "k", form: f)
        f.mtlHudEnabled = false
        f.wineMSync.toggle()
        s.undo(into: f)
        #expect(f.mtlHudEnabled == true)
        #expect(s.isDirty(f) == false)
    }

    /// Save moves the baseline, so a later Undo returns to what was saved and
    /// not to what the file held when the panel opened.
    @Test func saveMovesWhatUndoReturnsTo() {
        let (s, written) = make()
        let f = form(hud: true)
        s.begin(key: "k", form: f)
        f.mtlHudEnabled = false
        s.save(f)
        #expect(written()["k"]?.mtlHudEnabled == false)
        let msyncBefore = f.wineMSync
        f.wineMSync.toggle()
        s.undo(into: f)
        #expect(f.mtlHudEnabled == false, "undo went back past the save")
        #expect(f.wineMSync == msyncBefore)
    }

    @Test func endForgetsTheTitle() {
        let (s, written) = make()
        let f = form()
        s.begin(key: "k", form: f)
        s.end()
        f.mtlHudEnabled = false
        #expect(s.closing(f) == false)
        #expect(written().isEmpty)
    }
}

/// The reason the baseline is taken from the form and not the file.
@MainActor
struct OptionsSessionBaselineTests {
    @Test func aPanelThatJustLoadedIsNotDirty() {
        let s = OptionsSession { _, _ in }
        let f = GameOptions()
        // Whatever the fold does to this on the way in, the panel must open
        // clean: nothing has been touched.
        f.set(data: GameOptionsData(data: GameOptions(cxGraphicsBackend: "d3dmetal")))
        s.begin(key: "k", form: f)
        #expect(s.isDirty(f) == false)
        #expect(s.closing(f) == false)
    }
}

/// The property the whole session rests on: loading a form's own data back
/// into it changes nothing the second time. If this ever fails, "dirty" would
/// flicker on a panel nobody touched.
@MainActor
struct OptionsRoundTripTests {
    @Test func loadingIsIdempotent() {
        for backend in ["dxmt", "d3dmetal", "d3dmetal3", "d3dmetal4", "wined3d", "dxvk", "auto", "nonsense"] {
            let f = GameOptions(cxGraphicsBackend: backend)
            f.set(data: GameOptionsData(data: f))
            let once = GameOptionsData(data: f)
            f.set(data: once)
            let twice = GameOptionsData(data: f)
            #expect(once == twice, "a second load changed the form for backend \(backend)")
        }
    }

    /// And a fresh form, never loaded, is canonical after begin.
    @Test func beginLeavesTheFormCanonical() {
        let s = OptionsSession { _, _ in }
        let f = GameOptions(cxGraphicsBackend: "d3dmetal")
        s.begin(key: "k", form: f)
        #expect(s.isDirty(f) == false)
        s.undo(into: f)
        #expect(s.isDirty(f) == false, "undo onto a canonical form is a no-op")
    }
}
