//
//  LibraryTable.swift
//  RaccoonBot
//
//  The list view: four hundred titles are a table, not a wall of pictures.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import Kingfisher

struct LibraryTable: View {
    let games: [OwnedGame]
    let install: (OwnedGame) -> Void
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals

    private static let played: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                        row(game, striped: index.isMultiple(of: 2))
                        Divider().opacity(0.15)
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 52, height: 1)          // the cover column
            ForEach(LibraryColumn.allCases) { column in
                Button {
                    if libraryPageGlobals.sortColumn == column {
                        libraryPageGlobals.sortAscending.toggle()
                    } else {
                        libraryPageGlobals.sortColumn = column
                        libraryPageGlobals.sortAscending = true
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(column.label).font(.caption).fontWeight(.semibold)
                        if libraryPageGlobals.sortColumn == column {
                            Image(systemName: libraryPageGlobals.sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: column == .name ? .leading : .trailing)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: width(of: column) == nil ? .infinity : width(of: column),
                       alignment: column == .name ? .leading : .trailing)
            }
            Color.clear.frame(width: 84, height: 1)          // the action column
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(.secondary)
    }

    private func width(of column: LibraryColumn) -> CGFloat? {
        switch column {
        case .name: return nil                                // takes what is left
        case .platform: return 120
        case .size: return 90
        case .lastPlayed: return 130
        }
    }

    private func row(_ game: OwnedGame, striped: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if let cover = game.coverURL {
                    KFImage(cover).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.black.opacity(0.5))
                }
            }
            .frame(width: 52, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(game.displayName).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(game.platforms.isEmpty ? "—"
                 : game.platforms.sorted().map { $0 == "macos" ? "Mac" : $0.capitalized }.joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)

            // Nothing on disk records the size of something that is not
            // installed, and a guess in a column of facts is worse than a dash.
            Text("—")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            Text(game.lastPlayed.map { Self.played.string(from: $0) } ?? "Never")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)

            Button { install(game) } label: {
                Label("Install", systemImage: "square.and.arrow.down").labelStyle(.iconOnly)
            }
            .controlSize(.small)
            .frame(width: 84, alignment: .trailing)
            .help("Opens Steam's install dialog for this title")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(striped ? Color.white.opacity(0.04) : Color.clear)
    }
}
