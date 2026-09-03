//
//  EpicStore.swift
//  RaccoonBot
//
//  What the Epic Games Store will say about a title without a session.
//
//  The launcher's catalogue cache carries a title, a sentence of description,
//  a developer and two covers, and no more: no long description, publisher,
//  screenshots, requirements, languages or release date. The store's catalogue
//  API answers 401 and its GraphQL 403 to anyone not signed in (measured
//  2026-09-02). What does answer is the store's content endpoint, the one its
//  product pages are built from, by the page's slug:
//
//      https://store-content.ak.epicgames.com/api/en-US/content/products/<slug>
//
//  It carries all of the above and, decisively, the product's `namespace`,
//  which is the catalogue's namespace for the same title. So a slug guessed
//  from the title can be CHECKED before a word of it is shown: a guess that
//  lands on another product has another namespace and is dropped. Guessing
//  hit ten of fourteen titles here on the first try; a wrong slug is a 404.
//
//  Two things the page does not give reliably. `customReleaseDate` is free
//  text ("Coming Soon" on a game two years out) and is ignored; only an ISO
//  `releaseDate` is taken. And ratings come back as an empty object.
//
//  Fetched once per title and kept in the caches directory, as the Steam
//  information is; a miss is kept too, for a week, so a title the store does
//  not name under any guess is not asked about on every start.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated struct EpicStoreContent: Codable, Equatable {
    var slug: String
    var namespace: String
    var title: String?
    var description: String?
    var shortDescription: String?
    var developer: String?
    var publisher: String?
    var screenshots: [String] = []
    var background: String?
    var minimumRequirements: String?
    var recommendedRequirements: String?
    /// Comma-separated, which is how the detail page splits Steam's.
    var languages: String?
    /// ISO date, YYYY-MM-DD, or nil.
    var releaseDate: String?
}

