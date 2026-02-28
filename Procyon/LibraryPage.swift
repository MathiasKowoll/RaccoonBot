//
//  LibraryPage.swift
//  Procyon
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
    @State private var errorMessage: String?
    @State private var progress: Double = 0
    @State private var selectedGame: SteamGame? = nil
    @State private var mntObserver: MountObserver?
    
    var body: some View {
        VStack {
            if(libraryPageGlobals.isLaunchingGame) {
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
                            .blendMode(.softLight)
                    }
                }
            } else if let errorMessage {
                Text("Error: \(errorMessage)")
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
        .sheet(isPresented: $libraryPageGlobals.showDetailView) {
            Modal(showModal: $libraryPageGlobals.showDetailView, collapse: true, content:  {
                GameDetailView(game: $libraryPageGlobals.selectedGame)
            })
        }
        .overlay {
            if (isLoading) {
                HStack(alignment: .bottom) {
                    HStack(alignment: .center) {
                        Image(.procyon).resizable()
                            .scaledToFit()
                            .frame(height: 50)
                        VStack (alignment: .leading){
                            Text("Loading your library…")
                                .font(.footnote)
                                .foregroundStyle(.white)
                            ProgressView(value: progress, total: 100)
                                .progressViewStyle(.linear)
                                .frame(maxWidth: .infinity, maxHeight: 5)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(width: 220, height: 60)
                    .background(.accent.mix(with: .black, by: 0.6).opacity(0.9))
                    .cornerRadius(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding()
                .transition(.opacity)
            }
        }
        .onAppear() {
            isLoading = true // fixes missing library issue
            mntObserver = MountObserver(
                onMount: {
                    Task {
                        await load()
                    }
                },
                onUnmount: {
                    Task {
                        await load()
                    }
                }
            )
        }
        .onDisappear {
            mntObserver = nil
        }
        .task { await load() }
        .environmentObject(libraryPageGlobals)
    }
    
    @MainActor
    private func load() async {
        isLoading = true
        defer {
            Task {
                isLoading = false
            }
        }
        progress = 0
        libraryPageGlobals.gamesMeta.removeAll()
        do {
            libraryPageGlobals.folders = getSteamFolderPaths()
            if libraryPageGlobals.folders.isEmpty {
                console.warn("There are no folders to scan.")
            } else {
                for folder in libraryPageGlobals.folders {
                    let folderURL = URL(string: folder)!
                    if (!libraryPageGlobals.gamesMeta.filter { $0.libraryFolder == folderURL }.isEmpty) {
                        return // in memory cache just in case you disconnect/reconnect an external drive that has been scanned already
                    }
                    do {
                        let foldergamesMeta = try getGamesMeta(from: folderURL)
//                        console.log("found \(foldergamesMeta.count) games in the current folder")
                        libraryPageGlobals.gamesMeta.append(contentsOf: foldergamesMeta)
                    } catch {
                        console.error(error.localizedDescription)
                    }
                }
            }
        }
        do {
            if(appGlobals.userID != nil){
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
            libraryPageGlobals.games = try await api.fetchGamesInfo(meta: libraryPageGlobals.gamesMeta, setProgress: { self.progress = $0 })
            progress = 100
        } catch {
            console.error(error.localizedDescription)
        }
    }
}

#Preview {
    ContentView()
}

