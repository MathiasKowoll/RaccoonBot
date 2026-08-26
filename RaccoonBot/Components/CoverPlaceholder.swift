//
//  CoverPlaceholder.swift
//  RaccoonBot
//
//  What a card shows when there is no cover yet, or no cover at all.
//
//  This used to be `ProgressView()`, which reads as "loading" and therefore
//  promises something. For a title with no art it promised it forever: an empty
//  headerImage makes URL(string:) nil, Kingfisher shows the placeholder, and
//  the spinner turns until the application is closed. A still, dark rectangle
//  says the honest thing -- there is no picture here -- and stops the library
//  from looking like it is permanently busy.
//
//  It keeps the cover's aspect so nothing reflows when a real image replaces
//  it, which is what lets the grid fill in a card at a time.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct CoverPlaceholder: View {
    /// Shown faintly, so a card with no art is still identifiable at a glance.
    var title: String? = nil

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.55))
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 10)
            }
        }
        .aspectRatio(2.15, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
