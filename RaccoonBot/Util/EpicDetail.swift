//
//  EpicDetail.swift
//  RaccoonBot
//
//  The page for an Epic title nobody has installed here.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Where the card for an owned, not-installed Epic title comes from.
///
/// Both lists used to build it by asking Steam: `api.fetchGameInfo(appID:)` with
/// the Epic triple, which Steam's store has of course never heard of. Two
/// things followed. The click did nothing at all -- every Epic cover and every
/// Epic name in the not-installed list was a dead control -- and the failed
/// lookup wrote the Epic id into the Steam blacklist on its way out, where it
/// then counted as a skipped title.
///
/// Epic keeps the answer locally instead: the launcher's catalogue has the
/// title, its art and a short description, and the store page fills in the rest.
/// Both are already read this way for installed titles.
nonisolated enum EpicDetail {

    /// Always returns a card. When the catalogue cannot be read -- no bottle
    /// configured, launcher never signed in -- the owned list's own name and
    /// cover are enough to open a page with, and a thin page beats a click that
    /// does nothing.
    static func game(for owned: OwnedGame, bottleDirectory: URL?) async -> Game {
        let parts = owned.appID.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let namespace = parts.count == 4 ? parts[1] : ""
        let catalogItemId = parts.count == 4 ? parts[2] : ""
        let appName = parts.count == 4 ? parts[3] : ""

        let item = bottleDirectory
            .flatMap { EpicLibrary.dataDirectory(bottle: $0) }
            .flatMap { EpicCatalog.read(dataDirectory: $0) }?
            .item(forAppName: appName,
                  namespace: namespace.isEmpty ? nil : namespace,
                  catalogItemId: catalogItemId.isEmpty ? nil : catalogItemId)

        // The store page, from the cache first and the store at most once --
        // the same order the installed titles use, and the same cache, so
        // opening a card the library already enriched costs nothing.
        var page: EpicStoreContent?
        if !namespace.isEmpty {
            var cache = EpicStoreCache.load()
            if case .some(let known) = cache.lookup(namespace: namespace) {
                page = known
            } else {
                page = await EpicStore.content(for: item?.title ?? owned.displayName,
                                               namespace: namespace)
                cache.record(namespace: namespace, content: page)
                cache.save()
            }
        }

        return Game.epicOwned(id: owned.appID,
                              name: item?.title ?? owned.displayName,
                              catalog: item, store: page, cover: owned.coverURL)
    }
}
