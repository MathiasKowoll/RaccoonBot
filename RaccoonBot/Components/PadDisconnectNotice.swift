//
//  PadDisconnectNotice.swift
//  RaccoonBot
//
//  The alert for GameLauncher's .padWillDisconnect, written once.
//
//  Three places start a game -- the card, the list and the detail page -- and
//  a notice copied into each is three wordings free to drift. The words live
//  in MacIdleDisconnect; this is only the alert around them.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

extension View {
    /// Shown while `pads` is non-nil. `start` launches again with the notice
    /// acknowledged; the second button also turns the notice off for good,
    /// until Tools brings it back.
    ///
    /// No button starts the game from a pad: the view that listens to the pad
    /// answers only Back while this is up, as it does for the fix alert. A
    /// notice whose whole point is to be read should not be dismissed into a
    /// launch by the same press that opened it.
    func padDisconnectNotice(_ pads: Binding<[SonyPads.Pad]?>, start: @escaping () -> Void) -> some View {
        modifier(PadDisconnectNotice(pads: pads, start: start))
    }
}

private struct PadDisconnectNotice: ViewModifier {
    @Binding var pads: [SonyPads.Pad]?
    let start: () -> Void
    /// The last pads shown. Dismissing sets `pads` to nil before the alert has
    /// finished going, and a title read from nil would name "your controllers"
    /// on its way out.
    @State private var shown: [SonyPads.Pad] = []

    func body(content: Content) -> some View {
        let message = MacIdleDisconnect.message(for: pads ?? shown)
        return content
            .alert(message.title,
                   isPresented: Binding(get: { pads != nil },
                                        set: { if !$0 { pads = nil } })) {
                Button("Start") { start() }
                    .keyboardShortcut(.defaultAction)
                Button("Start, and don't show this again") {
                    UserDefaults.standard.set(true, forKey: MacIdleDisconnect.suppressionKey)
                    start()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(message.body)
            }
            .onChange(of: pads) { _, new in if let new { shown = new } }
    }
}
