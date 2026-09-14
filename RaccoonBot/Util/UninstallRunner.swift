//
//  UninstallRunner.swift
//  RaccoonBot
//
//  Asking a title's own client to remove it, from wherever the user asked:
//  the title's options, or the card in the library.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

extension Uninstall {

    /// Hands the removal to the client that installed the title. One copy, so
    /// the card and the options sheet cannot drift apart on which Steam is
    /// asked -- the one in the bottle, or the one on this Mac.
    @MainActor
    static func run(for game: Game, appGlobals: AppGlobals) {
        guard let route = route(for: game) else { return }
        switch route {
        case .steam(let appID):
            let steamX86AppPath = appGlobals.windowsSteamFolder?
                .appendingPathComponent("Steam.exe").path(percentEncoded: false)
                ?? "C:\\Program Files (x86)\\Steam\\Steam.exe"
            console.log("uninstall: asking Steam for \(game.name) (\(appID))")
            uninstallSteamGame(id: appID, cxAppPath: appGlobals.cxAppPath,
                               selectedBottle: appGlobals.selectedBottle,
                               SteamX86AppPath: steamX86AppPath)
        case .steamOnMac(let appID):
            // The Mac's own Steam, through the system handler -- not the one in
            // the bottle, which never installed this and must not be asked to
            // remove it.
            guard let url = URL(string: "steam://uninstall/\(appID)") else { return }
            console.log("uninstall: asking the Mac Steam for \(game.name) (\(appID))")
            NSWorkspace.shared.open(url)
        case .epic(let uri):
            guard let epic = EpicLaunch.target(settings: StoreConfig.settings(for: .epic),
                                               selectedBottle: appGlobals.selectedBottle) else {
                console.error("uninstall: no bottle configured for the Epic launcher")
                return
            }
            console.log("uninstall: opening the Epic library for \(game.name)")
            openEpic(cxAppPath: appGlobals.cxAppPath, bottle: epic.bottle,
                     clientPath: epic.clientPath, uri: uri)
        }
    }
}
