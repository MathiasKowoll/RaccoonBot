//
//  OptionFocusRing.swift
//  RaccoonBot
//
//  The mark a controller leaves on the control it is on.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

private struct OptionFocusRing: ViewModifier {
    let control: OptionControl
    let current: OptionControl?
    let shown: Bool

    private var on: Bool { shown && current == control }

    func body(content: Content) -> some View {
        content
            .id(control)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(on ? 0.10 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white, lineWidth: 2)
                    .opacity(on ? 1 : 0)
            )
            .padding(.horizontal, -6)
            .padding(.vertical, -3)
            .animation(.easeOut(duration: 0.1), value: on)
    }
}

extension View {
    /// Mark this control as reachable by a controller, and light it when the
    /// controller is on it. Drawn only while a pad is connected, so the
    /// mouse-driven panel is unchanged for everybody else. The padding in and
    /// back out keeps the ring clear of the control without moving it.
    func optionFocus(_ control: OptionControl, current: OptionControl?, shown: Bool) -> some View {
        modifier(OptionFocusRing(control: control, current: current, shown: shown))
    }
}

/// The same selection ring GameThumbnail draws on itself, offered to a card
/// that has no ring of its own -- so a pad selection looks identical whether
/// it lands on an installed card or an owned one in the same mixed grid.
extension View {
    func gridSelectionRing(_ isSelected: Bool) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .strokeBorder(.white, lineWidth: 3)
                    .opacity(isSelected ? 1 : 0)
            )
            .scaleEffect(isSelected ? 1.04 : 1)
            .shadow(color: .black.opacity(isSelected ? 0.45 : 0), radius: 14, y: 6)
            .zIndex(isSelected ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}
