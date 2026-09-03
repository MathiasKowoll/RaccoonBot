//
//  StoreActions.swift
//  RaccoonBot
//
//  Who installs a game and who removes it, and how each one is asked.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Which client installs a title, and where.
///
/// The store owns this decision, and it has to be made before the question of
/// Windows or macOS: an Epic id handed to Steam's URL scheme is a request
/// Steam cannot read. Both lists offered Install, both asked about platforms
/// first, and only one of them knew about Epic at all -- so an Epic title
/// with no macOS build was sent to Steam as `steam://install/epic:ns:it:app`.
nonisolated enum Install {

    enum Route: Equatable {
        /// The Windows client in the bottle, through Steam's own dialog.
        case steamInBottle(appID: String)
        /// The native client on this Mac, through the system's steam:// handler.
        case steamOnMac(appID: String)
        /// The Epic launcher in the bottle, asked by its own URI. Nil when the
        /// id is missing a piece the install needs: then the launcher is
        /// opened on the Library and the user finishes it there.
        case epicInBottle(uri: String?)
    }

    /// `toMac` is what the caller resolved for a title that ships for both.
    /// It is only consulted for Steam: the Epic launcher for macOS is not
    /// configured here yet, so every Epic title goes to the bottle.
    static func route(for game: OwnedGame, toMac: Bool) -> Route {
        if game.store == .epic || game.appID.hasPrefix("epic:") {
            return .epicInBottle(uri: EpicLaunch.installURI(forID: game.appID))
        }
        return toMac ? .steamOnMac(appID: game.appID) : .steamInBottle(appID: game.appID)
    }
}

/// Removing a title is the store's business, not ours.
///
/// Both clients keep their own record of what is installed -- Steam in its
/// `.acf` manifests, Epic in `Data\Manifests` and, since 5.5, in the EOS
/// helper's `InstalledItems` as well -- and a folder deleted behind their back
/// leaves the title still listed and no longer playable. So nothing here
/// deletes anything: it works out which client owns the title and what that
/// client has to be asked, and the client confirms with the user in its own
/// window and removes files, manifest and shortcut together.
///
/// Steam has a command for it. Epic has none: measured today against 5.5.4,
/// `?action=uninstall` is answered "Was unable to find URI Handler", and
/// nobody has published the launcher's `FCommunityPortalUninstallCommandlet`
/// invocation. Playnite, which drives the same official client, does not
/// uninstall either -- it opens the Library and waits for the entry to leave
/// `LauncherInstalled.dat`. Legendary does uninstall, but by deleting the
/// files itself, from its own `installed.json`: it cannot see a title the
/// official launcher installed unless you run `egl-sync` first, it knows
/// nothing about the EOS `InstalledItems` store that this launcher now treats
/// as authoritative, and its `egl_restore_or_uninstall` writes a `.item` back
/// whenever the files are still there. So it is not a route to our installs;
/// the launcher's own Library is.
nonisolated enum Uninstall {

    enum Route: Equatable {
        /// Steam's own command. For every installed title Steam writes
        /// `UninstallString = "steam.exe" steam://uninstall/<appid>` under
        /// Uninstall in the bottle's registry, so this is exactly what
        /// Windows would run from Add/Remove Programs.
        case steam(appID: String)
        /// Epic has no such command, so this opens the launcher on the
        /// Library and the user presses Uninstall on the card. Measured
        /// today against 5.5.4: `?action=uninstall` is answered "Was unable
        /// to find URI Handler", while `store/library` is processed and the
        /// router reports "Navigation Complete."
        case epic(uri: String)
    }

    /// Where the Library is. Nothing else in the launcher's URI surface leads
    /// anywhere useful for a removal.
    static let epicLibraryURI = "com.epicgames.launcher://store/library"

    /// Steam's is a real command and takes files away, so it is asked about
    /// first. Epic's only opens a window, and Epic asks for itself in it: a
    /// confirmation in front of that would be a confirmation to open a page.
    static func needsConfirmation(_ route: Route) -> Bool {
        switch route {
        case .steam: return true
        case .epic: return false
        }
    }

    static func buttonTitle(_ route: Route) -> String {
        switch route {
        case .steam: return "Uninstall\u{2026}"
        case .epic: return "Open Epic\u{2026}"
        }
    }

    /// Nil when nothing here can ask for the removal: then the button is not
    /// shown, rather than shown and doing nothing.
    static func route(for game: Game) -> Route? {
        switch game.storeOrSteam {
        case .steam:
            // A title with no Steam id is one of ours, added by hand; Steam
            // has never heard of it and would answer steam://uninstall/0 with
            // a dialog about a game that does not exist.
            guard game.steamAppID > 0 else { return nil }
            return .steam(appID: String(game.steamAppID))
        case .epic:
            return .epic(uri: epicLibraryURI)
        }
    }

    /// The line under the button: who is going to do it.
    static func explanation(_ route: Route) -> String {
        switch route {
        case .steam:
            return "Steam removes the game and its files. It asks you to confirm first."
        case .epic:
            return "Epic has no uninstall command, so this opens the launcher on your Library. Uninstall it from the card there."
        }
    }

    /// The confirmation's own text. It promises only what is certain: the
    /// client does the removal, and asks again on its own side.
    static func warning(for game: Game) -> String {
        switch route(for: game) {
        case .steam:
            return "Steam does the removal in its own window, and asks you to confirm there too."
        case .epic, nil:
            return ""
        }
    }
}
