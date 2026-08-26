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
                                // Hands the request to the Steam client in the
                                // bottle, which then asks the user where to put
                                // it and how much it weighs. The confirmation
                                // for a multi-gigabyte download belongs to
                                // Steam's own dialog, not to a button here.
                                let steamX86AppPath = appGlobals.windowsSteamFolder?
                                    .appendingPathComponent("Steam.exe").path(percentEncoded: false)
                                    ?? "C:\\Program Files (x86)\\Steam\\Steam.exe"
                                installGame(id: String(item.steamAppID),
                                            cxAppPath: appGlobals.cxAppPath,
                                            selectedBottle: appGlobals.selectedBottle,
                                            SteamX86AppPath: steamX86AppPath)
                            }
                            label: {
                                Label("Install", systemImage: "square.and.arrow.down").foregroundStyle(.black)
                            }
                            .cornerRadius(20)
                            .help("Opens Steam's install dialog for this title")
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
        // One launch path, shared with the list view. The fix gate lives inside
        // it, so neither view can start an unpatched title by forgetting to
        // check -- which is exactly what a second copy of this would risk.
        switch GameLauncher.shared.play(item,
                                        updatedItem: updatedItem,
                                        isPlaying: isPlaying,
                                        gameFolder: gameFolder,
                                        appGlobals: appGlobals,
                                        libraryPageGlobals: libraryPageGlobals,
                                        fixes: fixes) {
        case .needsFix:
            warnAboutFix = true
        case .started, .noExecutable, .alreadyPlaying:
            break
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
