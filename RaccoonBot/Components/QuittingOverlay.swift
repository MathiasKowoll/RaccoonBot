//
//  QuittingOverlay.swift
//  RaccoonBot
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import Combine

/// What the window says while a quit closes a bottle first. Set by the
/// application delegate, which has no view of its own to put it in; nil when
/// nothing is being closed.
@MainActor
final class QuitProgress: ObservableObject {
    static let shared = QuitProgress()
    @Published var message: String?
}

/// The window, locked while a quit closes a bottle, the way it is locked while
/// a game starts. Without it the window sat there looking finished while Steam
/// was still saving and signing out, and a quit that is doing its job read as
/// one that did nothing.
struct QuittingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(.raccoonBot).resizable()
                .scaledToFit()
                .frame(height: 72)
            ProgressView()
                .progressViewStyle(.circular)
            Text(message)
                .font(.headline)
                .foregroundStyle(.white)
            Text("Letting the game and the store save and sign out. RaccoonBot quits when they are done.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.92))
        .ignoresSafeArea()
        // Every click and scroll stops here: nothing under it is for now.
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}

#Preview {
    QuittingOverlay(message: "Closing Steam before quitting…")
}
