//
//  OptionsSession.swift
//  RaccoonBot
//
//  What a title's options panel owes the file, as it is edited and when it
//  closes.
//
//  The panel edits a form; the launcher reads a file. Five separate defects
//  came from those two disagreeing -- a launch that used what the form held
//  rather than what was saved -- and the rule that closed them is that the
//  file is the truth. This is the other half of that rule: when the panel
//  closes, the file becomes what the panel showed. Nothing is left in a state
//  where the last thing somebody looked at is not the thing that runs.
//
//  So there is no "save changes?" on the way out. With a controller that would
//  be a dialog to navigate every single time, and its Discard button would put
//  the form and the file back into disagreement -- the exact state the rule
//  exists to prevent.
//
//  AND THE PANEL NO LONGER WAITS UNTIL IT CLOSES. The same rule says that an
//  option changed and not saved is an option that silently does not apply, and
//  a Save button is a step that can be forgotten -- it was forgotten in this
//  project's own measuring, which is what `Autosave` below exists for. An edit
//  is committed a moment after it is made.
//
//  Which changes what Undo can mean. When the file follows the form, "put the
//  form back to the file" is a button that can never do anything, so Undo goes
//  back to what the file held when the panel OPENED and stays the escape
//  hatch it was. That is a second remembered state, `opened`, which nothing
//  moves while a title's panel is up; `baseline` still means "what is in the
//  file right now", because that is what "is there anything to write" is
//  measured against.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Combine

@MainActor
final class OptionsSession: ObservableObject {

    /// What is in the file right now: what it held when the panel opened, or
    /// what the last write put there. "Dirty" is measured against it.
    @Published private(set) var baseline: GameOptionsData?

    /// What the file held when the panel opened, which no write moves. Undo
    /// goes here, so it can still undo a title's whole visit even though
    /// autosave has been writing all along.
    @Published private(set) var opened: GameOptionsData?

    /// Where the file lives.
    private(set) var key: String?

    /// Writes, injectable so the session can be exercised without touching
    /// the real defaults.
    private let persist: (String, GameOptionsData) -> Void

    init(persist: @escaping (String, GameOptionsData) -> Void = { persistUsrDefData(key: $0, data: $1) }) {
        self.persist = persist
    }

    /// The panel opened on a title. Called once per title, AFTER the file has
    /// been loaded into the form -- and measured from the form, not from the
    /// file.
    ///
    /// Loading is not a copy: `GameOptions.set(data:)` folds the backend into
    /// the one the panel can pick, so a file holding a value the fold changes
    /// would differ from the form the moment it appeared. Measured from the
    /// file, such a panel opens dirty and Undo can never make it clean. The
    /// form after loading is what the person sees, and it is what closing
    /// compares against; the launcher applies the same fold when it reads, so
    /// leaving the file as it was is not a disagreement.
    func begin(key: String, form: GameOptions) {
        self.key = key
        // Canonical by construction, not by the caller remembering to load
        // through set(data:) first. A form built any other way -- defaults,
        // a test, a future caller -- is put through the same fold here, so
        // that "baseline equals the form as it will be compared" holds
        // whatever produced the form. The fold is idempotent, which a test
        // states outright because everything here rests on it.
        form.set(data: GameOptionsData(data: form))
        self.baseline = GameOptionsData(data: form)
        // The same value, remembered separately because they stop being the
        // same the first time autosave writes.
        self.opened = self.baseline
    }

    func end() {
        key = nil
        baseline = nil
        opened = nil
    }

    /// Does the form differ from the file?
    ///
    /// Compared, never tracked: a flag set on every control is a flag one
    /// control forgets to set. Before `begin` nothing is known, and "not
    /// known" is reported as "not dirty" so a panel that never loaded cannot
    /// write defaults over a file on its way out.
    func isDirty(_ form: GameOptions) -> Bool {
        guard let baseline else { return false }
        return GameOptionsData(data: form) != baseline
    }

    /// Commit now. The baseline moves, so nothing is dirty afterwards and the
    /// next edit is measured against what is now in the file. What Undo
    /// returns to does not move -- see `opened`.
    func save(_ form: GameOptions) {
        guard let key else { return }
        let data = GameOptionsData(data: form)
        persist(key, data)
        baseline = data
    }

    /// Is there anything for Undo to do? Measured against what the panel
    /// opened with, which is the only thing it can still return to.
    func canUndo(_ form: GameOptions) -> Bool {
        guard let opened else { return false }
        return GameOptionsData(data: form) != opened
    }

    /// Put the form back to what the file held when the panel opened.
    ///
    /// It does not write. It does not have to: the form changing is what
    /// autosave watches, so the undone form is committed a moment later by
    /// the same path every other edit takes.
    func undo(into form: GameOptions) {
        guard let opened else { return }
        form.set(data: opened)
    }

    /// Commit an edit, if there is one to commit. The rule is `Autosave`'s;
    /// this is the doing of it, and it answers whether it wrote so that a test
    /// -- and the panel -- can tell an edit from a no-op.
    @discardableResult
    func autosave(_ form: GameOptions) -> Bool {
        guard Autosave.shouldWrite(hasFile: key != nil, formDiffers: isDirty(form)) else { return false }
        save(form)
        return true
    }

    /// The panel is closing, by whatever route: the close button, Escape, a
    /// controller's B. One place, so no route can forget.
    ///
    /// Answers whether it wrote, which is what a caller that wants to say
    /// "saved" needs to know.
    @discardableResult
    func closing(_ form: GameOptions) -> Bool {
        guard isDirty(form) else { return false }
        save(form)
        return true
    }
}

/// When an edit becomes a write.
///
/// Out of the view and out of the session both, so the rule can be stated in
/// a test rather than lived inside a closure: the panel only owns the timer.
///
/// WHY THERE IS A PAUSE AT ALL. A slider dragged across its range publishes a
/// new value every frame, and writing the defaults file sixty times a second
/// to describe one gesture is a write per frame for one decision. The pause
/// coalesces a gesture into the write that ends it: every edit cancels the
/// pending one and starts it again, so the file is written once the hand
/// stops. It is short enough that it is over before anybody could close the
/// panel deliberately, and closing writes anyway -- `closing(_:)` is still
/// there, and is what catches an edit made in the last fraction of a second.
nonisolated enum Autosave {

    /// How long after the last edit the write happens. A quarter of a second
    /// reads as immediate and still swallows a drag.
    static let quietPeriod: Duration = .milliseconds(250)

    /// Whether an edit is worth a write.
    ///
    /// Two conditions and no more. There has to be a file to write to -- a
    /// panel that never loaded a title must not write its defaults over one,
    /// which is `isDirty`'s own rule said once more where it can be seen --
    /// and the form has to differ from what is in it, so that a rebuild, a
    /// reload or an edit put back by hand writes nothing.
    static func shouldWrite(hasFile: Bool, formDiffers: Bool) -> Bool {
        hasFile && formDiffers
    }
}
