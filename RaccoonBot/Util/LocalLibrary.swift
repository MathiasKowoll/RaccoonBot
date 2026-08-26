//
//  LocalLibrary.swift
//  RaccoonBot
//
//  Drawing the library from what Steam already wrote to this disk.
//
//  The application used to need the network to name a game it had installed.
//  It does not: the name is a field in the .acf it already parses, and the
//  cover is usually a file in Steam's own art cache inside the bottle. With a
//  cold cache and no reachable API, the library came up empty and said nothing
//  -- 57 installed titles, 57 failed lookups, no error. This is what it draws
//  instead, before any request is made and regardless of whether one succeeds.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum LocalLibrary {

    /// Steam writes its store art here, one directory per app id. Every bottle
    /// has its own, and a title cached by one is not cached by the other, so
    /// all of them are searched.
    static func artCaches(fileManager: FileManager = .default) -> [URL] {
        let bottles = PROCYON_SUPPORT_FOLDER_URL
            .appendingPathComponent(DEFAULT_CXP_BOTTLES_FOLDER, isDirectory: true)
        guard let names = try? fileManager.contentsOfDirectory(atPath: bottles.path(percentEncoded: false))
        else { return [] }
        return names.map {
            bottles.appendingPathComponent($0)
                .appendingPathComponent(DEFAULT_STEAM_WINE_PATH)
                .appendingPathComponent("appcache/librarycache", isDirectory: true)
        }
    }

    /// In preference order. `header.jpg` is the shape the interface expects;
    /// the others are there because Steam does not always cache the first one,
    /// and a wrongly-shaped cover beats no cover.
    static let artNames = ["header.jpg", "library_600x900.jpg", "library_hero.jpg", "logo.png"]

    /// The cover Steam already downloaded for this title, if it did.
    ///
    /// Returns a file URL. Kingfisher renders those, so nothing downstream has
    /// to know whether a cover came from the disk or from the network.
    static func coverURL(forAppID appID: String,
                         caches: [URL]? = nil,
                         fileManager: FileManager = .default) -> URL? {
        guard !appID.isEmpty else { return nil }
        for cache in caches ?? artCaches(fileManager: fileManager) {
            let dir = cache.appendingPathComponent(appID, isDirectory: true)
            for name in artNames {
                let candidate = dir.appendingPathComponent(name)
                if fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                    return candidate
                }
            }
        }
        return nil
    }
}

extension Game {

    /// A card built from the disk alone: no API, no key, no network.
    ///
    /// Every field the store would have filled is left empty rather than
    /// invented. An empty description is visibly empty; a plausible fake one
    /// is not, and this card can be replaced by a real one later.
    init(local meta: GamesMeta, cover: URL? = nil) {
        self.id = meta.id
        self.isNative = meta.isNative
        self.isInstalled = meta.installdir.isEmpty == false
        self.appNames = meta.appNames

        let bytesDown = Double(meta.BytesDownloaded ?? "0") ?? 0
        let bytesTotal = Double(meta.BytesToDownload ?? "0") ?? 0
        self.downloadProgress = meta.isDownloaded() ? 100
            : (bytesTotal > 0 ? (bytesDown / bytesTotal) * 100 : 0)

        self.type = "game"
        // The .acf carries it. Falling back to the install directory is still
        // better than a blank card: Valve picks that name too.
        self.name = meta.name?.isEmpty == false ? meta.name! : meta.installdir
        self.steamAppID = Int(meta.appid) ?? 0
        self.requiredAge = "0"
        self.isFree = false
        self.controllerSupport = nil
        self.dlc = nil

        self.detailedDescription = ""
        self.aboutTheGame = ""
        self.shortDescription = ""
        self.supportedLanguages = nil

        let art = (cover ?? LocalLibrary.coverURL(forAppID: meta.appid))?.absoluteString ?? ""
        self.headerImage = art
        self.capsuleImage = art
        self.capsuleImageV5 = nil
        self.website = nil

        self.pcRequirements = nil
        self.macRequirements = nil
        self.linuxRequirements = nil

        self.legalNotice = nil
        self.developers = []
        self.publishers = []

        self.priceOverview = nil
        self.packages = nil
        self.packageGroups = nil

        self.platforms = Platforms(windows: !meta.isNative, mac: meta.isNative, linux: false)
        self.metacritic = nil

        self.categories = []
        self.genres = nil

        self.screenshots = nil
        self.movies = nil

        self.recommendations = nil
        self.achievements = nil
        self.releaseDate = ReleaseDate(comingSoon: false, date: "")
        self.supportInfo = nil

        self.background = nil
        self.backgroundRaw = nil

        self.contentDescriptors = nil
        self.ratings = nil
    }
}
