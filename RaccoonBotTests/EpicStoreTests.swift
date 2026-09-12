//
//  EpicStoreTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// The store's content page for a title: guessed by slug, checked by
/// namespace, read into what the detail page draws.
struct EpicStoreTests {

    // A page in the store's shape, for a title that does not exist.
    static func page(namespace: String = "ns-1", releaseDate: String? = "2024-03-15T12:00:00.000Z",
                     images: [String] = ["https://cdn/x-1.jpg", "https://cdn/x-2.jpg"]) throws -> Data {
        var meta: [String: Any] = ["_type": "Epic Store Meta", "customReleaseDate": "Coming Soon"]
        if let releaseDate { meta["releaseDate"] = releaseDate }
        let root: [String: Any] = [
            "namespace": namespace, "productName": "Lantern Harbour", "_slug": "lantern-harbour",
            "pages": [[
                "type": "productHome",
                "data": [
                    "about": ["description": "# Lantern Harbour\n\nA quiet town.\n- Fish\n- Sail\n\n\n\nThe **end**.",
                              "shortDescription": "A quiet town by the sea.",
                              "developerAttribution": "Tideworks", "publisherAttribution": "Harbour Press"],
                    "carousel": ["items": [["video": ["recipes": [:]]], ["image": ["src": images[0]]], ["image": ["src": images[1]]]]],
                    "gallery": ["galleryImages": [["src": images[1]], ["src": "https://cdn/x-3.jpg"]]],
                    "hero": ["backgroundImageUrl": "https://cdn/bg.jpg"],
                    "requirements": ["languages": ["AUDIO: English, French | TEXT: English, French, Spanish - Spain"],
                                     "systems": [["systemType": "Windows",
                                                  "details": [["title": "OS", "minimum": "Windows 10", "recommended": "Windows 11"],
                                                              ["title": "Memory", "minimum": "8 GB", "recommended": ""]]]]],
                    "meta": meta,
                ],
            ], ["type": "offer", "data": ["about": ["description": "the deluxe edition"]]]],
        ]
        return try JSONSerialization.data(withJSONObject: root)
    }

    @Test func slugsAreGuessedInAUsefulOrder() {
        #expect(EpicStore.slugCandidates(for: "Alan Wake 2").first == "alan-wake-2")
        #expect(EpicStore.slugCandidates(for: "Borderlands®4").contains("borderlands-4"))
        #expect(EpicStore.slugCandidates(for: "Ys IX: Monstrum Nox").first == "ys-ix-monstrum-nox")
        #expect(EpicStore.slugCandidates(for: "Cronos: The New Dawn").contains("cronos"))
        #expect(EpicStore.slugCandidates(for: "Metro Exodus Enhanced Edition").contains("metro-exodus"))
        #expect(EpicStore.slugCandidates(for: "Monument Valley 2").contains("monument-valley-ii"))
        #expect(EpicStore.slugCandidates(for: "Crysis 3 Remastered").first == "crysis-3-remastered")
        #expect(EpicStore.slugCandidates(for: "Tom & Jerry").first == "tom-and-jerry")
        let c = EpicStore.slugCandidates(for: "Alan Wake 2")
        #expect(Set(c).count == c.count, "no duplicates")
    }

    @Test func thePageIsReadIntoTheFieldsTheDetailDraws() throws {
        let c = try #require(EpicStore.parse(try Self.page(), slug: "lantern-harbour"))
        #expect(c.namespace == "ns-1")
        #expect(c.title == "Lantern Harbour")
        #expect(c.description == "Lantern Harbour\n\nA quiet town.\n• Fish\n• Sail\n\nThe end.", "markdown made plain")
        #expect(c.shortDescription == "A quiet town by the sea.")
        #expect(c.developer == "Tideworks" && c.publisher == "Harbour Press")
        #expect(c.screenshots == ["https://cdn/x-1.jpg", "https://cdn/x-2.jpg", "https://cdn/x-3.jpg"], "carousel images, then the gallery, no video, no repeats")
        #expect(c.background == "https://cdn/bg.jpg")
        #expect(c.minimumRequirements == "OS: Windows 10\nMemory: 8 GB")
        #expect(c.recommendedRequirements == "OS: Windows 11", "an empty recommended line is left out")
        #expect(c.languages == "English, French, Spanish - Spain", "the union, once each")
        #expect(c.releaseDate == "2024-03-15")
    }

    @Test func aFreeTextReleaseDateIsIgnored() throws {
        let c = try #require(EpicStore.parse(try Self.page(releaseDate: nil), slug: "x"))
        #expect(c.releaseDate == nil, "\"Coming Soon\" is not a date")
    }

    @Test func aPageWithoutANamespaceIsNotAPage() throws {
        #expect(EpicStore.parse(Data("{\"pages\":[]}".utf8), slug: "x") == nil)
        #expect(EpicStore.parse(Data("not json".utf8), slug: "x") == nil)
    }

    /// The whole point: a guess that lands on another product is dropped,
    /// a 404 moves on to the next guess, and the right namespace wins.
    @Test func guessesAreCheckedAgainstTheNamespace() async throws {
        let right = try Self.page(namespace: "ns-right")
        let wrong = try Self.page(namespace: "ns-other")
        let fetch: EpicStore.Fetcher = { slug in
            switch slug {
            case "lantern-harbour-2": return (200, wrong)      // another product
            case "lantern-harbour-ii": return (200, right)
            default: return (404, Data())
            }
        }
        let c = await EpicStore.content(for: "Lantern Harbour 2", namespace: "ns-right", fetch: fetch)
        #expect(c?.slug == "lantern-harbour-ii")
        let none = await EpicStore.content(for: "Nothing Here", namespace: "ns-right", fetch: fetch)
        #expect(none == nil)
    }

