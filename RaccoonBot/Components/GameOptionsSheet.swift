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
