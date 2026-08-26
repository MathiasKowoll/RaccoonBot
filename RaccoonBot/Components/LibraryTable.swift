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
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 52, height: 1)
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: width(of: column) == nil ? .infinity : width(of: column),
                       alignment: column == .name ? .leading : .trailing)
            }
            Color.clear.frame(width: 40, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(.secondary)
    }

    private func width(of column: LibraryColumn) -> CGFloat? {
        switch column {
        case .name: return nil
        case .platform: return 130
        case .size: return 90
        case .lastPlayed: return 130
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
            .frame(width: 52, height: 24)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(row.name).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.platforms.isEmpty ? "—"
                 : row.platforms.sorted().map { $0 == "macos" ? "Mac" : $0.capitalized }.joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)

            // A dash rather than a guess: nothing on disk records the size of
            // something that is not installed.
            Text(row.sizeBytes.map { Self.size.string(fromByteCount: $0) } ?? "—")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            Text(row.lastPlayed.map { Self.played.string(from: $0) } ?? "—")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)

            Button { action(row) } label: {
                Image(systemName: actionSymbol)
            }
            .buttonStyle(.plain)
            .frame(width: 40, alignment: .trailing)
            .help(actionHelp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(striped ? Color.white.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { action(row) }
    }
}
