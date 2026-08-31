//
//  GameOptionsSheet.swift
//  RaccoonBot
//
//  One options screen, presented from wherever it is asked for.
//
//  GameOptionsView needs a GameOptions in its environment and force-unwraps the
//  game it is given. GameDetailView happened to provide both, so opening
//  options from the detail page worked and opening it from anywhere else
//  trapped -- EXC_BREAKPOINT in a body getter, which closes the application
//  without a word.
//
//  The setup belongs with the screen rather than with each caller, so there is
//  one place to fix it and every entry point gets the fix.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct GameOptionsSheet: View {
    @Binding var game: Game?
    @Binding var isPresented: Bool

    /// Owned here, so a caller cannot forget to supply it.
    @StateObject private var gameOptions = GameOptions()

    var body: some View {
        Modal("Options for \(game?.name ?? "this title")", showModal: $isPresented) {
            if game != nil {
                GameOptionsView(game: $game)
                    .environmentObject(gameOptions)
                    // Loaded HERE, once per title, rather than in the view's
                    // onAppear.
                    //
                    // GameOptionsView's body is wrapped in a conditional, and
                    // SwiftUI is free to rebuild that branch -- which fires
                    // onAppear again, which read the saved options back over
                    // whatever the user had just changed. The setting looked
                    // like it would not save; it was being reloaded on top of.
                    //
                    // .task(id:) runs when the id changes and not otherwise, so
                    // opening the sheet loads once and nothing reloads while it
                    // is open.
                    .task(id: game?.id) {
                        guard let current = game else { return }
                        // Opening the configuration is the other first time a
                        // title can be met, so it is configured here as well as
                        // at launch. Otherwise the panel would show defaults for
                        // a title that has no file, somebody would change one
                        // field, and everything they did not touch would be
                        // written from whatever the form happened to hold.
                        let key = GameDefaults.key(forAppID: current.steamAppID,
                                                   id: String(current.id))
                        GameDefaults.seedIfAbsent(key: key)
                        if let saved: GameOptionsData = readUsrDefData(key: key) {
                            gameOptions.set(data: saved)
                        }
                        // The fold lives in GameOptions.set(data:) now, so the panel
                        // and the launch cannot disagree about it.
                    }
            } else {
                // Reachable if the game is cleared while the sheet is open.
                // Empty beats trapping.
                Text("No title selected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}
