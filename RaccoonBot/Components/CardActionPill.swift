//
//  CardActionPill.swift
//  RaccoonBot
//
//  The row of actions under a card in the library grid: one capsule, each
//  action a segment, a thin rule between them.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

/// One segment of the pill. A label only where the action needs a word -- Play,
/// Install -- and a glyph alone everywhere else, with the word in the tooltip.
struct CardAction {
    var label: String? = nil
    var systemImage: String
    var help: String
    var action: () -> Void
}

/// Sized for a card, not for a page header: smaller type and less padding than
/// PlayButtonExtras, which sits beside a large title. Its own width, centred by
/// whoever places it, so a card with three actions and one with five look like
/// the same control.
struct CardActionPill: View {
    let actions: [CardAction]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Divider().padding(.vertical, 5)
                }
                Button(action: item.action) {
                    Group {
                        if let label = item.label {
                            Label(label, systemImage: item.systemImage)
                        } else {
                            Image(systemName: item.systemImage)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .padding(.leading, index == 0 ? 4 : 0)
                    .padding(.trailing, index == actions.count - 1 ? 4 : 0)
                    .contentShape(Rectangle())
                }
                .help(item.help)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(.black)
        .background(.procyonSecondary)
        .clipShape(.capsule)
        .fixedSize()
    }
}

#Preview {
    CardActionPill(actions: [
        CardAction(label: "Play", systemImage: "play.fill", help: "Play", action: {}),
        CardAction(systemImage: "gear", help: "Options", action: {}),
        CardAction(systemImage: "info.circle.fill", help: "Page", action: {}),
    ])
    .padding()
}
