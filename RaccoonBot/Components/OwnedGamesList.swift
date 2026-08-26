//
//  OwnedGamesList.swift
//  RaccoonBot
//
//  The titles a person owns and has not installed.
//
//  Everything shown here is read from the disk: the ids from localconfig.vdf,
//  the names from appinfo.vdf, the art from Steam's own cache. Nothing on this
//  screen costs a request.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import Kingfisher

/// Which Steam should be asked to install a title that ships for both.
enum InstallTarget: Identifiable {
    case choose(OwnedGame)
    var id: String {
        switch self { case .choose(let game): return game.appID }
    }
}

struct OwnedGamesList: View {
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject var appGlobals: AppGlobals
    @State private var asking: InstallTarget?

    var body: some View {
        Group {
            if !libraryPageGlobals.ownedLoaded {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Reading your library from disk…")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if libraryPageGlobals.ownedGames.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing else to install").font(.headline)
                    Text("Every title Steam knows about on this machine is already installed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if libraryPageGlobals.viewMode == .list {
                LibraryTable(games: libraryPageGlobals.filteredOwnedGames, install: install)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(libraryPageGlobals.filteredOwnedGames) { game in
                            OwnedGameCard(game: game) { install(game) }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .confirmationDialog("Which version?", isPresented: .constant(asking != nil), presenting: asking) { target in
            if case .choose(let game) = target {
                Button("Windows version") { send(game, toMac: false) }
                Button("macOS version") { send(game, toMac: true) }
                Button("Cancel", role: .cancel) { asking = nil }
            }
        } message: { target in
            if case .choose(let game) = target {
                Text("\(game.displayName) ships for both. The Windows version runs in the bottle, which is where the video fixes apply; the macOS version is handled by the Steam app on this Mac.")
            }
        }
    }

    private func install(_ game: OwnedGame) {
        // Only ask when there is genuinely a choice. A Windows-only title has
        // one answer and a dialog for it is just a click.
        if game.isCrossPlatform {
            asking = .choose(game)
        } else {
            send(game, toMac: game.runsOnMac && !game.runsOnWindows)
        }
    }

    private func send(_ game: OwnedGame, toMac: Bool) {
        asking = nil
        if toMac {
            // The native client on this Mac, which has its own library folders.
            if let url = URL(string: "steam://install/\(game.appID)") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        let steamX86AppPath = appGlobals.windowsSteamFolder?
            .appendingPathComponent("Steam.exe").path(percentEncoded: false)
            ?? "C:\\Program Files (x86)\\Steam\\Steam.exe"
        installGame(id: game.appID,
                    cxAppPath: appGlobals.cxAppPath,
                    selectedBottle: appGlobals.selectedBottle,
                    SteamX86AppPath: steamX86AppPath)
    }
}

struct OwnedGameCard: View {
    let game: OwnedGame
    let install: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let cover = game.coverURL {
                KFImage(cover)
                    .placeholder { CoverPlaceholder(title: game.displayName) }
                    .resizable()
                    .aspectRatio(2.15, contentMode: .fit)
                    .frame(maxWidth: .infinity, alignment: .top)
            } else {
                CoverPlaceholder(title: game.displayName)
            }

            Text(game.displayName).font(.headline).lineLimit(2)

            HStack(spacing: 6) {
                ForEach(game.platforms.sorted(), id: \.self) { platform in
                    Text(platform == "macos" ? "Mac" : platform.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Button(action: install) {
                    Label("Install", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .help("Opens Steam's install dialog for this title")
            }
        }
        .padding(8)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(.white)
    }
}
