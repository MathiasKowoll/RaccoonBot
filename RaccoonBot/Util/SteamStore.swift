//
//  SteamStore.swift
//  RaccoonBot
//
//  Talking to Steam's storefront directly, in the shape this client expects.
//
//  Upstream never called Steam. It called a proxy, and the proxy did the work
//  of reshaping what Steam returns -- so the Swift types here were written
//  against the proxy's dialect, not Valve's, and pointing the same decoder at
//  store.steampowered.com fails on the very first key. Measured differences:
//
//    envelope     Valve: {"<appid>":{"success":Bool,"data":{…}}}
//                 here:  {"data":[{…}]}                       -> keyNotFound
//    required_age Valve sends int 0 for some apps and "17" for others, in the
//                 same field, on the same day                 -> typeMismatch
//    display_type int from Valve, String in PackageGroup      -> typeMismatch
//    requirements [] for platforms a game does not support    -> typeMismatch
//    descriptions Valve sends HTML; 0 of 420 cached records had a single tag,
//                 so the proxy was rendering it, and nothing downstream knows
//                 what to do with <p class="bb_paragraph">
//
//  So this is not a change of URL. It is the adapter the proxy was, moved into
//  the client where it costs nothing and cannot go down.
//
//  No key is sent and none is needed. This is NOT the upstream proxy -- see
//  FORBIDDEN_API_HOSTS.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum SteamStoreError: Error, LocalizedError {
    case badStatus(Int)
    case notAStoreEntry
    /// Steam asked us to stop. Distinct from any other failure because the
    /// right response is to stop entirely, not to try the next title.
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "Steam answered \(code)"
        case .notAStoreEntry: return "Steam has no store record for this title"
        case .rateLimited: return "Steam is rate limiting this address; the rest will be fetched later"
        }
    }
}

