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

    /// Apple ships no penguin, so Linux borrows the terminal.
    static func symbol(for platform: String) -> String {
        switch platform.lowercased() {
        case "macos", "mac", "osx": return "apple.logo"
        case "windows", "win": return "pc"
        case "linux", "steamos": return "terminal"
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

/// The row of glyphs, used by both the cards and the list.
struct PlatformBadges: View {
    let platforms: Set<String>
    var body: some View {
        HStack(spacing: 4) {
            ForEach(platforms.sorted(), id: \.self) { platform in
                Image(systemName: PlatformBadge.symbol(for: platform))
                    .font(.caption)
                    .frame(width: 18, height: 18)
                    .background(.quaternary, in: Circle())
                    .help(PlatformBadge.name(for: platform))
                    .accessibilityLabel(PlatformBadge.name(for: platform))
            }
        }
    }
}
