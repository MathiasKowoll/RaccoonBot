//
//  PlatformBadge.swift
//  RaccoonBot
//
//  Which systems a title ships for, as glyphs.
//
//  Spelled out, "Windows" wraps to "Win-dows" inside a capsule that has to fit
//  beside two buttons on a card three to a row. A glyph is one character wide
//  at any card size and reads faster besides.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

enum PlatformBadge {

    /// Only Apple's own mark exists as an SF Symbol; the other two are drawn.
    static func symbol(for platform: String) -> String {
        switch platform.lowercased() {
        case "macos", "mac", "osx": return "apple.logo"
        default: return "questionmark.circle"
        }
    }

    /// Still spelled out for the tooltip and for VoiceOver, which a glyph on
    /// its own would leave with nothing to say.
    static func name(for platform: String) -> String {
        switch platform.lowercased() {
        case "macos", "mac", "osx": return "macOS"
        case "windows", "win": return "Windows"
        case "linux", "steamos": return "Linux"
        default: return platform.capitalized
        }
    }
}

/// The four panes of the Windows mark.
///
/// Drawn rather than named: SF Symbols carries Apple's logo and nobody else's,
/// and "pc" is a beige desktop from 1995 that reads as "computer", not as
/// "Windows".
struct WindowsGlyph: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let gap = side * 0.14
            let pane = (side - gap) / 2
            ZStack(alignment: .topLeading) {
                ForEach(0..<4, id: \.self) { index in
                    Rectangle()
                        .frame(width: pane, height: pane)
                        .offset(x: CGFloat(index % 2) * (pane + gap),
                                y: CGFloat(index / 2) * (pane + gap))
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// One platform, at the size of a caption glyph.
struct PlatformGlyph: View {
    let platform: String

    var body: some View {
        Group {
            switch platform.lowercased() {
            case "windows", "win":
                WindowsGlyph().frame(width: 9, height: 9)
            case "linux", "steamos":
                // The real Tux, shipped as a vector asset. Larry Ewing's terms
                // are attribution, not copyleft -- see CREDITS.md, which is the
                // attribution. The emoji penguin that stood here first is a
                // different bird.
                Image("Tux")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
            default:
                Image(systemName: PlatformBadge.symbol(for: platform))
                    .font(.system(size: 10))
            }
        }
        .frame(width: 18, height: 18)
        .background(.quaternary, in: Circle())
        .help(PlatformBadge.name(for: platform))
        .accessibilityLabel(PlatformBadge.name(for: platform))
    }
}

/// The row of glyphs, used by both the cards and the list.
struct PlatformBadges: View {
    let platforms: Set<String>
    var body: some View {
        HStack(spacing: 4) {
            ForEach(platforms.sorted(), id: \.self) { platform in
                PlatformGlyph(platform: platform)
            }
        }
    }
}
