//
//  EpicGlyph.swift
//  RaccoonBot
//
//  Epic's mark, drawn: the shield with its pointed foot, EPIC across it, the
//  bar and the chevron beneath. Vector, so it is crisp at 20 points in the
//  toolbar and at any size in a panel, and it takes the current foreground
//  colour like an SF Symbol would.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct EpicGlyph: View {
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            EpicShield()
                .fill(.primary.opacity(0.9))
            VStack(spacing: size * 0.06) {
                Text("EPIC")
                    .font(.system(size: size * 0.34, weight: .black, design: .default))
                    .kerning(-size * 0.01)
                    .scaleEffect(x: 0.88, y: 1.35)
                    .padding(.top, size * 0.16)
                Rectangle()
                    .frame(width: size * 0.56, height: size * 0.075)
                Image(systemName: "chevron.down")
                    .font(.system(size: size * 0.16, weight: .black))
                    .padding(.top, -size * 0.02)
            }
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .offset(y: -size * 0.03)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Epic Games")
    }
}

/// A rectangle whose bottom comes to a point, with slightly rounded corners.
struct EpicShield: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let inset = w * 0.06                     // the mark is a touch narrower than tall
        let left = r.minX + inset, right = r.maxX - inset
        let foot = r.maxY                        // the tip
        let shoulder = r.minY + h * 0.78         // where the sides turn in
        var p = Path()
        p.move(to: CGPoint(x: left, y: r.minY))
        p.addLine(to: CGPoint(x: right, y: r.minY))
        p.addLine(to: CGPoint(x: right, y: shoulder))
        p.addLine(to: CGPoint(x: r.midX, y: foot))
        p.addLine(to: CGPoint(x: left, y: shoulder))
        p.closeSubpath()
        return p
    }
}