actor SteamStore {

    static let shared = SteamStore()
    private let session: URLSession

    /// Set when Steam pushes back, and honoured until it passes.
    ///
    /// The break in fetchGamesInfo only ends the pass it is in. The library
    /// reloads on every volume mount and unmount -- and this user's games live
    /// on an external drive -- so without a gate that outlives one pass, a
    /// flapping disk, or simply being offline, walks the whole library again
    /// every time. That is the runaway; the number of games is not.
    private var silentUntil: Date?

    /// Consecutive failures that were not a refusal.
    ///
    /// Three in a row is not three unlucky titles, it is no network. Walking
    /// the rest of the library a second apart to discover that fifty-four more
    /// times helps nobody, and the volume observer would do it again on the
    /// next mount.
    private var consecutiveFailures = 0
    static let failuresBeforeGivingUp = 3
    static let offlineCooldown: TimeInterval = 5 * 60

    init(session: URLSession = .shared) { self.session = session }

    /// How long to stay quiet after a refusal. Long enough that a mount storm
    /// cannot turn into a retry storm.
    static let cooldown: TimeInterval = 15 * 60

    var isSilenced: Bool {
        guard let until = silentUntil else { return false }
        return until > Date()
    }

    /// One app id per request: Valve closed the multi-id form of this endpoint.
    /// `appids=220,440` answers HTTP 400 today, with or without `filters=basic`.
    func fetch(appID: String, country: String = "us", language: String = "english") async throws -> SteamGame? {
        if isSilenced { throw SteamStoreError.rateLimited }
        var components = URLComponents(string: "https://store.steampowered.com/api/appdetails")!
        components.queryItems = [
            .init(name: "appids", value: appID),
            // Pinned deliberately. The proxy did not pin it, and its cache came
            // out holding seventeen different currencies because each serverless
            // invocation left from wherever it happened to be.
            .init(name: "cc", value: country),
            .init(name: "l", value: language),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 25
        // Carries no identity: no api key, no Authorization, and -- explicitly
        // -- no cookies. URLSession attaches them by default, and while on
        // macOS the store is the application's own rather than Safari's, "would
        // not happen" is an argument where this is a guarantee.
        //
        // What that does and does not buy, stated honestly: it means the
        // REQUEST names nobody. It does not make it unlinkable. It leaves from
        // the same address the user's Steam client authenticates from, and
        // Valve holds both sides of that log. So this removes the in-band
        // channel; it does not make the traffic invisible. The reason to stay
        // well inside a polite rate is that being anonymous is not the same as
        // being unattributable.
        request.httpShouldHandleCookies = false

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            noteFailure()
            throw error
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        // This endpoint sends no X-RateLimit headers at all, so there is no way
        // to know how close we are -- only to notice when we have arrived. And
        // the address being throttled is the user's own, the one their Steam
        // client uses, so arriving there is worse than being slow.
        if code == 429 || code == 403 {
            silentUntil = Date().addingTimeInterval(Self.cooldown)
            throw SteamStoreError.rateLimited
        }
        guard code == 200 else {
            noteFailure()
            throw SteamStoreError.badStatus(code)
        }
        // A real answer arrived: whatever was wrong before has passed.
        consecutiveFailures = 0

        guard let payload = try Self.unwrap(data, appID: appID) else { return nil }
        let normalised = try JSONSerialization.data(withJSONObject: Self.normalise(payload))
        return try JSONDecoder().decode(SteamGame.self, from: normalised)
    }

    // MARK: - The adapter

    /// Steam keys its answer by app id and wraps it in a success flag. A false
    /// one is a real answer -- delisted, region locked, or not a store item --
    /// and is reported as nil so the caller can blacklist it, exactly the way
    /// the proxy's empty array was used.
    private func noteFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= Self.failuresBeforeGivingUp {
            silentUntil = Date().addingTimeInterval(Self.offlineCooldown)
        }
    }

    /// Only for tests: reaching this state otherwise means being rate limited.
    func silenceForTesting(until: Date) { silentUntil = until }

    nonisolated static func unwrap(_ data: Data, appID: String) throws -> [String: Any]? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root[appID] as? [String: Any] else { throw SteamStoreError.notAStoreEntry }
        guard (entry["success"] as? Bool) == true,
              let payload = entry["data"] as? [String: Any] else { return nil }
        return payload
    }

    /// Coerce the shapes this client cannot decode, and render the HTML the
    /// proxy used to render.
    nonisolated static func normalise(_ input: [String: Any]) -> [String: Any] {
        var out = input

        // Scalars Valve sends as either an int or a string, in both directions.
        for key in ["required_age"] {
            if let n = out[key] as? NSNumber { out[key] = n.stringValue }
        }

        // A platform a game does not support comes back as [] rather than an
        // object, and an empty array is not a Requirements.
        for key in ["pc_requirements", "mac_requirements", "linux_requirements"] {
            if out[key] is [Any] { out[key] = nil }
            else if var block = out[key] as? [String: Any] {
                for field in ["minimum", "recommended"] {
                    if let html = block[field] as? String { block[field] = plainText(from: html) }
                }
                out[key] = block
            }
        }

        // Descriptions arrive as HTML and nothing downstream strips it:
        // GameDetailView renders the string as-is.
        for key in ["detailed_description", "about_the_game", "short_description", "supported_languages"] {
            if let html = out[key] as? String { out[key] = plainText(from: html) }
        }

        if var groups = out["package_groups"] as? [[String: Any]] {
            for index in groups.indices {
                if let n = groups[index]["display_type"] as? NSNumber {
                    groups[index]["display_type"] = n.stringValue
                }
            }
            out["package_groups"] = groups
        }

        return out
    }

    /// Small on purpose: Steam's descriptions use a narrow set of tags, and a
    /// general HTML parser is a dependency this does not need.
    nonisolated static func plainText(from html: String) -> String {
        var text = html
        for (pattern, replacement) in [
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</p\\s*>", "\n"),
            ("(?i)<li[^>]*>", "- "),
            ("(?i)</li\\s*>", "\n"),
            ("(?i)</(ul|ol|h[1-6]|div)\\s*>", "\n"),
            ("<[^>]+>", ""),
        ] {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        for (entity, character) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                    ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
                                    ("&nbsp;", " "), ("&hellip;", "…"), ("&mdash;", "—"),
                                    ("&ndash;", "–"), ("&rsquo;", "’"), ("&lsquo;", "‘")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        // Collapse the blank lines the tag removal leaves behind.
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
