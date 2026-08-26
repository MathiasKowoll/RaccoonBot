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
                        .padding(.bottom)
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
            ToolbarItemGroup(placement: .primaryAction) {
                HStack {
                    if(!appGlobals.selectedBottle.isEmpty){
                        ProfileWidget()
                        Divider()
                    }
                    Button {
                        libraryPageGlobals.showOptions = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    api.deleteOwnedGamesIDsCache()
                    libraryPageGlobals.gamesMeta.removeAll()
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task {
                        try! await closeWineActivities()
                        libraryPageGlobals.isLaunchingGame = false
                    }
                } label: {
                    Image(systemName: "exclamationmark.octagon")
                }
            }
            // The tabs alone in the centre. Everything else was in here with
            // them and the search field ended up squeezed to nothing -- typing
            // worked, there was simply nowhere for the text to appear.
            ToolbarItem(placement: .principal) {
                Picker("", selection: $libraryPageGlobals.tab) {
                    ForEach(LibraryTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }
            ToolbarItemGroup(placement: .automatic) {
                HStack(spacing: 6) {
                    Image(systemName: libraryPageGlobals.filter.isEmpty ? "magnifyingglass" : "xmark.circle")
                        .foregroundStyle(.secondary)
                        .onTapGesture { libraryPageGlobals.filter = "" }
                    TextField("Search…", text: $libraryPageGlobals.filter)
                        .textFieldStyle(.plain)
                        .disableAutocorrection(true)
                        .frame(minWidth: 120, idealWidth: 160)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
                .controlSize(.small)

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
                } label: {
                    Image(systemName: libraryPageGlobals.platformFilter.isEmpty
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .help("Filter by platform")

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

                Picker("", selection: $libraryPageGlobals.viewMode) {
                    ForEach(LibraryViewMode.allCases) { mode in
                        Image(systemName: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
                .help("Grid or list")

                Text(libraryPageGlobals.tab == .installed
                     ? "\(libraryPageGlobals.filteredGames.count)/\(libraryPageGlobals.allGamesCount)"
                     : "\(libraryPageGlobals.filteredOwnedGames.count)/\(libraryPageGlobals.ownedGames.count)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

