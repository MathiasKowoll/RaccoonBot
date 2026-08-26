//
//  LibraryTable.swift
//  RaccoonBot
//
//  The list view: four hundred titles are a table, not a wall of pictures.
//
//  Header and rows are laid out from ONE description of the columns. They were
//  built separately -- the same widths typed twice, plus a spacer in the row
//  that the header did not have -- and drifted apart, so every label sat
//  slightly off the data underneath it.
//
//  Per-row actions rather than per-table ones: a row for something installed
//  offers play and options, a row for something that is not offers install, and
//  both live in the same list so a filter searches one library rather than two.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import Kingfisher

/// Sizes that scale with the display.
///
/// A row sized for a 13" laptop is a stripe on a 5K panel. Derived from the
/// main screen's height once, rather than from a magic number.
enum LibraryMetrics {
    static var scale: CGFloat {
        let height = NSScreen.main?.frame.height ?? 900
        // 900 is the old baseline. Clamped at 1.35 rather than 1.6: on a
        // 1329pt display the raw ratio is 1.48, which turned 13pt type into 19
        // and made the table shout.
        return min(max(height / 900, 1.0), 1.35)
    }
    static var rowHeight: CGFloat { (34 * scale).rounded() }
    static var coverWidth: CGFloat { (64 * scale).rounded() }
    static var coverHeight: CGFloat { (30 * scale).rounded() }
    /// Weighted rather than large. The title is the thing being scanned for, so
    /// it carries a little weight instead of extra points -- which keeps it
    /// distinct without making the row shout.
    static var nameSize: CGFloat { (12 * scale).rounded() }
    static var detailSize: CGFloat { (10 * scale).rounded() }
    static var gutter: CGFloat { 24 }
}

struct LibraryTable: View {
    let rows: [LibraryRow]
    /// Open the detail page.
    let open: (LibraryRow) -> Void
    /// Installed only.
    var play: ((LibraryRow) -> Void)? = nil
    var options: ((LibraryRow) -> Void)? = nil
    /// Not installed only.
    var install: ((LibraryRow) -> Void)? = nil

    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .file
        return f
    }()

    /// One description, used by the header and by every row.
    private static let widths: [LibraryColumn: CGFloat] = [
        .name: 320, .installedOn: 76, .supported: 96,
        .size: 92, .played: 70, .lastPlayed: 110,
    ]
    private func width(_ column: LibraryColumn) -> CGFloat {
        (Self.widths[column] ?? 80) * min(LibraryMetrics.scale, 1.25)
    }
    private var actionsWidth: CGFloat { 96 * min(LibraryMetrics.scale, 1.25) }

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
                    // The dock floats over this too, and a row behind it is a
                    // row you cannot click.
                    Color.clear.frame(height: dockClearance)
                }
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: LibraryMetrics.coverWidth, height: 1)
            ForEach(LibraryColumn.allCases) { column in
                if column == .supported {
                    // Mirrors the rule between the two platform columns below;
                    // without it they read as one wide column of glyphs.
                    Divider().frame(height: 12).opacity(0.25)
                }
                sortButton(column)
            }
            Color.clear.frame(width: actionsWidth, height: 1)
        }
        .padding(.horizontal, LibraryMetrics.gutter)
        .padding(.vertical, 8)
        .foregroundStyle(.secondary)
    }

    private func sortButton(_ column: LibraryColumn) -> some View {
        Button {
            if libraryPageGlobals.sortColumn == column {
                libraryPageGlobals.sortAscending.toggle()
            } else {
                libraryPageGlobals.sortColumn = column
                libraryPageGlobals.sortAscending = true
            }
        } label: {
            HStack(spacing: 3) {
                Text(column.label)
                    .font(.system(size: LibraryMetrics.detailSize, weight: .semibold))
                if libraryPageGlobals.sortColumn == column {
                    Image(systemName: libraryPageGlobals.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                }
            }
            .frame(width: width(column),
                   alignment: column == .name ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rows

    private func row(_ row: LibraryRow, striped: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if let cover = row.coverURL {
                    KFImage(cover).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.black.opacity(0.5))
                }
            }
            .frame(width: LibraryMetrics.coverWidth, height: LibraryMetrics.coverHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(row.name)
                .font(.system(size: LibraryMetrics.nameSize, weight: .medium))
                .lineLimit(1).truncationMode(.tail)
                .frame(width: width(.name), alignment: .leading)

            platformCell(row.installedOn.map { [$0] } ?? [], width: width(.installedOn))

            Divider().frame(height: 16).opacity(0.25)

            platformCell(row.platforms, width: width(.supported))

            detail(row.sizeBytes.map { Self.sizeFormatter.string(fromByteCount: $0) } ?? "—",
                   width: width(.size))
            detail(row.playtimeMinutes.map { $0 >= 60 ? "\($0 / 60) h" : "\($0) m" } ?? "—",
                   width: width(.played))
            detail(row.lastPlayed.map { Self.dayFormatter.string(from: $0) } ?? "—",
                   width: width(.lastPlayed))

            actions(row)
        }
        .padding(.horizontal, LibraryMetrics.gutter)
        .frame(height: LibraryMetrics.rowHeight)
        .background(striped ? Color.white.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { open(row) }
    }

    private func platformCell(_ platforms: Set<String>, width: CGFloat) -> some View {
        Group {
            if platforms.isEmpty {
                Text("—").font(.system(size: LibraryMetrics.detailSize)).foregroundStyle(.secondary)
            } else {
                PlatformBadges(platforms: platforms)
            }
        }
        .frame(width: width, alignment: .trailing)
    }

    private func detail(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: LibraryMetrics.detailSize).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .trailing)
    }

    /// What a row offers depends on what the row IS.
    private func actions(_ row: LibraryRow) -> some View {
        HStack(spacing: 10) {
            Button { open(row) } label: { Image(systemName: "info.circle") }
                .buttonStyle(.plain).help("Open this title")

            if row.isInstalled {
                if let options {
                    Button { options(row) } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.plain).help("Options for this title")
                }
                if let play {
                    Button { play(row) } label: { Image(systemName: "play.fill") }
                        .buttonStyle(.plain).help("Play")
                }
            } else if let install {
                Button { install(row) } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(.plain).help("Opens Steam's install dialog for this title")
            }
        }
        .frame(width: actionsWidth, alignment: .trailing)
    }
}
