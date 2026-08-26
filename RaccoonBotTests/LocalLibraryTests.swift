//
//  LocalLibraryTests.swift
//  RaccoonBotTests
//
//  The library has to be drawable with the network unplugged.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct LocalLibraryCoverTests {

    /// Builds an art cache shaped like Steam's own.
    private func cache(_ files: [String: [String]]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("art-\(UUID().uuidString)")
        for (appID, names) in files {
            let dir = root.appendingPathComponent(appID, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in names {
                try Data("jpeg".utf8).write(to: dir.appendingPathComponent(name))
            }
        }
        return root
    }

    @Test func findsTheCoverSteamAlreadyDownloaded() throws {
        let root = try cache(["1325200": ["header.jpg"]])
        defer { try? FileManager.default.removeItem(at: root) }
        let url = LocalLibrary.coverURL(forAppID: "1325200", caches: [root])
        #expect(url?.lastPathComponent == "header.jpg")
        #expect(url?.isFileURL == true)
    }

    @Test func fallsBackToAnotherShapeRatherThanNothing() throws {
        // Steam caches the grid art for plenty of titles whose header it never
        // fetched. Measured: 24 of 57 installed games had header.jpg, 39 had
        // at least one image. Insisting on header.jpg costs fifteen covers.
        let root = try cache(["500": ["library_600x900.jpg"], "600": ["logo.png"]])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(LocalLibrary.coverURL(forAppID: "500", caches: [root])?.lastPathComponent == "library_600x900.jpg")
        #expect(LocalLibrary.coverURL(forAppID: "600", caches: [root])?.lastPathComponent == "logo.png")
    }

    @Test func prefersTheHeaderWhenThereIsAChoice() throws {
        let root = try cache(["700": ["logo.png", "header.jpg", "library_hero.jpg"]])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(LocalLibrary.coverURL(forAppID: "700", caches: [root])?.lastPathComponent == "header.jpg")
    }

    @Test func searchesEveryBottleBecauseEachCachesItsOwn() throws {
        let a = try cache(["800": ["header.jpg"]])
        let b = try cache(["900": ["header.jpg"]])
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        #expect(LocalLibrary.coverURL(forAppID: "900", caches: [a, b]) != nil)
    }

    @Test func saysNothingRatherThanGuessing() throws {
        let root = try cache(["100": ["header.jpg"]])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(LocalLibrary.coverURL(forAppID: "999", caches: [root]) == nil)
        #expect(LocalLibrary.coverURL(forAppID: "", caches: [root]) == nil)
    }
}

struct LocalGameCardTests {

    private func meta(name: String?, appid: String = "1325200") -> GamesMeta {
        let m = GamesMeta(appid: appid, installdir: "Nioh2",
                          bytesDownloaded: "0", BytesTodownload: "0")
        m.name = name
        return m
    }

    @Test func takesTheNameFromTheManifest() {
        let game = Game(local: meta(name: "Nioh 2 – The Complete Edition"), cover: nil)
        #expect(game.name == "Nioh 2 – The Complete Edition")
        #expect(game.steamAppID == 1325200)
        #expect(game.isInstalled)
    }

    @Test func fallsBackToTheFolderRatherThanShowingNothing() {
        // A blank card is worse than a card named after its directory: Valve
        // chooses that name too, and it is at least recognisable.
        #expect(Game(local: meta(name: nil), cover: nil).name == "Nioh2")
        #expect(Game(local: meta(name: ""), cover: nil).name == "Nioh2")
    }

    @Test func leavesTheStoreFieldsEmptyInsteadOfInventingThem() {
        // The disk knows the name; it does not know the blurb. An empty
        // description is visibly empty and can be replaced later. A plausible
        // fabricated one would be neither.
        let game = Game(local: meta(name: "A Game"), cover: nil)
        #expect(game.detailedDescription.isEmpty)
        #expect(game.shortDescription.isEmpty)
        #expect(game.developers.isEmpty)
        #expect(game.categories.isEmpty)
    }

    @Test func carriesTheCoverAsAFileURL() throws {
        let cover = URL(fileURLWithPath: "/tmp/art/1325200/header.jpg")
        let game = Game(local: meta(name: "A Game"), cover: cover)
        #expect(game.headerImage.hasPrefix("file://"))
        #expect(game.capsuleImage == game.headerImage)
    }
}

struct ForbiddenHostTests {

    @Test func refusesUpstreamsProxy() {
        // Not a style preference: that host is one person's Vercel account, its
        // api key is not checked, and it is published in the upstream app's
        // Info.plist -- so a merge or a copied xcconfig is all it would take.
        #expect(FORBIDDEN_API_HOSTS.contains("prapi-chi.vercel.app"))
    }
}
