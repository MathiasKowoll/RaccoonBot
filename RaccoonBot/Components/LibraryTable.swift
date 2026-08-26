//
//  LibraryTable.swift
//  RaccoonBot
//
//  The list view: four hundred titles are a table, not a wall of pictures.
//
//  Takes LibraryRow rather than a game type, so the same table serves both
//  tabs. It used to take OwnedGame, which is why the list button did nothing
//  at all on the installed tab -- there was no list there to switch to.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import Kingfisher

struct LibraryTable: View {
    let rows: [LibraryRow]
    let actionSymbol: String
    let actionHelp: String
    let action: (LibraryRow) -> Void
    /// Shown after the first, when there is something to play.
    var secondarySymbol: String? = nil
    var secondaryHelp: String = ""
    var secondaryAction: ((LibraryRow) -> Void)? = nil
    var tertiarySymbol: String? = nil
    var tertiaryHelp: String = ""
    var tertiaryAction: ((LibraryRow) -> Void)? = nil

    /// Rows are sized around the cover, which is the thing being read at a
    /// glance. A 24pt strip of a 460x215 header is not enough of it.
    private var actionColumnWidth: CGFloat {
        var width: CGFloat = 40
        if secondaryAction != nil { width += 32 }
        if tertiaryAction != nil { width += 32 }
        return width
    }
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals

    private static let played: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let size: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .file
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        self.row(row, striped: index.isMultiple(of: 2))
                        Divider().opacity(0.15)
                    }
                    // The dock floats over this too, and a row hidden behind it
                    // is a row you cannot click.
                    Color.clear.frame(height: dockClearance)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 64, height: 1)
            ForEach(LibraryColumn.allCases) { column in
                if column == .supported {
                    // Mirrors the rule between the two platform columns below,
                    // which read as one wide column of glyphs without it.
                    Divider().frame(height: 12).opacity(0.25)
                }
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: width(of: column), alignment: column == .name ? .leading : .trailing)
            }
            Color.clear.frame(width: actionColumnWidth, height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .foregroundStyle(.secondary)
    }

    private func width(of column: LibraryColumn) -> CGFloat? {
        switch column {
        // Bounded. A title like "Batman: Arkham Asylum Game of the Year
        // Edition" pushed every other column right and left the row looking
        // like a paragraph with numbers after it.
        case .name: return 320
        case .installedOn: return 76
        case .supported: return 96
        case .size: return 84
        case .played: return 70
        case .lastPlayed: return 108
        }
    }

    private func row(_ row: LibraryRow, striped: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if let cover = row.coverURL {
                    KFImage(cover).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.black.opacity(0.5))
                }
            }
            .frame(width: 64, height: 30)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(row.name).lineLimit(1).truncationMode(.tail)
                .frame(width: 320, alignment: .leading)

            Spacer(minLength: 12)

            // What it is installed AS -- one platform, the one that will run.
            Group {
                if let installed = row.installedOn {
                    PlatformBadges(platforms: [installed])
                } else {
                    Text("—").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 76, alignment: .trailing)

            Divider().frame(height: 16).opacity(0.25)

            // What it is available FOR, which is a different question: a title
            // can ship for three systems and be installed as one.
            Group {
                if row.platforms.isEmpty {
                    Text("—").font(.caption).foregroundStyle(.secondary)
                } else {
                    PlatformBadges(platforms: row.platforms)
                }
            }
            .frame(width: 96, alignment: .trailing)

            // A dash rather than a guess: nothing on disk records the size of
            // something that is not installed.
            Text(row.sizeBytes.map { Self.size.string(fromByteCount: $0) } ?? "—")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 84, alignment: .trailing)

            // Two columns, because either can be the one worth sorting by and
            // one column can only sort by one of them.
            Text(row.playtimeMinutes.map { $0 >= 60 ? "\($0 / 60) h" : "\($0) m" } ?? "—")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            Text(row.lastPlayed.map { Self.played.string(from: $0) } ?? "—")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 108, alignment: .trailing)

            HStack(spacing: 10) {
                Button { action(row) } label: {
                    Image(systemName: actionSymbol)
                }
                .buttonStyle(.plain)
                .help(actionHelp)

                if let tertiarySymbol, let tertiaryAction {
                    Button { tertiaryAction(row) } label: {
                        Image(systemName: tertiarySymbol)
                    }
                    .buttonStyle(.plain)
                    .help(tertiaryHelp)
                }

                if let secondarySymbol, let secondaryAction {
                    Button { secondaryAction(row) } label: {
                        Image(systemName: secondarySymbol)
                    }
                    .buttonStyle(.plain)
                    .help(secondaryHelp)
                }
            }
            .frame(width: actionColumnWidth, alignment: .trailing)
        }
        // Wider gutters than the rows need, so the table has margins rather
        // than running into the window.
        .padding(.horizontal, 24)
        .padding(.vertical, 5)
        .background(striped ? Color.white.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        // The row opens; only the button plays. A whole row that launches a
        // game is a row you cannot click to look at one.
        .onTapGesture { action(row) }
    }
}
