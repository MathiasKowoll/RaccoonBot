//
//  GameView.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 29/01/2026.
//

import SwiftUI

let columns = [
    GridItem(.adaptive(minimum: 250, maximum: 325), spacing: 10),
]

/// Every capsule in the toolbar is this tall.
///
/// They were sized by their contents, and their contents differ -- a switcher
/// with its own track is taller than a row of glyphs -- so two bars that sit
/// side by side ended up a few points apart, which is the kind of difference
/// that looks like a mistake rather than a choice.
let toolbarCapsuleHeight: CGFloat = 32

/// Room kept clear at the bottom of every scrolling library view.
///
/// The dock floats over the content rather than sitting under it -- a 35pt
/// capsule inside 16pt of padding, so 67 -- and without this the last row's
/// Play button ends up behind it, reachable only by scrolling past the end.
let dockClearance: CGFloat = 80

struct GamesList: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject var appGlobals: AppGlobals
    @State private var showProfile: Bool = false
    @State private var warnAboutFix = false
    @State private var fixWarningGame: Game?
    @StateObject private var fixes = MGVFLibrary.shared
    
    var load: @Sendable () async -> Void
    
    /// Play from the list, through the same launcher the cards use -- fix
    /// gate included, so this cannot start an unpatched title by omission.
    private func play(_ row: LibraryRow) {
        guard let game = libraryPageGlobals.allGames.first(where: { $0.id == row.id }) else { return }
        let folder = getMeta(libraryPageGlobals.gamesMeta, byID: game.id)?
            .gameURL?.path(percentEncoded: false)
        switch GameLauncher.shared.play(game,
                                        updatedItem: game,
                                        isPlaying: libraryPageGlobals.playingID == game.id,
                                        gameFolder: folder,
                                        appGlobals: appGlobals,
                                        libraryPageGlobals: libraryPageGlobals,
                                        fixes: fixes) {
        case .needsFix:
            fixWarningGame = game
            warnAboutFix = true
        case .started, .noExecutable, .alreadyPlaying:
            break
        }
    }

    var body: some View {
        Group {
            switch libraryPageGlobals.tab {
            case .installed:
                if libraryPageGlobals.viewMode == .list {
                    LibraryTable(rows: libraryPageGlobals.rows,
                                 actionSymbol: "info.circle",
                                 actionHelp: "Open this title",
                                 action: { row in
                                     if let game = libraryPageGlobals.allGames.first(where: { $0.id == row.id }) {
                                         libraryPageGlobals.selectedGame = game
                                         libraryPageGlobals.showDetailView = true
                                     }
                                 },
                                 secondarySymbol: "play.fill",
                                 secondaryHelp: "Play",
                                 secondaryAction: { row in play(row) })
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(libraryPageGlobals.filteredGames) { item in
                                GameThumbnail(item: item, isResizable: appWindowResizable)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, dockClearance)
                    }
                }
            case .notInstalled:
                OwnedGamesList()
            case .all:
                if libraryPageGlobals.viewMode == .list {
                    LibraryTable(rows: libraryPageGlobals.rows,
                                 actionSymbol: "info.circle",
                                 actionHelp: "Open this title",
                                 action: { row in
                                     if let game = libraryPageGlobals.allGames.first(where: { $0.id == row.id }) {
                                         libraryPageGlobals.selectedGame = game
                                         libraryPageGlobals.showDetailView = true
                                     }
                                 },
                                 secondarySymbol: "play.fill",
                                 secondaryHelp: "Play",
                                 secondaryAction: { row in play(row) })
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(libraryPageGlobals.filteredGames) { item in
                                GameThumbnail(item: item, isResizable: appWindowResizable)
                            }
                        }
                        .padding(.horizontal)
                        OwnedGamesGrid()
                            .padding(.bottom, dockClearance)
                    }
                }
            }
        }
        .alert("This title needs its video fix", isPresented: $warnAboutFix) {
            Button("Open options") {
                libraryPageGlobals.selectedGame = fixWarningGame
                libraryPageGlobals.showDetailView = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let folder = fixWarningGame
                .flatMap { getMeta(libraryPageGlobals.gamesMeta, byID: $0.id) }?
                .gameURL?.path(percentEncoded: false)
            Text(folder.flatMap { fixes.entry(for: $0)?.why }
                 ?? "Its video will not play without it.")
        }
        // Read only when the tab is first opened. It walks a 4.7 MB binary
        // cache, and there is no reason to make somebody who never leaves the
        // installed tab pay for it -- off the main thread either way.
        .task(id: libraryPageGlobals.tab) {
            guard libraryPageGlobals.tab.needsOwned else { return }

            // The list is read once; the art is resumed every time. Leaving the
            // tab cancels this, and guarding both halves on the same flag would
            // mean anything not fetched before you wandered off stayed missing
            // until the application was restarted.
            if !libraryPageGlobals.ownedLoaded {
                let installed = Set(libraryPageGlobals.gamesMeta.map(\.appid))
                let owned = await Task.detached(priority: .userInitiated) {
                    OwnedLibrary.notInstalled(installed: installed)
                }.value
                libraryPageGlobals.ownedGames = owned
                libraryPageGlobals.ownedLoaded = true
            }

            // The list first, then the art. Nine of ten titles already have a
            // cover on disk; the rest need their url from the store, because
            // Steam's newer art sits behind a content hash that cannot be
            // derived from the app id.
            //
            // One at a time, through fetchGameInfo, which already carries the
            // cache, the permanent blacklist, the two-second pace and the gates
            // that go quiet when Steam refuses or nobody answers. Cancelled
            // when the tab is left: .task tears this down on the id change, so
            // wandering between tabs cannot stack up loops.
            for game in libraryPageGlobals.ownedGames where game.coverURL == nil {
                if Task.isCancelled { return }
                guard let info = try? await api.fetchGameInfo(appID: game.appID),
                      !info.headerImage.isEmpty,
                      let url = URL(string: info.headerImage) else { continue }
                if let index = libraryPageGlobals.ownedGames.firstIndex(where: { $0.appID == game.appID }) {
                    libraryPageGlobals.ownedGames[index].coverURL = url
                }
            }
        }
        .toolbar {
            // Everything in one capsule, in one order.
            //
            // It had grown into four floating pills -- view controls, tabs,
            // search, account -- each with its own background, which is four
            // shapes for one bar. The tabs stay centred on their own because
            // they are navigation, not a control; the rest live here.
            // One pill, everything inside it.
            //
            // Two capsules kept vanishing: macOS collapses a trailing toolbar
            // group into an overflow menu when it decides there is not room,
            // and with the wider tab labels showing there was not -- so the
            // whole right-hand half of the toolbar disappeared depending on
            // which tab you were on. One group cannot be half-collapsed.
            ToolbarItemGroup(placement: .principal) {
                HStack(spacing: 8) {
                    Button {
                        api.deleteOwnedGamesIDsCache()
                        libraryPageGlobals.gamesMeta.removeAll()
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Rescan the library")

                    Button {
                        Task {
                            try! await closeWineActivities()
                            libraryPageGlobals.isLaunchingGame = false
                        }
                    } label: {
                        Image(systemName: "exclamationmark.octagon")
                    }
                    .buttonStyle(.plain)
                    .help("Stop everything running under Wine")

                    IconSwitcher(selection: $libraryPageGlobals.viewMode,
                                 options: LibraryViewMode.allCases,
                                 symbol: { $0.symbol },
                                 help: { $0 == .grid ? "Grid" : "List" })

                    TabSwitcher(selection: $libraryPageGlobals.tab)

                    Divider().frame(height: 14)

                    Menu {
                        ForEach(["windows", "macos", "linux"], id: \.self) { platform in
                            Toggle(PlatformBadge.name(for: platform), isOn: Binding(
                                get: { libraryPageGlobals.platformFilter.contains(platform) },
                                set: { on in
                                    if on { libraryPageGlobals.platformFilter.insert(platform) }
                                    else { libraryPageGlobals.platformFilter.remove(platform) }
                                }))
                        }
                        Divider()
                        Button("All platforms") { libraryPageGlobals.platformFilter.removeAll() }
                        // Hiding with no way back is a trap, and the card's
                        // button is the only place hiding happens.
                        if !libraryPageGlobals.hiddenAppIDs.isEmpty {
                            Divider()
                            Button("Show \(libraryPageGlobals.hiddenAppIDs.count) hidden \(libraryPageGlobals.hiddenAppIDs.count == 1 ? "title" : "titles")") {
                                libraryPageGlobals.unhideAll()
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: (libraryPageGlobals.platformFilter.isEmpty
                                               && libraryPageGlobals.hiddenAppIDs.isEmpty)
                                  ? "line.3.horizontal.decrease.circle"
                                  : "line.3.horizontal.decrease.circle.fill")
                            if !libraryPageGlobals.hiddenAppIDs.isEmpty {
                                Image(systemName: "eye.slash").font(.caption2)
                            }
                            // Glyphs, not names: a bar that resizes as you
                            // filter is a bar that will not hold still.
                            ForEach(libraryPageGlobals.platformFilter.sorted(), id: \.self) { platform in
                                Image(systemName: PlatformBadge.symbol(for: platform))
                                    .font(.caption2)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(libraryPageGlobals.platformFilter.isEmpty
                          ? "Filter by platform"
                          : "Showing only " + libraryPageGlobals.platformFilter.sorted()
                                .map(PlatformBadge.name(for:)).joined(separator: ", "))

                    Image(systemName: libraryPageGlobals.filter.isEmpty ? "magnifyingglass" : "xmark.circle")
                        .foregroundStyle(.secondary)
                        .onTapGesture { libraryPageGlobals.filter = "" }

                    // A darker well than the pill around it, so the part you can
                    // type into reads as a place rather than a gap. Same track,
                    // inset and radius as the switchers.
                    TextField("", text: $libraryPageGlobals.filter)
                        .textFieldStyle(.plain)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 8)
                        .frame(height: toolbarCapsuleHeight - switcherInset * 2)
                        .background(.black.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: switcherSelectionRadius))
                        .frame(minWidth: 90, maxWidth: .infinity)

                    // Answers the same question the field asks, and stays
                    // readable while typing. Fixed, because 58/58 and 334/334
                    // are not the same width even in monospaced digits.
                    Text("\(libraryPageGlobals.rows.count)/\(libraryPageGlobals.tabTotal)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                        .help("Showing this many of the titles in this tab")

                    Menu {
                        Picker("", selection: $libraryPageGlobals.sortBy) {
                            Text("Name").tag(SortingOptions.name)
                            Text("Release Date").tag(SortingOptions.releaseDate)
                            Text("Publisher").tag(SortingOptions.publisher)
                            Text("Developer").tag(SortingOptions.developer)
                            Text("Installed").tag(SortingOptions.installed)
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Sort order")

                    Divider().frame(height: 14)

                    if !appGlobals.selectedBottle.isEmpty {
                        ProfileWidget()
                    }
                    Button {
                        libraryPageGlobals.showOptions = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.plain)
                    .help("Options")
                }
                .padding(.horizontal, 10)
                .frame(height: toolbarCapsuleHeight)
                .background(.quaternary, in: Capsule())
                .controlSize(.small)
            }
        }
    }
}

