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

/// The size of a glyph that stands on its own in the toolbar.
///
/// The ones inside the switcher tracks are 11pt on purpose -- they sit on the
/// same line as 11pt text and belong to it. These do not: they were inheriting
/// whatever the ambient font gave them, which under .controlSize(.small) came
/// out at 12pt inside a 32pt capsule, and left the gear looking like an
/// afterthought beside the 18pt profile icon next to it.
let toolbarGlyphSize: CGFloat = 16

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
    @State private var optionsGame: Game?
    @State private var installChoice: OwnedGame?
    @StateObject private var fixes = MGVFLibrary.shared
    
    var load: @Sendable () async -> Void
    
    /// Open a row's detail page, installed or not.
    ///
    /// A not-installed row has no Game yet -- its record is fetched on demand,
    /// one request for the title actually being opened.
    private func openRow(_ row: LibraryRow) {
        if let game = libraryPageGlobals.allGames.first(where: { $0.id == row.id }) {
            libraryPageGlobals.selectedGame = game
            libraryPageGlobals.showDetailView = true
            return
        }
        guard let owned = libraryPageGlobals.ownedGames.first(where: { $0.appID == row.appID })
        else { return }
        Task {
            guard let info = try? await api.fetchGameInfo(appID: owned.appID) else { return }
            libraryPageGlobals.selectedGame = Game(from: info, id: owned.appID,
                                                   isNative: owned.runsOnMac && !owned.runsOnWindows,
                                                   downloadProgress: 0, isInstalled: false,
                                                   appNames: [])
            libraryPageGlobals.showDetailView = true
        }
    }

    /// Hand the title to Steam's own install dialog, asking first only when the
    /// title genuinely ships for both platforms.
    private func installRow(_ row: LibraryRow) {
        guard let owned = libraryPageGlobals.ownedGames.first(where: { $0.appID == row.appID })
        else { return }
        if owned.isCrossPlatform {
            installChoice = owned
            return
        }
        sendInstall(owned, toMac: owned.runsOnMac && !owned.runsOnWindows)
    }

    private func sendInstall(_ game: OwnedGame, toMac: Bool) {
        installChoice = nil
        if toMac {
            if let url = URL(string: "steam://install/\(game.appID)") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        let steamX86AppPath = appGlobals.windowsSteamFolder?
            .appendingPathComponent("Steam.exe").path(percentEncoded: false)
            ?? "C:\\Program Files (x86)\\Steam\\Steam.exe"
        installGame(id: game.appID, cxAppPath: appGlobals.cxAppPath,
                    selectedBottle: appGlobals.selectedBottle,
                    SteamX86AppPath: steamX86AppPath)
    }

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
            // The list is one view for all three tabs: which rows it holds is a
            // property of the tab, not a reason for a second table. That also
            // makes the filter search one library rather than two.
            if libraryPageGlobals.viewMode == .list {
                LibraryTable(rows: libraryPageGlobals.rows,
                             open: { row in openRow(row) },
                             play: { row in play(row) },
                             options: { row in
                                 optionsGame = libraryPageGlobals.allGames.first { $0.id == row.id }
                             },
                             install: { row in installRow(row) })
            } else {
                switch libraryPageGlobals.tab {
                case .installed:
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(libraryPageGlobals.filteredGames) { item in
                                GameThumbnail(item: item, isResizable: appWindowResizable)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, dockClearance)
                    }
                case .notInstalled:
                    OwnedGamesList()
                case .all:
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
        // Per-title options, through the same sheet the detail page uses.
        .sheet(isPresented: Binding(get: { optionsGame != nil },
                                    set: { if !$0 { optionsGame = nil } })) {
            GameOptionsSheet(game: $optionsGame,
                             isPresented: Binding(get: { optionsGame != nil },
                                                  set: { if !$0 { optionsGame = nil } }))
        }
        // The gate. GameLauncher refuses to start an unpatched title and
        // reports why; without something here to say so, Play on such a title
        // simply does nothing, which reads as broken rather than as protected.
        .alert("This title needs its video fix", isPresented: $warnAboutFix) {
            Button("Open options") { optionsGame = fixWarningGame }
            Button("Cancel", role: .cancel) {}
        } message: {
            let folder = fixWarningGame
                .flatMap { getMeta(libraryPageGlobals.gamesMeta, byID: $0.id) }?
                .gameURL?.path(percentEncoded: false)
            Text(folder.flatMap { fixes.entry(for: $0)?.why }
                 ?? "Its video will not play without it.")
        }
        // Only asked for a title that genuinely ships for both.
        .confirmationDialog("Which version?",
                            isPresented: Binding(get: { installChoice != nil },
                                                 set: { if !$0 { installChoice = nil } }),
                            presenting: installChoice) { game in
            Button("Windows version") { sendInstall(game, toMac: false) }
            Button("macOS version") { sendInstall(game, toMac: true) }
            Button("Cancel", role: .cancel) { installChoice = nil }
        } message: { game in
            Text("\(game.displayName) ships for both. The Windows version runs in the bottle, which is where the video fixes apply; the macOS version is handled by the Steam app on this Mac.")
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
                            .font(.system(size: toolbarGlyphSize))
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
                            .font(.system(size: toolbarGlyphSize))
                    }
                    .buttonStyle(.plain)
                    .help("Stop everything running under Wine")

                    IconSwitcher(selection: $libraryPageGlobals.viewMode,
                                 options: LibraryViewMode.allCases,
                                 symbol: { $0.symbol },
                                 help: { $0 == .grid ? "Grid" : "List" })

                    TabSwitcher(selection: $libraryPageGlobals.tab)

                    Divider().frame(height: 14)

                    // Sized rather than fonted: a borderless Menu draws its label at
                    // the control's own font and ignores the one set on the image, so
                    // these two stayed at 11pt while every other glyph grew.
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
                                      .font(.system(size: toolbarGlyphSize))
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
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(libraryPageGlobals.platformFilter.isEmpty
                          ? "Filter by platform"
                          : "Showing only " + libraryPageGlobals.platformFilter.sorted()
                                .map(PlatformBadge.name(for:)).joined(separator: ", "))

                    Image(systemName: libraryPageGlobals.filter.isEmpty ? "magnifyingglass" : "xmark.circle")
                        .font(.system(size: toolbarGlyphSize))
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
                            .font(.system(size: toolbarGlyphSize))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
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
                            .font(.system(size: toolbarGlyphSize))
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

