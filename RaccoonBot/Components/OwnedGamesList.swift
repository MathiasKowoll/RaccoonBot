//
//  OwnedGamesList.swift
//  RaccoonBot
//
//  The titles a person owns and has not installed.
//
//  Everything shown here is read from the disk: the ids from localconfig.vdf,
//  the names from appinfo.vdf, the art from Steam's own cache. Nothing on this
//  screen costs a request.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import Kingfisher

/// The states that precede the owned grid, around whatever grid is given.
///
/// The grid itself is GamesList's `cardGrid`, the same one the other two tabs
/// draw, passed in from there. This view drew a grid of its own until
/// 2026-09-04, and that grid was the one place in the library the controller
/// could not reach: no ring, no movement, no press. Sharing the grid is what
/// puts the tab on the pad, and it also ends the second copy of the install
/// and open flows that lived here -- the earlier version of which, before
/// that, had a copy that could not fire at all.
struct OwnedGamesList<Grid: View>: View {
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @ViewBuilder let grid: () -> Grid

    var body: some View {
        Group {
            if !libraryPageGlobals.ownedLoaded {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Reading your library from disk…")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if libraryPageGlobals.allOwnedGames.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing else to install").font(.headline)
                    Text("Every title Steam and Epic know about on this machine is already installed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid()
            }
        }
    }
}

struct OwnedGameCard: View {
    let game: OwnedGame
    let isOpening: Bool
    let install: () -> Void
    let hide: () -> Void
    let open: () -> Void

    private static let played: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    private var subtitle: String {
        var parts: [String] = []
        if let minutes = game.playtimeMinutes, minutes > 0 {
            parts.append(minutes >= 60 ? "\(minutes / 60) h played" : "\(minutes) min played")
        }
        if let date = game.lastPlayed {
            parts.append("last \(Self.played.string(from: date))")
        }
        if parts.isEmpty { parts.append("Never played") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        // Shaped like the installed cards: the art sits flush at the top so the
        // container's corner radius clips it, rather than floating inside a
        // padded box with its own smaller radius.
        VStack(alignment: .leading, spacing: 6) {
            // The box decides the shape; the picture fills it and the rest is
            // cut off.
            //
            // Steam's cache holds portrait grid art -- 600x900 -- as often as a
            // landscape header, and a card that sizes itself to its picture
            // ends up twice as tall as the ones beside it. Asking the IMAGE for
            // an aspect ratio does that; asking a clear box for one, and
            // overlaying the image inside it, does not. The middle band is what
            // survives, which for cover art is where the subject is.
            Color.clear
                .aspectRatio(2.15, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let cover = game.coverURL {
                        KFImage(cover)
                            .placeholder { CoverPlaceholder(title: game.displayName) }
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        CoverPlaceholder(title: game.displayName)
                    }
                }
                .clipped()
            .overlay(alignment: .center) {
                if isOpening {
                    ProgressView().controlSize(.small)
                        .padding(8)
                        .background(.black.opacity(0.55), in: Circle())
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: open)

            // The same two lines as an installed card: the name on the left
            // and the platforms on the right, then the actions, centred. The
            // time played is the name's tooltip: it is what the disk knows about
            // a title that is not installed, and a line of its own made these
            // cards taller than the installed ones beside them. No description
            // or genre: those come from the store, and asking for all of them
            // would be a request each for titles nobody has opened yet.
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Text(game.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                        .help(subtitle)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: open)
                    Spacer(minLength: 8)
                    PlatformBadges(platforms: game.platforms)
                        .fixedSize()
                }
                HStack {
                    Spacer(minLength: 0)
                    CardActionPill(actions: [
                        CardAction(label: "Install", systemImage: "square.and.arrow.down",
                                   help: "Opens the store's install dialog for this title",
                                   action: install),
                        CardAction(systemImage: "info.circle.fill", help: "Open this title's page",
                                   action: open),
                        CardAction(systemImage: "eye.slash",
                                   help: "Hide this title. Steam lists titles the account has no licence for -- free weekends and trials -- and there is no way to tell from disk.",
                                   action: hide),
                    ])
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.procyonAccent.mix(with: .black, by: 0.6).opacity(0.8))
        .cornerRadius(30)
        .foregroundStyle(.white)
    }
}
