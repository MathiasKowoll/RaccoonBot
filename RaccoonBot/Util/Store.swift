//
//  Store.swift
//  RaccoonBot
//
//  Which shop a game came from, and what that implies.
//
//  Introduced before any Epic code so the migration happens once. Everything
//  that is currently "the bottle" or "the Steam path" is really "this store's
//  bottle" and "this store's client", and saying so is most of the work.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// A store RaccoonBot can read a library from.
///
/// Not a boolean and not a flag on a game's options. `useArmBottle` is a
/// per-title override on top of a default; a store is a property of the title's
/// identity, resolved before options are read. Modelling it the other way round
/// works for exactly two stores and then stops.
nonisolated enum Store: String, CaseIterable, Identifiable, Codable, Sendable {
    case steam
    case epic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .steam: return "Steam"
        case .epic: return "Epic Games"
        }
    }

    /// Steam's mark is already in the asset catalogue; Epic's is a trademark
    /// this repository does not carry, for the same reason it draws the Windows
    /// panes rather than shipping Microsoft's logo. Epic gets a neutral glyph.
    var assetName: String? {
        switch self {
        case .steam: return "steam-fill"
        case .epic: return nil
        }
    }
    var systemSymbol: String {
        switch self {
        case .steam: return "cloud.fill"
        case .epic: return "storefront"
        }
    }

    /// Steam scatters a library across as many folders as you point it at, and
    /// records them in libraryfolders.vdf. Epic records one install path per
    /// title in that title's own manifest, so there is no library list to keep
    /// -- the closest thing is the folder EGL last defaulted to.
    var supportsMultipleLibraries: Bool {
        switch self {
        case .steam: return true
        case .epic: return false
        }
    }

    /// What the client executable is called inside the bottle, for the
    /// fallback when the registry does not say.
    var defaultClientPath: String {
        switch self {
        case .steam:
            return #"C:\Program Files (x86)\Steam\Steam.exe"#
        case .epic:
            return #"C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe"#
        }
    }

    /// Epic's launcher needs an engine at least this new. Steam has no floor
    /// beyond what RaccoonBot itself requires.
    var minimumEngine: String? {
        switch self {
        case .steam: return nil
        case .epic: return "26.3.0"
        }
    }
}

/// Everything RaccoonBot needs to know about one store on this machine.
///
/// Persisted in the shared group domain, so the stable build and the dev build
/// see the same setup.
struct StoreSettings: Codable, Equatable, Sendable {
    /// The bottle this store's client lives in. Empty until chosen.
    var bottle: String = ""
    /// The client executable, as a Windows path inside that bottle. Nil means
    /// "use the default for this store".
    var clientPath: String?
    /// Where its games are installed. Steam keeps several; Epic keeps one.
    var libraries: [String] = []

    var isConfigured: Bool { !bottle.isEmpty }
}

/// Reads and writes the per-store settings.
///
/// Deliberately not an ObservableObject: AppGlobals already publishes the
/// values the interface binds to, and a second source for the same state is how
/// two views end up disagreeing.
enum StoreConfig {

    private static func key(_ store: Store) -> String {
        namespacedKey("StoreSettings", store.rawValue)
    }

    static func settings(for store: Store) -> StoreSettings {
        readUsrDefData(key: key(store)) ?? StoreSettings()
    }

    static func save(_ settings: StoreSettings, for store: Store) {
        persistUsrDefData(key: key(store), data: settings)
    }

    /// Which stores are set up, in a stable order.
    static var configured: [Store] {
        Store.allCases.filter { settings(for: $0).isConfigured }
    }

    /// Carries the existing single-store setup into the per-store shape.
    ///
    /// The application had one bottle and one Steam path because it had one
    /// store. Those values are Steam's, so they become Steam's -- copied, not
    /// moved, so a build from before this change still finds them.
    static func adoptLegacySteamSettings(bottle: String,
                                         steamFolder: URL?,
                                         libraries: [String]) {
        var steam = settings(for: .steam)
        guard !steam.isConfigured else { return }
        steam.bottle = bottle
        if let steamFolder {
            steam.clientPath = steamFolder
                .appendingPathComponent("Steam.exe")
                .path(percentEncoded: false)
        }
        steam.libraries = libraries
        save(steam, for: .steam)
    }
}
