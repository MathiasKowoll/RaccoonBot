//
//  EpicCatalog.swift
//  RaccoonBot
//
//  What the Epic launcher knows about the titles in an account, read from the
//  copy it keeps on disk.
//
//  Epic keeps no art or descriptions beside an installed game, and the store
//  answers nothing without a signed-in session: the catalogue endpoint is 401
//  and the store's GraphQL is 403 even with a browser's user agent, measured
//  2026-09-02. What there is, is the launcher's own catalogue cache --
//  Data\Catalog\catcache.bin, base64 around a JSON array -- written when the
//  launcher has signed in and shown the library. On this machine it holds 258
//  items, every installed title among them with title, cover art and
//  description, and every other game in the account. So it is the source for
//  both: what a card shows, and what is owned but not installed.
//
//  When it is not there, nothing here pretends. Installed titles fall back to
//  the name in their manifest, with no cover; the owned list is empty; and the
//  panel says the launcher has to be opened and signed in once.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated struct EpicCatalogItem: Decodable, Equatable {
    struct KeyImage: Decodable, Equatable { let type: String?; let url: String? }
    struct Release: Decodable, Equatable { let appId: String? }
    struct Category: Decodable, Equatable { let path: String? }
    struct MainGame: Decodable, Equatable { let namespace: String?; let id: String? }

    let id: String
    let namespace: String?
    let title: String?
    let description: String?
    let developer: String?
    let keyImages: [KeyImage]?
    let releaseInfo: [Release]?
    let categories: [Category]?
    let mainGameItem: MainGame?
    /// Free-form, per title. Two matter here: FolderName, the folder the
    /// launcher installs into and so the join from a folder on the disk to
    /// its title; and CanRunOffline.
    let customAttributes: [String: Attribute]?
    struct Attribute: Decodable, Equatable { let value: String? }

    var folderName: String? { customAttributes?["FolderName"]?.value }
    var canRunOffline: Bool { customAttributes?["CanRunOffline"]?.value?.lowercased() == "true" }

    /// A game somebody can play, as opposed to DLC, an engine or a tool.
    ///
    /// Base games carry a mainGameItem whose ids are EMPTY STRINGS, not a
    /// missing one -- a predicate of "has a main game" would drop every base
    /// game in the cache, which is exactly what the first attempt did.
    var isBaseGame: Bool {
        let paths = Set((categories ?? []).compactMap(\.path))
        guard paths.contains("games") else { return false }
        return (mainGameItem?.id ?? "").isEmpty
    }

    /// The AppNames this item is released as; the join to a manifest.
    var appNames: [String] { (releaseInfo ?? []).compactMap(\.appId) }

    func image(_ type: String) -> URL? {
        guard let s = (keyImages ?? []).first(where: { $0.type == type })?.url, let u = URL(string: s) else { return nil }
        return u
    }
    /// Landscape, for the card; portrait, for the owned grid.
    var cover: URL? { image("DieselGameBox") ?? image("DieselGameBoxTall") }
    var tallCover: URL? { image("DieselGameBoxTall") ?? image("DieselGameBox") }

    /// The store-tagged identity, matching EpicManifest.tripleID for the same
    /// title, so an installed record and a catalogue record meet on one key.
    func tripleID(appName: String) -> String { "epic:\(namespace ?? ""):\(id):\(appName)" }
}

nonisolated struct EpicCatalog: Equatable {
    let items: [EpicCatalogItem]

    static let fileName = "catcache.bin"

    /// The cache, decoded. Nil when the file is not there or is not what it
    /// should be -- the same answer either way, because the caller's next
    /// move is the same: show what the manifests say and no more.
    static func read(dataDirectory: URL) -> EpicCatalog? {
        let url = dataDirectory.appendingPathComponent("Catalog").appendingPathComponent(fileName)
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return decode(raw)
    }

    static func decode(_ raw: Data) -> EpicCatalog? {
        // Base64 with whatever whitespace the launcher felt like adding.
        guard let json = Data(base64Encoded: raw, options: .ignoreUnknownCharacters),
              let items = try? JSONDecoder().decode([EpicCatalogItem].self, from: json) else { return nil }
        return EpicCatalog(items: items)
    }

    /// The catalogue record for an installed title, by the AppName the
    /// manifest carries, or by its namespace and item id if the release list
    /// does not name it.
    func item(forAppName appName: String, namespace: String?, catalogItemId: String?) -> EpicCatalogItem? {
        if let byApp = items.first(where: { $0.appNames.contains(appName) }) { return byApp }
        guard let namespace, let catalogItemId else { return nil }
        return items.first { $0.namespace == namespace && $0.id == catalogItemId }
    }

    /// Games in the account that no manifest says are installed.
    func ownedNotInstalled(installedAppNames: Set<String>) -> [EpicCatalogItem] {
        items.filter { $0.isBaseGame && $0.appNames.allSatisfy { !installedAppNames.contains($0) } }
             .sorted { ($0.title ?? "").lowercased() < ($1.title ?? "").lowercased() }
    }
}
