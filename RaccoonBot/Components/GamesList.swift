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
    
    var load: @Sendable () async -> Void
    
    var body: some View {
        Group {
            switch libraryPageGlobals.tab {
            case .installed:
                if libraryPageGlobals.viewMode == .list {
                    LibraryTable(rows: libraryPageGlobals.rows,
                                 actionSymbol: "info.circle",
                                 actionHelp: "Open this title") { row in
                        if let game = libraryPageGlobals.allGames.first(where: { $0.id == row.id }) {
                            libraryPageGlobals.selectedGame = game
                            libraryPageGlobals.showDetailView = true
                        }
                    }
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
            }
        }
        // Read only when the tab is first opened. It walks a 4.7 MB binary
        // cache, and there is no reason to make somebody who never leaves the
        // installed tab pay for it -- off the main thread either way.
        .task(id: libraryPageGlobals.tab) {
            guard libraryPageGlobals.tab == .notInstalled else { return }

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
            ToolbarItemGroup(placement: .automatic) {
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
                            // Glyphs, not names. "Windows" and "macOS" are
                            // different widths, and a bar that resizes as you
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

                    Divider().frame(height: 14)

                    Image(systemName: libraryPageGlobals.filter.isEmpty ? "magnifyingglass" : "xmark.circle")
                        .foregroundStyle(.secondary)
                        .onTapGesture { libraryPageGlobals.filter = "" }
                    TextField("", text: $libraryPageGlobals.filter)
                        .textFieldStyle(.plain)
                        .disableAutocorrection(true)
                        .frame(maxWidth: .infinity)

                    // Answers the same question the field asks, and stays
                    // readable while typing, which a placeholder would not.
                    Text(libraryPageGlobals.tab == .installed
                         ? "\(libraryPageGlobals.filteredGames.count)/\(libraryPageGlobals.allGamesCount)"
                         : "\(libraryPageGlobals.filteredOwnedGames.count)/\(libraryPageGlobals.ownedGames.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        // Fixed, because 58/58 and 334/334 are not the same
                        // width even in monospaced digits.
                        .frame(width: 54, alignment: .trailing)
                        .help("Showing this many of the titles in this tab")

                    Divider().frame(height: 14)

                    Picker("", selection: $libraryPageGlobals.sortBy) {
                        Text("Name").tag(SortingOptions.name)
                        Text("Release Date").tag(SortingOptions.releaseDate)
                        Text("Publisher").tag(SortingOptions.publisher)
                        Text("Developer").tag(SortingOptions.developer)
                        Text("Installed").tag(SortingOptions.installed)
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()

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
                .padding(.horizontal, 10).padding(.vertical, 4)
                // One width, always. Everything variable inside it is pinned --
                // the count, the filter glyphs -- and the search field takes up
                // whatever slack is left, so the bar stops shifting under the
                // pointer as the library is filtered.
                .frame(width: 640)
                .background(.quaternary, in: Capsule())
                .controlSize(.small)
            }
        }
    }
}

