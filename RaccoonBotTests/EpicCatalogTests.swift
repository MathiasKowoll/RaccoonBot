//
//  EpicCatalogTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// The launcher's catalogue cache: what a title is called, what it looks
/// like, and what is owned but not installed.
struct EpicCatalogTests {

    private func item(_ f: [String: Any]) -> [String: Any] {
        var d: [String: Any] = ["id": "item1", "namespace": "ns1", "title": "A Game",
                                "categories": [["path": "public"], ["path": "games"], ["path": "applications"]],
                                "mainGameItem": ["namespace": "", "id": ""],
                                "releaseInfo": [["appId": "app1"]],
                                "keyImages": [["type": "DieselGameBox", "url": "https://cdn/box.jpg"],
                                              ["type": "DieselGameBoxTall", "url": "https://cdn/tall.jpg"]]]
        d.merge(f) { _, new in new }
        return d
    }

    private func cache(_ items: [[String: Any]]) throws -> EpicCatalog {
        let json = try JSONSerialization.data(withJSONObject: items)
        let raw = Data(json.base64EncodedString().utf8)
        return try #require(EpicCatalog.decode(raw))
    }

    @Test func decodesTheBase64WrappedList() throws {
        let c = try cache([item([:])])
        #expect(c.items.count == 1)
        #expect(c.items.first?.title == "A Game")
        #expect(c.items.first?.cover?.absoluteString == "https://cdn/box.jpg")
        #expect(c.items.first?.tallCover?.absoluteString == "https://cdn/tall.jpg")
    }

    /// Base games carry a mainGameItem with EMPTY ids. "Has a main game" would
    /// drop every one of them; the first attempt did exactly that.
    @Test func aBaseGameHasEmptyMainGameIDs() throws {
        let c = try cache([item([:]),
                           item(["id": "dlc", "mainGameItem": ["namespace": "ns1", "id": "item1"]]),
                           item(["id": "eng", "categories": [["path": "engines"]]])])
        #expect(c.items[0].isBaseGame)
        #expect(!c.items[1].isBaseGame, "DLC")
        #expect(!c.items[2].isBaseGame, "not a game")
    }

    /// An installed title meets its catalogue record on the AppName the
    /// manifest carries, which the record lists under releaseInfo.
    @Test func joinsToAManifestByAppName() throws {
        let c = try cache([item([:])])
        #expect(c.item(forAppName: "app1", namespace: nil, catalogItemId: nil)?.title == "A Game")
        #expect(c.item(forAppName: "nope", namespace: "ns1", catalogItemId: "item1")?.title == "A Game", "namespace and id as the fallback")
        #expect(c.item(forAppName: "nope", namespace: "x", catalogItemId: "y") == nil)
    }

    @Test func ownedIsBaseGamesWithNoManifest() throws {
        let c = try cache([item([:]), item(["id": "item2", "title": "Other", "releaseInfo": [["appId": "app2"]]])])
        let owned = c.ownedNotInstalled(installedAppNames: ["app1"])
        #expect(owned.map(\.title) == ["Other"])
        #expect(c.ownedNotInstalled(installedAppNames: ["app1", "app2"]).isEmpty)
    }

    /// Not base64, not JSON, not there: the same nil, because the caller's
    /// next move is the same.
    @Test func garbageIsNilNotACrash() {
        #expect(EpicCatalog.decode(Data("not base64!!".utf8)) == nil)
        #expect(EpicCatalog.decode(Data("bm90IGpzb24=".utf8)) == nil)   // "not json"
        #expect(EpicCatalog.read(dataDirectory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")) == nil)
    }

    /// Whitespace in the base64 is tolerated; the launcher's own file is
    /// one long line, but nothing says it has to be.
    @Test func base64WithLineBreaksStillDecodes() throws {
        let json = try JSONSerialization.data(withJSONObject: [item([:])])
        let wrapped = json.base64EncodedString(options: [.lineLength64Characters])
        #expect(EpicCatalog.decode(Data(wrapped.utf8))?.items.count == 1)
    }
}

/// Which name wins for an installed title.
struct EpicTitleNameTests {
    @Test func theManifestNamesAnInstalledTitle() throws {
        let installed = EpicInstalled(id: "epic:ns:item:app", appName: "app", catalogNamespace: "ns",
                                      catalogItemId: "item", title: "Borderlands®4",
                                      folder: URL(fileURLWithPath: "/tmp/x"), executable: nil,
                                      version: "1", presence: .installed)
        let json = try JSONSerialization.data(withJSONObject: [["id": "item", "namespace": "ns", "title": "Borderlands?4",
                                                                "keyImages": [["type": "DieselGameBox", "url": "https://cdn/b.jpg"]]]])
        let item = try #require(EpicCatalog.decode(Data(json.base64EncodedString().utf8))?.items.first)
        let game = Game.epic(installed, catalog: item)
        #expect(game.name == "Borderlands®4", "the mark the cache lost")
        #expect(game.headerImage == "https://cdn/b.jpg", "the art the manifest never had")
    }
}
