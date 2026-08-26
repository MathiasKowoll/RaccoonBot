//
//  GameThumbnail.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 30/01/2026.
//

import SwiftUI
import Kingfisher

struct GameThumbnail: View {
    var item: Game
    var isResizable: Bool = false
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @State private var tObserver: TerminationObserver?
    @StateObject private var fixes = MGVFLibrary.shared
    @State private var warnAboutFix = false

    /// Where this title is installed, from its metadata.
    private var gameFolder: String? {
        getMeta(libraryPageGlobals.gamesMeta, byID: item.id)?.gameURL?.path(percentEncoded: false)
    }
    var isPlaying: Bool {
        libraryPageGlobals.playingID == item.id
    }
    var isDownloading: Bool {
        item.downloadProgress < 100
    }
    var updatedItem: Game {
        var newItem = item
        if let meta = libraryPageGlobals.gamesMeta.first(where: { $0.id == item.id }){
            
            newItem.appNames = getAppNames(isNative: meta.isNative, gameURL: meta.gameURL)
            return newItem
        }
        return newItem
    }
    
    var body: some View {
        Button(action: {
            openDetailPage()
        }) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing){
                    if fixes.needsPatch(folder: gameFolder) {
                        // Marked here because this is where a library is looked
                        // at. Everything else about the fix lives inside the
                        // game's options, which nobody opens for a title they
                        // have no reason to suspect.
                        Image(systemName: "wand.and.sparkles")
                            .font(.caption)
                            .padding(4)
                            .background(.orange.opacity(0.85), in: Circle())
                            .foregroundStyle(.white)
                            .padding(6)
                            .zIndex(1)
                            .help("This title needs its video fix")
                    }
                    // No url means there is nothing to wait for, so do not ask
                    // Kingfisher to wait for it. That distinction is the whole
                    // difference between a card that is loading and a card that
                    // never will.
                    if let cover = URL(string: item.headerImage), !item.headerImage.isEmpty {
                        KFImage(cover)
                            .placeholder { CoverPlaceholder(title: item.name) }
                            .resizable()
                            .aspectRatio(2.15, contentMode: .fit)
                            .frame(maxWidth:.infinity, maxHeight: .infinity, alignment: .top)
                    } else {
                        CoverPlaceholder(title: item.name)
                    }
                        
                    HStack(alignment: .top) {
                        if (item.isNative == true) {
                            OIcon("apple.logo").padding(.vertical, 8)            // icon size
                        }
                        if (item.isCustom == true) {
                            Button {
                                libraryPageGlobals.deleteCustomAddedGame(game: item)
                            } label: {
                                OIcon("trash").padding(.vertical, 8)
                            }
                            .task { await fixes.loadIfNeeded() }
                            .alert("This title needs its video fix", isPresented: $warnAboutFix) {
                                Button("Open options") { openDetailPage() }
                                Button("Play anyway", role: .destructive) { warnAboutFix = false }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text(fixes.entry(for: gameFolder)?.why ?? "Its video will not play without it.")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                VStack (alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(1)
                    HStack (spacing: 6){
                        AccentTag(item.type)
                        if (item.genres != nil && item.genres!.count > 0){
                            AccentTag(item.genres!.first!.description)
                        }
                        if (item.isInstalled) {
                            if (item.isNative == true) {
                                AccentTag("Mac")
                            } else {
                                AccentTag("Pc")
                            }
                        }
                        Spacer()
                        
                        if(!isDownloading && item.isInstalled) {
                            Button {
                                if (isPlaying) {
                                    if(item.isNative) {
                                        console.log("stop action not implemented for macOS")
                                    } else {
                                        Task {
                                            try! await closeWineActivities()
                                            libraryPageGlobals.playingID = nil
                                        }
                                    }
                                } else {
                                    PlayGame()
                                }
                            } label: {
                                Label(isPlaying ? "Stop" :"Play", systemImage: isPlaying ? "stop.fill" : "play.fill").foregroundStyle(.black)
                            }
                            .background(.procyonSecondary)
                            .cornerRadius(20)
                        } else if(item.isInstalled) {
                            ProgressView(value: item.downloadProgress, total: 100,
                                         label: { Text("Downloading...").font(.footnote)
                            }).frame(height: 30)
                        } else {
                            Button {
                                // TO DO: Install script
                            }
                            label: {
                                Label("Install", systemImage: "square.and.arrow.down").foregroundStyle(.black)
                            }
                            .cornerRadius(20)
                        }
                    }
                    .padding(.bottom, 8)
                }.foregroundStyle(.white)
                    .padding(.horizontal)
                }
            .background(.procyonAccent.mix(with: .black, by: 0.6).opacity(0.8))
            .cornerRadius(30)
        }
        .buttonStyle(.plain)
        .frame(height: isResizable ? nil : 214)
    }
    
    @MainActor
    func PlayGame () {
        libraryPageGlobals.selectedGame = updatedItem
        libraryPageGlobals.setLoader(state: true)
        if (isPlaying) {
            return
        }
        Task {
            do {
                let id = item.steamAppID != 0 ? String(describing: item.steamAppID) : String(describing: item.id)
                let gameOptKey = namespacedKey("GameOptions", id)
                let gameOptions: GameOptions = GameOptions()
                if let gameOptionsData: GameOptionsData = readUsrDefData(key: gameOptKey) {
                    gameOptions.set(data: gameOptionsData)
                    console.log("options retrieved")
                } else {
                    console.warn("failed to retrieve game options")
                }
                Task(priority: .background) {
                    tObserver = try await getGameTracker(appNames: updatedItem.appNames, cxAppPath: appGlobals.cxAppPath!, bottleName: appGlobals.selectedBottle, onLoad: { appName in 
                        libraryPageGlobals.playingID = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            libraryPageGlobals.setLoader(state: false)
                            Task {
                                activateApp(appName)
                            }
                        }
                    }, onTerminate: {
                        libraryPageGlobals.setLoader(state: false) // if doesn't get loaded i need to close the loader
                        libraryPageGlobals.playingID = nil
                        tObserver = nil
                    }, isNative: item.isNative, steamID: item.isCustom == true ? nil : item.steamAppID, steamPath: appGlobals.windowsSteamFolder?.path(percentEncoded: false) ?? "")
                }
                if(item.isNative) {
                    try await launchNativeGame(id: String(item.steamAppID), cxAppPath: appGlobals.cxAppPath ?? "", selectedBottle: appGlobals.selectedBottle, options: gameOptions, appExeURL: item.appExeURL)
                } else {
                    if(item.isCustom == true && item.appExeURL == nil) {
                        console.error("custom game doesn't have an executable associated")
                        libraryPageGlobals.setLoader(state: false)
                        return
                    }
                    // Asked before the game starts: that is the moment the
                    // reason is obvious, and the only moment a user who never
                    // opens the options will hear it at all. It asks rather
                    // than acts -- applying a fix renames a file in the game
                    // folder, and doing that behind a play button is not
                    // something to do quietly.
                    if fixes.needsPatch(folder: gameFolder) {
                        warnAboutFix = true
                        libraryPageGlobals.setLoader(state: false)
                        return
                    }
                    let steamExePath = appGlobals.windowsSteamFolder?.appendingPathComponent("Steam.exe").path(percentEncoded: false) ?? "C:\\Program Files (x86)\\Steam\\Steam.exe"
                    try await launchWindowsGame(id: String(item.steamAppID), cxAppPath: appGlobals.cxAppPath ?? "", selectedBottle: gameOptions.useArmBottle ? appGlobals.selectedArmBottle : appGlobals.selectedBottle, steamExePath: steamExePath, options: gameOptions, appExeURL: item.appExeURL)
                }
            } catch {
                console.error(String(reflecting: error))
                libraryPageGlobals.setLoader(state: false)
            }
        }
    }
    
    func openDetailPage() {
        libraryPageGlobals.selectedGame = updatedItem
        libraryPageGlobals.showDetailView =  true
    }
}

#Preview {
    GameThumbnail(item: .mock)
}
