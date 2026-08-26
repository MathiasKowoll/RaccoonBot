//
//  LibraryPage.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 29/01/2026.
//

import SwiftUI
import Combine
import Kingfisher

struct LibraryPage: View {
    @StateObject var libraryPageGlobals = LibraryPageGlobals()
    @EnvironmentObject var appGlobals: AppGlobals
    @State private var isLoading = false
    /// One library reload at a time.
    ///
    /// A mount and an unmount both call load(), and Steam libraries commonly
    /// sit on external drives, so two can easily be in flight together --
    /// reconnecting a disk is enough. Both clear gamesMeta and both append to
    /// it, so overlapping them loses titles or duplicates them. Checked and set
    /// on the main actor, which is what makes the check meaningful.
    @State private var isReloading = false
    @State private var errorMessage: String?
    @State private var progress: Double = 0
    @State private var selectedGame: SteamGame? = nil
    @State private var mntObserver: MountObserver?
    @State private var showAddCustomGameView: Bool = false
    
    var body: some View {
        ZStack {
            if(libraryPageGlobals.isLaunchingGame) {
                VStack {
                    ProgressView(label: {
                        Text("Launching \(libraryPageGlobals.selectedGame?.name ?? "'Unknown'")...")
                    })
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .background {
                        if (libraryPageGlobals.selectedGame?.headerImage != nil){
                            KFImage(URL(string: libraryPageGlobals.selectedGame!.headerImage))
                                .placeholder {
                                    ProgressView()
                                }
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 10)
                                .opacity(0.4)
                        }
                    }
                }
                .background(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity).zIndex(10)
            }
            
            VStack {
                if (errorMessage != nil) {
                    Text("Error: \(errorMessage!)")
                        .lineLimit(1)
                        .foregroundStyle(.red)
                } else if (!isLoading && libraryPageGlobals.gamesMeta.isEmpty) {
                    VStack {
                        ContentUnavailableView {
                            Label("No Libraries found", systemImage: "gamecontroller")
                                .padding(.bottom)
                        } description: {
                            Text("No Steam libraries found.\nPlease add a Steam library folder.")
                            Button {
                                libraryPageGlobals.showOptions = true
                            } label: {
                                Label("Add Library", systemImage: "plus")
                            }
                        }
                        .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    GamesList(load: load)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $libraryPageGlobals.showOptions) {
                OptionsView(load: load)
            }
            .sheet(isPresented: $libraryPageGlobals.showTools) {
                ToolsView(load: load)
            }
            .sheet(isPresented: $libraryPageGlobals.showDetailView) {
                Modal(showModal: $libraryPageGlobals.showDetailView, collapse: true, content:  {
                    GameDetailView(game: $libraryPageGlobals.selectedGame)
                })
                // A macOS sheet takes the size of its content, and this content
                // has none of its own -- so a long description grew the sheet
                // past the bottom of the window with no way to reach the rest.
                // Bounded here; the Modal already scrolls inside it.
                // The same width GameDetailView lays out at, so the sheet and
                // its content agree instead of negotiating.
                .frame(width: GameDetailView.contentWidth)
                .frame(minHeight: 460, idealHeight: 720, maxHeight: 860)
            }
            .sheet(isPresented: $showAddCustomGameView) {
                Modal("Custom Game Editor", showModal: $showAddCustomGameView, scrollable: false)  {
                    CustomGameView(isPresented: $showAddCustomGameView)
                }
            }
            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom) {
                    RaccoonBotToolbar(showAddCustomGameView: $showAddCustomGameView)
                    Spacer()
                    if (isLoading) {
                        LoadingProgress(progress: $progress)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .transition(.opacity)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial.opacity(0.5))
                        .overlay(.procyonAccent.mix(with: .black, by: 0.4).opacity(0.5))
                        .mask {
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .black.opacity(0.0), location: 0.0), // top = transparent
                                    .init(color: .black.opacity(0.9), location: 0.5), // fade in
                                    .init(color: .black.opacity(1.0), location: 1.0)              // bottom = solid
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                }
            }
            .onAppear() {
                isLoading = true // fixes missing library issue
                try? FileManager.default.createDirectory(at: PROCYON_SUPPORT_FOLDER_URL.appendingPathComponent(DEFAULT_CXP_BOTTLES_FOLDER), withIntermediateDirectories: true)
                try? stripEnvsInCXBottleConfigFile(selectedBottle: appGlobals.selectedBottle)
                Task(priority: .background) {
                    await load()
                }
                mntObserver = MountObserver(
                    onMount: {
                        Task(priority: .background) {
                            await load()
                        }
                    },
                    onUnmount: {
                        Task(priority: .background) {
                            await load()
                        }
                    }
                )
            }
            .onDisappear {
                mntObserver = nil
            }
            .environmentObject(libraryPageGlobals)
        }
    }
    
    @MainActor
    private func load() async {
        guard !isReloading else {
            console.log("library reload already running; not starting a second")
            return
        }
        isReloading = true
        defer { isReloading = false }
        isLoading = true
        defer {
            Task {
                isLoading = false
            }
        }
        progress = 0
        libraryPageGlobals.gamesMeta.removeAll()
        libraryPageGlobals.folders = getSteamFolderPaths()
        if libraryPageGlobals.folders.isEmpty {
            console.warn("There are no folders to scan.")
        } else {
            for folder in libraryPageGlobals.folders {
                let folderURL = URL(string: folder)!
                if (!libraryPageGlobals.gamesMeta.filter { $0.libraryFolder == folderURL }.isEmpty) {
                    console.log("skipping gamesMeta processing")
                    return // in memory cache just in case you disconnect/reconnect an external drive that has been scanned already
                }
                do {
                    let foldergamesMeta = try getGamesMeta(from: folderURL)
                    libraryPageGlobals.gamesMeta.append(contentsOf: foldergamesMeta)
                } catch {
                    console.error(String(reflecting: error))
                }
            }
        }
        do {
            if(appGlobals.userID != nil) {
                let ownedMeta = try await api
                    .fetchOwnedGamesIDs(userID: appGlobals.userID!)
                    .map{
                        GamesMeta(appid: $0, installdir: "", bytesDownloaded: "0", BytesTodownload: "0")
                    }
                    .filter { owned in
                        !libraryPageGlobals.gamesMeta.contains(where: { $0.appid == owned.appid })
                    }
                libraryPageGlobals.gamesMeta.append(contentsOf: ownedMeta)
            }
        } catch {
            console.error("fetchOwnedGamesIDs \(String(reflecting: error))")
        }
        
        // How long each title has been played, and when last. Read once, from
        // Steam's own per-account config: the store API is a catalogue and has
        // no idea what anybody has played. Off the main thread, and a failure
        // here costs two columns rather than the library.
        libraryPageGlobals.playStats = await Task.detached(priority: .utility) {
            var stats: [String: (lastPlayed: Date?, playtime: Int?)] = [:]
            for steam in OwnedLibrary.steamRoots() {
                for config in OwnedLibrary.localConfigs(inSteamAt: steam) {
                    for (appID, value) in OwnedLibrary.ownedApps(inLocalConfigAt: config)
                    where stats[appID] == nil {
                        stats[appID] = value
                    }
                }
            }
            return stats
        }.value

        // The disk first. Every installed title has a name in its .acf and most
        // have a cover in Steam's own art cache, so the library is complete
        // enough to use before a single request goes out -- and stays that way
        // if every one of them fails. It used to come up empty and silent.
        libraryPageGlobals.games = libraryPageGlobals.gamesMeta.map { Game(local: $0) }
        progress = 100

        // Then the store, if there is one, to fill in what the disk does not
        // have. Merged rather than assigned: a remote answer for forty titles
        // must not delete the seventeen the disk knew about.
        do {
            let enriched = try await api.fetchGamesInfo(
                meta: libraryPageGlobals.gamesMeta,
                setProgress: { self.progress = $0 },
                // Each record replaces its placeholder the moment it lands, so
                // the grid fills in rather than sitting still and then changing
                // all at once a minute later.
                onGame: { game in
                    if let index = libraryPageGlobals.games.firstIndex(where: { $0.id == game.id }) {
                        libraryPageGlobals.games[index] = game
                    } else {
                        libraryPageGlobals.games.append(game)
                    }
                })
            if !enriched.isEmpty {
                // uniquingKeysWith, not uniqueKeysWithValues: the latter traps
                // on a duplicate key. Ids carry the library folder so they
                // cannot collide today, but a crash is a poor way to find out
                // that stopped being true.
                var byID = Dictionary(libraryPageGlobals.games.map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
                for game in enriched { byID[game.id] = game }
                libraryPageGlobals.games = Array(byID.values)
            }
            progress = 100
        } catch {
            console.error("fetchGamesInfo \(String(reflecting: error))")
        }

    }
}

#Preview {
    ContentView()
}

