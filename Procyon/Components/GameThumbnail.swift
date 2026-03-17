//
//  GameThumbnail.swift
//  Procyon
//
//  Created by Italo Mandara on 30/01/2026.
//

import SwiftUI
import Kingfisher

struct GameThumbnail: View {
    var item: Game
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @State private var tObserver: TerminationObserver?
    var isPlaying: Bool {
        libraryPageGlobals.playingID == item.id
    }
    var isDownloading: Bool {
        item.downloadProgress < 100
    }
    var updatedItem: Game {
        let meta = libraryPageGlobals.gamesMeta.first(where: { $0.id == item.id })!
        var newItem = item
        newItem.appNames = getAppNames(isNative: meta.isNative, gameURL: meta.gameURL)
        return newItem
    }
    
    var body: some View {

        
        Button(action: {
            openDetailPage()
        }) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing){
                    KFImage(URL(string: item.headerImage))
                        .placeholder {
                            ProgressView()
                        }
                        .resizable()
                        .scaledToFit()
                    if (item.isNative == true) {
                        Image(systemName: "apple.logo")            // icon size
                            .resizable()
                            .frame(width: 16, height: 16)
                            .padding(8)                                // space inside the circle
                            .background(Color.black.opacity(0.1))     // semi-transparent black
                            .clipShape(Circle())                       // make it circular
                            .foregroundStyle(.white.opacity(0.9))                   // icon color
                            .padding(8)
                    }
                }.frame(maxHeight: 150)
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
            .background(.accent.mix(with: .black, by: 0.6).opacity(0.8))
            .cornerRadius(30)
        }
        .buttonStyle(.plain)
    }
    
    func PlayGame () {
        libraryPageGlobals.selectedGame = updatedItem
        libraryPageGlobals.setLoader(state: true)
        if (isPlaying) {
            return
        }
        Task {
            do {
                let gameOptKey = namespacedKey("GameOptions", String(item.steamAppID))
                let gameOptions: GameOptions = GameOptions()
                if let gameOptionsData: GameOptionsData = readUsrDefData(key: gameOptKey) {
                    gameOptions.set(data: gameOptionsData)
                    console.log("options retrieved")
                } else {
                    console.warn("failed to retrieve game options")
                }
                Task(priority: .background) {
                    tObserver = try await getGameTracker(appNames: updatedItem.appNames, cxAppPath: appGlobals.cxAppPath!, bottleName: appGlobals.selectedBottle, onLoad: {
                        libraryPageGlobals.playingID = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            libraryPageGlobals.setLoader(state: false)
                        }
                    }, onTerminate: {
                        libraryPageGlobals.setLoader(state: false) // if doesn't get loaded i need to close the loader
                        libraryPageGlobals.playingID = nil
                        tObserver = nil
                    }, isNative: item.isNative)
                }
                if(item.isNative) {
                    try await launchNativeGame(id: String(item.steamAppID), cxAppPath: appGlobals.cxAppPath ?? "", selectedBottle: appGlobals.selectedBottle, options: gameOptions)
                } else {
                    try await launchWindowsGame(id: String(item.steamAppID), cxAppPath: appGlobals.cxAppPath ?? "", selectedBottle: appGlobals.selectedBottle, options: gameOptions)
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
    @Previewable @State var showDetailView: Bool = false
    @Previewable @State var selectedGame: Game? = nil
    GameThumbnail(item: .mock)
}
