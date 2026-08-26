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
    /// The app id currently being fetched, so its card can say so.
    @State private var opening: String?

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
            } else {
                ScrollView {
                    OwnedGamesGrid()
                        .padding(.bottom, dockClearance)
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

    /// Fetch this one title's store record and show it.
    ///
    /// One request, for the title actually being looked at, and cached after
    /// that. The alternative was fetching all 334 up front, which is 334
    /// requests for descriptions nobody had asked to read.
    private func open(_ game: OwnedGame) async {
        opening = game.appID
        defer { opening = nil }
        guard let info = try? await api.fetchGameInfo(appID: game.appID) else { return }
        libraryPageGlobals.selectedGame = Game(from: info,
                                               id: game.appID,
                                               isNative: game.runsOnMac && !game.runsOnWindows,
                                               downloadProgress: 0,
                                               isInstalled: false,
                                               appNames: [])
        libraryPageGlobals.showDetailView = true
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
    let isOpening: Bool
    let install: () -> Void
    let hide: () -> Void
    let open: () -> Void

    private static let played: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    private var subtitle: String {
        var parts: [String] = []
        if let minutes = game.playtimeMinutes, minutes > 0 {
            parts.append(minutes >= 60 ? "\(minutes / 60) h played" : "\(minutes) min played")
        }
        if let date = game.lastPlayed {
            parts.append("last \(Self.played.string(from: date))")
        }
        if parts.isEmpty { parts.append("Never played") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        // Shaped like the installed cards: the art sits flush at the top so the
        // container's corner radius clips it, rather than floating inside a
        // padded box with its own smaller radius.
        VStack(alignment: .leading, spacing: 6) {
            // The box decides the shape; the picture fills it and the rest is
            // cut off.
            //
            // Steam's cache holds portrait grid art -- 600x900 -- as often as a
            // landscape header, and a card that sizes itself to its picture
            // ends up twice as tall as the ones beside it. Asking the IMAGE for
            // an aspect ratio does that; asking a clear box for one, and
            // overlaying the image inside it, does not. The middle band is what
            // survives, which for cover art is where the subject is.
            Color.clear
                .aspectRatio(2.15, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let cover = game.coverURL {
                        KFImage(cover)
                            .placeholder { CoverPlaceholder(title: game.displayName) }
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        CoverPlaceholder(title: game.displayName)
                    }
                }
                .clipped()
            .overlay(alignment: .center) {
                if isOpening {
                    ProgressView().controlSize(.small)
                        .padding(8)
                        .background(.black.opacity(0.55), in: Circle())
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: open)

            VStack(alignment: .leading, spacing: 6) {
                Text(game.displayName).font(.headline).lineLimit(2)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: open)

                // What the disk actually knows about a title that is not
                // installed. No description or genre: those come from the
                // store, and asking for all of them would be a request each for
                // titles nobody has opened yet.
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)

                HStack(spacing: 6) {
                    PlatformBadges(platforms: game.platforms)
                    Spacer()
                    Button(action: hide) {
                        Image(systemName: "eye.slash")
                    }
                    .controlSize(.small)
                    .buttonStyle(.plain)
                    .help("Hide this title. Steam lists titles the account has no licence for -- free weekends and trials -- and there is no way to tell from disk.")
                    Button(action: install) {
                        Label("Install", systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.small)
                    .cornerRadius(20)
                    .help("Opens Steam's install dialog for this title")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.procyonAccent.mix(with: .black, by: 0.6).opacity(0.8))
        .cornerRadius(30)
        .foregroundStyle(.white)
    }
}

/// Just the cards, with their actions. Used on its own by the All tab, which
/// shows them under the installed ones, and by OwnedGamesList in grid mode.
///
/// It carries install and open rather than taking them as closures: a first
/// version passed `install: {}` and `open: {}` here, which is a card whose
/// buttons quietly do nothing -- and a dead control is worse than an absent
/// one, because it is indistinguishable from a broken one.
struct OwnedGamesGrid: View {
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject var appGlobals: AppGlobals
    @State private var asking: InstallTarget?
    @State private var opening: String?

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(libraryPageGlobals.filteredOwnedGames) { game in
                OwnedGameCard(game: game,
                              isOpening: opening == game.appID,
                              install: { install(game) },
                              hide: { libraryPageGlobals.hide(appID: game.appID) },
                              open: { Task { await open(game) } })
            }
        }
        .padding(.horizontal)
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

    /// One request, for the title actually being looked at, cached after that.
    private func open(_ game: OwnedGame) async {
        opening = game.appID
        defer { opening = nil }
        guard let info = try? await api.fetchGameInfo(appID: game.appID) else { return }
        libraryPageGlobals.selectedGame = Game(from: info,
                                               id: game.appID,
                                               isNative: game.runsOnMac && !game.runsOnWindows,
                                               downloadProgress: 0,
                                               isInstalled: false,
                                               appNames: [])
        libraryPageGlobals.showDetailView = true
    }

    /// Only asks when there is genuinely a choice.
    private func install(_ game: OwnedGame) {
        if game.isCrossPlatform {
            asking = .choose(game)
        } else {
            send(game, toMac: game.runsOnMac && !game.runsOnWindows)
        }
    }

    private func send(_ game: OwnedGame, toMac: Bool) {
        asking = nil
        if toMac {
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
