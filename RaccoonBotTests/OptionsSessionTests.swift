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

    @Test func undoReturnsToWhatThePanelOpenedWith() {
        let (s, _) = make()
        let f = form(hud: true)
        s.begin(key: "k", form: f)
        f.mtlHudEnabled = false
        f.wineMSync.toggle()
        s.undo(into: f)
        #expect(f.mtlHudEnabled == true)
        #expect(s.isDirty(f) == false)
        #expect(s.canUndo(f) == false, "there is nothing left to undo")
    }

    /// A write does NOT move what Undo returns to, and this is the whole
    /// reason `opened` exists.
    ///
    /// It used to: Undo meant "put the form back to the file", and Save moved
    /// the file. With the panel writing by itself a moment after every edit,
    /// that Undo could never do anything -- the file is always what the form
    /// says. So Undo goes back to what the file held when the panel opened,
    /// which is the state somebody reaches for when they want out of a visit.
    @Test func aWriteDoesNotMoveWhatUndoReturnsTo() {
        let (s, written) = make()
        let f = form(hud: true)
        s.begin(key: "k", form: f)
        f.mtlHudEnabled = false
        s.save(f)
        #expect(written()["k"]?.mtlHudEnabled == false)
        #expect(s.isDirty(f) == false, "the file is what the form says")
        #expect(s.canUndo(f) == true, "and there is still a visit to undo")
        f.wineMSync.toggle()
        s.undo(into: f)
        #expect(f.mtlHudEnabled == true, "back to what the panel opened with")
        #expect(s.isDirty(f) == true, "which the file does not hold yet -- autosave writes it next")
    }

    // MARK: - saving as it is edited

    /// The rule, on its own: something to write to, and something to write.
    @Test func theAutosaveRuleIsTwoConditions() {
        #expect(Autosave.shouldWrite(hasFile: true, formDiffers: true))
        #expect(!Autosave.shouldWrite(hasFile: true, formDiffers: false), "nothing changed")
        #expect(!Autosave.shouldWrite(hasFile: false, formDiffers: true),
                "a panel that never loaded a title has no file to write over")
        #expect(Autosave.quietPeriod > .zero, "a pause, so one drag is one write")
    }

    /// An edit is committed without anybody pressing anything, and an edit
    /// put back by hand during the pause commits nothing at all.
    @Test func anEditIsWrittenWithoutBeingAskedTo() {
        let (s, written) = make()
        let f = form(hud: true)
        s.begin(key: "k", form: f)
        #expect(s.autosave(f) == false, "nothing to write")
        #expect(written().isEmpty)
        f.mtlHudEnabled = false
        #expect(s.autosave(f) == true)
        #expect(written()["k"]?.mtlHudEnabled == false)
        #expect(s.isDirty(f) == false)
        f.mtlHudEnabled = true
        f.mtlHudEnabled = false
        #expect(s.autosave(f) == false, "back where it was is not an edit")
        #expect(written().count == 1)
    }

    /// And the guard the whole session rests on holds for this door too: a
    /// panel that never loaded a title writes nothing.
    @Test func autosaveNeverWritesDefaultsOverAFile() {
        let (s, written) = make()
        let f = form()
        f.mtlHudEnabled = false
        #expect(s.autosave(f) == false)
        #expect(written().isEmpty)
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
