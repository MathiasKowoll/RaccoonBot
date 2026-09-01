//
//  OptionsSession.swift
//  RaccoonBot
//
//  What a title's options panel owes the file when it closes.
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
//  exists to prevent. Undo, before closing, is the escape hatch: it puts the
//  form back to the file, which is a state that cannot be wrong.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Combine

@MainActor
final class OptionsSession: ObservableObject {

    /// What the file held when the panel opened, or the last time it saved.
    /// Undo goes here; "dirty" is measured against it.
    @Published private(set) var baseline: GameOptionsData?

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
    }

    func end() {
        key = nil
        baseline = nil
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

    /// Commit now. The baseline moves, so a later Undo returns to this and
    /// not to whatever was there before the person pressed Save.
    func save(_ form: GameOptions) {
        guard let key else { return }
        let data = GameOptionsData(data: form)
        persist(key, data)
        baseline = data
    }

    /// Put the form back to the file.
    func undo(into form: GameOptions) {
        guard let baseline else { return }
        form.set(data: baseline)
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
