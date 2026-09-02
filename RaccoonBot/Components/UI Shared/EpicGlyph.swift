//
//  EpicGlyph.swift
//  RaccoonBot
//
//  A mark for Epic, drawn here rather than borrowed: a rounded badge with a
//  heavy E, the shape people read as the store's without being its logo.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct EpicGlyph: View {
    var size: CGFloat = 20
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(.primary.opacity(0.85))
            Text("E")
                .font(.system(size: size * 0.66, weight: .black, design: .rounded))
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .offset(y: -size * 0.01)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Epic Games")
    }
}