nonisolated enum EpicStore {

    static let endpoint = "https://store-content.ak.epicgames.com/api/en-US/content/products/"

    // MARK: - guessing the slug

    /// The slugs a title is likely to live under, most likely first. All of
    /// them are checked against the namespace, so a wrong guess costs a
    /// request and nothing else.
    static func slugCandidates(for title: String) -> [String] {
        let ascii = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
            .unicodeScalars.filter { $0.isASCII }.map(String.init).joined()
            .lowercased()
        func slug(_ s: String) -> String {
            var out = ""; var dash = false
            for ch in s {
                if ch.isLetter || ch.isNumber { out.append(ch); dash = false }
                else if !dash && !out.isEmpty { out.append("-"); dash = true }
            }
            while out.hasSuffix("-") { out.removeLast() }
            return out
        }
        var c: [String] = []
        let base = slug(ascii)
        c.append(base)
        // A digit glued to a word: "borderlands4" -> "borderlands-4".
        var split = ""; var prev: Character? = nil
        for ch in base {
            if let p = prev, p.isLetter, ch.isNumber { split.append("-") }
            split.append(ch); prev = ch
        }
        c.append(split)
        // The title before a colon or a dash: "Cronos: The New Dawn" -> "cronos".
        if let i = title.firstIndex(where: { $0 == ":" || $0 == "–" || $0 == "—" }) {
            c.append(slug(String(title[..<i]).lowercased()))
        }
        // Edition words the store page does not carry.
        let editions = ["-enhanced-edition", "-definitive-edition", "-game-of-the-year-edition", "-goty-edition", "-goty",
                        "-deluxe-edition", "-ultimate-edition", "-complete-edition", "-gold-edition", "-standard-edition", "-remastered"]
        for e in editions where base.hasSuffix(e) { c.append(String(base.dropLast(e.count))) }
        // A trailing number as a roman numeral, and the other way round.
        let romans = ["2": "ii", "3": "iii", "4": "iv", "5": "v", "6": "vi"]
        for (d, r) in romans {
            if split.hasSuffix("-" + d) { c.append(String(split.dropLast(d.count)) + r) }
            if base.hasSuffix("-" + r) { c.append(String(base.dropLast(r.count)) + d) }
        }
        var seen: Set<String> = []
        return c.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - fetching

    typealias Fetcher = @Sendable (String) async throws -> (status: Int, body: Data)

    static let live: Fetcher = { slug in
        var req = URLRequest(url: URL(string: endpoint + slug)!)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    /// The page for a title, or nil when no guess lands on its namespace.
    static func content(for title: String, namespace: String, fetch: Fetcher = live) async -> EpicStoreContent? {
        for slug in slugCandidates(for: title) {
            guard let (status, body) = try? await fetch(slug) else { continue }
            guard status == 200, let page = parse(body, slug: slug) else { continue }
            if page.namespace == namespace { return page }
            console.log("epic store: \(slug) is another product (\(page.namespace.prefix(8)) vs \(namespace.prefix(8))); not \(title)")
        }
        return nil
    }

    // MARK: - reading the page

    static func parse(_ data: Data, slug: String) -> EpicStoreContent? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let namespace = root["namespace"] as? String, !namespace.isEmpty else { return nil }
        var c = EpicStoreContent(slug: slug, namespace: namespace)
        c.title = root["productName"] as? String
        let pages = root["pages"] as? [[String: Any]] ?? []
        // The product's home page; the others are editions and add-ons.
        guard let page = pages.first(where: { ($0["type"] as? String) == "productHome" }) ?? pages.first,
              let d = page["data"] as? [String: Any] else { return c }
        if let about = d["about"] as? [String: Any] {
            c.description = plainText(about["description"] as? String)
            c.shortDescription = plainText(about["shortDescription"] as? String)
            c.developer = nonEmpty(about["developerAttribution"] as? String)
            c.publisher = nonEmpty(about["publisherAttribution"] as? String)
        }
        var shots: [String] = []
        if let carousel = d["carousel"] as? [String: Any], let items = carousel["items"] as? [[String: Any]] {
            for it in items {
                if let src = (it["image"] as? [String: Any])?["src"] as? String, !src.isEmpty { shots.append(src) }
            }
        }
        if let gallery = d["gallery"] as? [String: Any], let images = gallery["galleryImages"] as? [[String: Any]] {
            for g in images { if let src = g["src"] as? String, !src.isEmpty { shots.append(src) } }
        }
        var seen: Set<String> = []
        c.screenshots = shots.filter { seen.insert($0).inserted }
        if let hero = d["hero"] as? [String: Any] {
            c.background = nonEmpty(hero["backgroundImageUrl"] as? String)
        }
        if let req = d["requirements"] as? [String: Any] {
            if let systems = req["systems"] as? [[String: Any]] {
                let windows = systems.first { ($0["systemType"] as? String)?.lowercased().contains("windows") == true } ?? systems.first
                if let details = windows?["details"] as? [[String: Any]] {
                    let minimum = details.compactMap { line($0, "minimum") }.joined(separator: "\n")
                    let recommended = details.compactMap { line($0, "recommended") }.joined(separator: "\n")
                    c.minimumRequirements = nonEmpty(minimum)
                    c.recommendedRequirements = nonEmpty(recommended)
                }
            }
            if let langs = req["languages"] as? [String] { c.languages = languages(from: langs) }
        }
        if let meta = d["meta"] as? [String: Any], let iso = meta["releaseDate"] as? String, iso.count >= 10,
           iso.prefix(10).filter({ $0 == "-" }).count == 2 {
            c.releaseDate = String(iso.prefix(10))
        }
        return c
    }

    private static func line(_ d: [String: Any], _ key: String) -> String? {
        guard let title = d["title"] as? String, let value = d[key] as? String, !value.isEmpty else { return nil }
        return "\(title): \(value)"
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// "AUDIO: English, German | TEXT: English, German, French" -> the union,
    /// comma-separated, in order of first appearance.
    static func languages(from lines: [String]) -> String? {
        var names: [String] = []; var seen: Set<String> = []
        for l in lines {
            for part in l.components(separatedBy: "|") {
                var s = part
                if let colon = s.firstIndex(of: ":") { s = String(s[s.index(after: colon)...]) }
                for name in s.components(separatedBy: ",") {
                    let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !n.isEmpty, seen.insert(n.lowercased()).inserted { names.append(n) }
                }
            }
        }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// The page text is light Markdown; the detail page draws plain text.
    static func plainText(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        var out: [String] = []
        for raw in s.components(separatedBy: "\n") {
            var l = raw.trimmingCharacters(in: .whitespaces)
            while l.hasPrefix("#") { l.removeFirst() }
            l = l.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("- ") || l.hasPrefix("* ") { l = "• " + l.dropFirst(2) }
            l = l.replacingOccurrences(of: "**", with: "")
            out.append(l)
        }
        var text = out.joined(separator: "\n")
        while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return nonEmpty(text)
    }
}

/// One fetch per title, kept on disk as the Steam information is.
nonisolated struct EpicStoreCache: Codable, Equatable {
    struct Entry: Codable, Equatable { var content: EpicStoreContent?; var checked: Date }
    var entries: [String: Entry] = [:]     // by namespace

    static let missRetry: TimeInterval = 7 * 24 * 3600

    static var defaultURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RaccoonBotEpicStoreCache.json")
    }

    static func load(from url: URL = defaultURL) -> EpicStoreCache {
        guard let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(EpicStoreCache.self, from: d) else { return EpicStoreCache() }
        return c
    }

    func save(to url: URL = defaultURL) {
        guard let d = try? JSONEncoder().encode(self) else { return }
        try? d.write(to: url, options: .atomic)
    }

    /// The content if known, nil if a fresh miss, and `.none` (a missing
    /// key) when it is time to ask.
    func lookup(namespace: String, now: Date = Date()) -> EpicStoreContent?? {
        guard let e = entries[namespace] else { return .none }
        if e.content == nil, now.timeIntervalSince(e.checked) > Self.missRetry { return .none }
        return .some(e.content)
    }

    mutating func record(namespace: String, content: EpicStoreContent?, now: Date = Date()) {
        entries[namespace] = Entry(content: content, checked: now)
    }
}