    /// The page's namespace is not always the catalogue's; the product
    /// name, letters and digits alone, is the second key.
    @Test func aPageUnderAnotherNamespaceIsTheTitlesWhenItsNameIs() async throws {
        let page = try Self.page(namespace: "store-ns")          // productName "Lantern Harbour"
        let fetch: EpicStore.Fetcher = { _ in (200, page) }
        let same = await EpicStore.content(for: "Lantern® Harbour", namespace: "owned-ns", fetch: fetch)
        #expect(same?.slug == "lantern-harbour", "the mark and the space do not make another game")
        let other = await EpicStore.content(for: "Lantern Harbour 2", namespace: "owned-ns", fetch: fetch)
        #expect(other == nil, "another name under another namespace is another product")
        #expect(EpicStore.letters("Ys IX: Monstrum Nox") == "ysixmonstrumnox")
    }

    @Test func theCacheRemembersHitsAndMissesForAWhile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("epicstore-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var cache = EpicStoreCache()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        cache.record(namespace: "hit", content: EpicStoreContent(slug: "s", namespace: "hit", title: "T"), now: t0)
        cache.record(namespace: "miss", content: nil, now: t0)
        cache.save(to: url)
        let back = EpicStoreCache.load(from: url)
        #expect(back.lookup(namespace: "hit", now: t0)??.title == "T")
        if case .some(.none) = back.lookup(namespace: "miss", now: t0) {} else { Issue.record("a fresh miss is an answer") }
        if case .none = back.lookup(namespace: "miss", now: t0.addingTimeInterval(8 * 24 * 3600)) {} else { Issue.record("an old miss is asked again") }
        if case .none = back.lookup(namespace: "never", now: t0) {} else { Issue.record("unknown is asked") }
    }

    @Test func theEpicGameCarriesTheStorePage() throws {
        let installed = EpicInstalled(id: "epic:ns-1:item:app", appName: "app", catalogNamespace: "ns-1", catalogItemId: "item",
                                      title: "Lantern Harbour", folder: URL(fileURLWithPath: "/tmp/x"), executable: nil,
                                      version: "1", presence: .installed)
        let page = try #require(EpicStore.parse(try Self.page(), slug: "lantern-harbour"))
        let g = Game.epic(installed, catalog: nil, store: page)
        #expect(g.detailedDescription.hasPrefix("Lantern Harbour"))
        #expect(g.publishers == ["Harbour Press"] && g.developers == ["Tideworks"])
        #expect(g.screenshots?.count == 3)
        #expect(g.pcRequirements?.minimum == "OS: Windows 10\nMemory: 8 GB")
        #expect(g.supportedLanguages == "English, French, Spanish - Spain")
        #expect(g.releaseDate.date == "2024-03-15")
        #expect(g.background == "https://cdn/bg.jpg")
        #expect(g.headerImage == "https://cdn/bg.jpg", "no catalogue cover: the store's background stands in")
    }

    /// Epic's own copy runs spaces together: six mid-sentence in Alan Wake 2,
    /// two in Ghostwire Tokyo's graphics line. Paragraphs are left alone.
    @Test func runsOfSpacesAreCollapsed() {
        #expect(EpicStore.squeezed("each other, and      affecting the world") == "each other, and affecting the world")
        #expect(EpicStore.squeezed("Arc A380*  (VRAM 6GB)") == "Arc A380* (VRAM 6GB)")
        #expect(EpicStore.squeezed("one\n\ntwo") == "one\n\ntwo", "the blank line is a paragraph")
        #expect(EpicStore.squeezed("  padded  ") == "padded")
    }

    /// "OS: TBD" is worse than no requirements, because it looks like some.
    @Test func placeholderRequirementsAreNotRequirements() throws {
        let page: [String: Any] = ["namespace": "ns", "productName": "P", "pages": [[
            "type": "productHome",
            "data": ["requirements": ["systems": [["systemType": "Windows", "details": [
                ["title": "OS", "minimum": "TBD", "recommended": "TBD"],
                ["title": "Memory", "minimum": "8 GB", "recommended": "n/a"],
            ]]]]],
        ]]]
        let c = try #require(EpicStore.parse(try JSONSerialization.data(withJSONObject: page), slug: "p"))
        #expect(c.minimumRequirements == "Memory: 8 GB", "the TBD line is dropped, the real one kept")
        #expect(c.recommendedRequirements == nil, "every line a placeholder is no block at all")
    }

    /// A miss is kept a week, so a change in the matching would otherwise stay
    /// invisible for a week. Borderlands 4 lived exactly that: its page is
    /// under another namespace, the rules learned to accept it by name, and
    /// the day-old miss went on hiding it.
    @Test func changingTheRulesForgetsWhatTheOldOnesDecided() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rules-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var cache = EpicStoreCache()
        cache.record(namespace: "ns", content: nil)
        cache.save(to: url)
        #expect(EpicStoreCache.load(from: url).entries.count == 1)

        // The same file, written by an older set of rules.
        var stale = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        stale["rules"] = EpicStoreCache.currentRules - 1
        try JSONSerialization.data(withJSONObject: stale).write(to: url)
        #expect(EpicStoreCache.load(from: url).entries.isEmpty, "an older rule's answers are dropped")
    }
}
