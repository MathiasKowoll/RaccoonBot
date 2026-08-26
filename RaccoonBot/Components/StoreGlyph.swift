//
//  StoreGlyph.swift
//  RaccoonBot
//
//  A store's mark, where one exists.
//
//  Same rule as the platform badges: ship what is ours to ship. Steam's mark is
//  already in the asset catalogue; Epic's is a trademark, so Epic gets a neutral
//  glyph rather than a logo this repository has no licence to carry.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct StoreGlyph: View {
    let store: Store
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let asset = store.assetName {
                Image(asset).resizable().scaledToFit()
            } else {
                Image(systemName: store.systemSymbol).resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .help(store.label)
        .accessibilityLabel(store.label)
    }
}
