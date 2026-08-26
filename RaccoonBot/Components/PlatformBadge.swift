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
/// and Microsoft does not licence theirs for this. Plain geometry, written
/// here.
///
/// Built from fixed frames rather than a GeometryReader. That reader expands to
/// fill whatever it is given and lays its content out from the top left, so the
/// mark sat off-centre in its circle. Stacks of a known size centre themselves.
struct WindowsGlyph: View {
    var side: CGFloat

    var body: some View {
        let gap = (side * 0.16).rounded()
        let pane = ((side - gap) / 2).rounded()
        VStack(spacing: gap) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: gap) {
                    ForEach(0..<2, id: \.self) { _ in
                        Rectangle().frame(width: pane, height: pane)
                    }
                }
            }
        }
        .frame(width: pane * 2 + gap, height: pane * 2 + gap)
    }
}

/// One platform, at the size of a caption glyph.
struct PlatformGlyph: View {
    let platform: String

    var body: some View {
        Group {
            switch platform.lowercased() {
            case "windows", "win":
                WindowsGlyph(side: 15)
            case "linux", "steamos":
                // The real Tux, shipped as a vector asset. Larry Ewing's terms
                // are attribution, not copyleft -- see CREDITS.md, which is the
                // attribution. The emoji penguin that stood here first is a
                // different bird.
                Image("Tux")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            default:
                Image(systemName: PlatformBadge.symbol(for: platform))
                    .font(.system(size: 16))
            }
        }
        .frame(width: 28, height: 28)
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
