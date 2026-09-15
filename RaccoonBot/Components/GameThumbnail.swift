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

    /// The controller is on this card.
    ///
    /// Defaulted so that every existing caller -- the mouse ones -- is
    /// unchanged: this is an addition to how the grid is used, not a
    /// replacement. Clicking works exactly as it did whether or not a pad is
    /// connected, and a pad selection is drawn on top of that rather than
    /// instead of it.
    var isSelected: Bool = false
    /// Opens this title's options where the grid can show them. Without one --
    /// a card somewhere that has no options sheet of its own -- the gear opens
    /// the title's page, which has.
    var showOptions: (() -> Void)? = nil
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @State private var tObserver: TerminationObserver?
    @StateObject private var fixes = MGVFLibrary.shared
    @State private var warnAboutFix = false
    @State private var confirmingUninstall = false

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
                        if item.isEpic {
                            Text("EPIC").font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Capsule().fill(.white.opacity(0.18)))
                                .padding(.vertical, 8)
                                .help(item.isInstalled ? "Installed by the Epic Games Launcher" : "Installed, but its drive is not mounted")
                        }
                        if (item.isCustom == true) {
                            Button {
                                libraryPageGlobals.deleteCustomAddedGame(game: item)
                            } label: {
                                OIcon("trash").padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                // Two lines under the cover. The first says what the title is:
                // its name on the left, its tags on the right. The second, a
                // little apart and centred, is what can be done with it: play,
                // its options, its folder, its removal and its page -- so
                // changing a setting no longer means opening the page first. A
                // title that is not installed gets Install and its page in the
                // same place. The name gives up room before the tags do.
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(-1)
                        Spacer(minLength: 8)
                        AccentTag(item.type).fixedSize()
                        if let genre = item.genres?.first {
                            AccentTag(genre.description).fixedSize()
                        }
                        if item.isInstalled {
                            AccentTag(item.isNative == true ? "Mac" : "Pc").fixedSize()
                        }
                    }
                    HStack {
                        Spacer(minLength: 0)
                        if !isDownloading && item.isInstalled {
                            CardActionPill(actions: installedActions)
                        } else if item.isInstalled {
                            ProgressView(value: item.downloadProgress, total: 100,
                                         label: { Text("Downloading...").font(.footnote) })
                                .frame(width: 180, height: 30)
                        } else {
                            CardActionPill(actions: [
                                CardAction(label: "Install", systemImage: "square.and.arrow.down",
                                           help: "Opens Steam's install dialog for this title",
                                           action: { installFromCard() }),
                                CardAction(systemImage: "info.circle.fill", help: "Open this title's page",
                                           action: { openDetailPage() }),
                            ])
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 8)
                }
                .foregroundStyle(.white)
                    .padding(.horizontal)
                }
            .background(.procyonAccent.mix(with: .black, by: 0.6).opacity(0.8))
            .cornerRadius(30)
        }
        .buttonStyle(.plain)
        // On the card rather than on one of its buttons. It sat on the delete
        // button of a custom title, so the fixes were only loaded, and the
        // warning only ever shown, for custom titles; Play on any other card
        // that needed a fix did nothing at all.
        .task { await fixes.loadIfNeeded() }
        .alert("This title needs its video fix", isPresented: $warnAboutFix) {
            Button("Open options") { if let showOptions { showOptions() } else { openDetailPage() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(fixes.entry(for: gameFolder)?.why ?? "Its video will not play without it.")
        }
        // The same question the title's options ask, in the same words: Steam
        // does the removal, and asks again in its own window.
        .confirmationDialog("Uninstall \(item.name)?",
                            isPresented: $confirmingUninstall,
                            titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) { Uninstall.run(for: item, appGlobals: appGlobals) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Uninstall.warning(for: item))
        }
        .frame(height: isResizable ? nil : 214)
        // Drawn on top of the card, and sized with scaleEffect rather than by
        // changing the frame: a selection that changed the layout would reflow
        // the whole grid on every press, which is both distracting and the
        // thing that makes the buttons on the neighbouring cards jump.
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .strokeBorder(.white, lineWidth: 3)
                .opacity(isSelected ? 1 : 0)
        )
        .scaleEffect(isSelected ? 1.04 : 1)
        .shadow(color: .black.opacity(isSelected ? 0.45 : 0), radius: 14, y: 6)
        .zIndex(isSelected ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
    
    /// Play or Stop, the options, the folder, Uninstall when a client can do it,
    /// and the page. A title added by hand has no client to ask, so it has no
    /// Uninstall here: its card keeps the delete button on the cover.
    private var installedActions: [CardAction] {
        var list: [CardAction] = [
            CardAction(label: isPlaying ? "Stop" : "Play",
                       systemImage: isPlaying ? "stop.fill" : "play.fill",
                       help: isPlaying ? "Stop this title" : "Play this title",
                       action: { if isPlaying { stopGame() } else { PlayGame() } }),
            CardAction(systemImage: "gear", help: "This title's options",
                       action: { if let showOptions { showOptions() } else { openDetailPage() } }),
            CardAction(systemImage: "folder.fill", help: "Open the game's folder",
                       action: { openFolder() }),
        ]
        if let route = Uninstall.route(for: item) {
            list.append(CardAction(systemImage: "trash", help: Uninstall.explanation(route),
                                   action: {
                                       if Uninstall.needsConfirmation(route) {
                                           confirmingUninstall = true
                                       } else {
                                           Uninstall.run(for: item, appGlobals: appGlobals)
                                       }
                                   }))
        }
        list.append(CardAction(systemImage: "info.circle.fill", help: "Open this title's page",
                               action: { openDetailPage() }))
        return list
    }

    /// Hands the request to the Steam client in the bottle, which then asks the
    /// user where to put it and how much it weighs. The confirmation for a
    /// multi-gigabyte download belongs to Steam's own dialog, not to a button
    /// here.
    private func installFromCard() {
        let steamX86AppPath = appGlobals.windowsSteamFolder?
            .appendingPathComponent("Steam.exe").path(percentEncoded: false)
            ?? "C:\\Program Files (x86)\\Steam\\Steam.exe"
        installGame(id: String(item.steamAppID),
                    cxAppPath: appGlobals.cxAppPath,
                    selectedBottle: appGlobals.selectedBottle,
                    SteamX86AppPath: steamX86AppPath)
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

    /// Stopping by hand deserves the same courtesy as stopping by itself: ask
    /// Steam to go, let it finish, then close this bottle -- not every bottle
    /// on the machine.
    func stopGame() {
        if item.isNative {
            console.log("stop action not implemented for macOS")
            return
        }
        Task {
            if let cx = appGlobals.cxAppPath {
                if item.isEpic {
                    // The game is asked to close; its tracker then waits for
                    // the launcher's sync and closes the bottle.
                    let epic = EpicLaunch.target(settings: StoreConfig.settings(for: .epic), selectedBottle: appGlobals.selectedBottle)
                    try? await stopEpicGame(appNames: item.appNames, cxAppPath: cx, bottle: epic?.bottle ?? appGlobals.selectedBottle)
                    return
                }
                try? await quitSteam(cxAppPath: cx, bottle: appGlobals.selectedBottle, isNative: false)
                try? await closeBottle(cxAppPath: cx, bottle: appGlobals.selectedBottle)
            }
            libraryPageGlobals.playingID = nil
        }
    }

    /// The folder the title lives in, the way its page opens it.
    func openFolder() {
        if let url = getMeta(libraryPageGlobals.gamesMeta, byID: item.id)?.gameURL {
            showFolder(url: url)
        } else if let exe = item.appExeURL {
            showFolder(url: exe.deletingLastPathComponent())
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
