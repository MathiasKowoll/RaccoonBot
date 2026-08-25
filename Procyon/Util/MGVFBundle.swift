//
//  MGVFBundle.swift
//  Procyon
//
//  Fetches the MacGameVideoFix fixes bundle -- the installers, the carrier DLL
//  each of them names, the PE reader and a manifest -- and keeps it on disk by
//  tag.
//
//  The same shape DXMT already uses here, plus the three things that one does
//  not do: verify the download before trusting it, survive GitHub answering
//  something other than JSON, and fall back to what is already on disk rather
//  than leaving the caller with nothing.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CryptoKit

// MARK: - The manifest

/// One title, as the fixes repository describes it.
///
/// Derived over there from the installers themselves, so this is read and never
/// written: a second copy of which DLL belongs to which game is the copy that
/// goes stale the first time a title is added.
struct MGVFGame: Codable, Hashable {
    let script: String
    /// The shipping executable. This is the identity -- not an app id, which
    /// neither repository records, and not the folder name, which Valve
    /// chooses: Mortal Shell 2 installs into a folder called "Sparta".
    let exe: String
    let files: [String]
    /// The DLL the proxy takes the place of.
    let carrier: String
    /// What the original is renamed to.
    let keptAs: String
    /// Whether the fix also needs a DLL override in the bottle's registry.
    let writesRegistry: Bool
}

struct MGVFManifest: Codable {
    let schema: Int
    let version: String
    let commit: String
    let games: [MGVFGame]

    /// Refuse a manifest written to a contract this build does not know.
    ///
    /// Reading a newer schema on a best-effort basis is how a field that
    /// changed meaning gets acted on anyway. Better to say the bundle is too
    /// new and let the user update.
    static let supportedSchema = 1
    var isSupported: Bool { schema == Self.supportedSchema }
}

// MARK: - Errors

enum MGVFBundleError: LocalizedError {
    case noRelease(String)
    case noAsset(String)
    case checksumMismatch(expected: String, got: String)
    case extractionFailed(String)
    case manifestUnreadable(String)
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .noRelease(let why):
            return "Could not find the fixes release: \(why)"
        case .noAsset(let tag):
            return "Release \(tag) has no fixes bundle attached"
        case .checksumMismatch(let expected, let got):
            return "The download did not match its checksum (expected \(expected.prefix(12))…, got \(got.prefix(12))…)"
        case .extractionFailed(let why):
            return "Could not unpack the fixes bundle: \(why)"
        case .manifestUnreadable(let why):
            return "The fixes bundle has no readable manifest: \(why)"
        case .unsupportedSchema(let n):
            return "This bundle is written for a newer version of Procyon (manifest schema \(n))"
        }
    }
}

// MARK: - The bundle

final class MGVFBundle: @unchecked Sendable {
    static let shared = MGVFBundle()

    private let repo = "MathiasKowoll/MacGameVideoFix"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Where unpacked bundles live, one directory per tag.
    ///
    /// By tag, so a downgrade is a directory that is already there and an
    /// upgrade never overwrites something a run in flight is reading from.
    var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Procyon/mgvf", isDirectory: true)
    }

    func directory(for tag: String) -> URL {
        root.appendingPathComponent(tag, isDirectory: true)
    }

    /// Every tag already unpacked, newest-looking first.
    func cachedTags() -> [String] {
        let f = FileManager.default
        guard let entries = try? f.contentsOfDirectory(atPath: root.path(percentEncoded: false)) else { return [] }
        return entries
            .filter { f.fileExists(atPath: directory(for: $0).appendingPathComponent("manifest.json").path(percentEncoded: false)) }
            .sorted { Self.compareTags($0, $1) == .orderedDescending }
    }

    /// The newest bundle already on disk, if any.
    func cached() -> URL? {
        cachedTags().first.map { directory(for: $0) }
    }

    /// Make sure a usable bundle is on disk, and return where it is.
    ///
    /// Network failure is not fatal when something is already cached: a
    /// launcher that cannot reach GitHub should still be able to apply the
    /// fixes it downloaded last week. It only throws when there is nothing at
    /// all to fall back on.
    @discardableResult
    func ensureAvailable() async throws -> URL {
        do {
            let release = try await latestRelease()
            let target = directory(for: release.tag)
            if FileManager.default.fileExists(atPath: target.appendingPathComponent("manifest.json").path(percentEncoded: false)) {
                return target
            }
            return try await download(release)
        } catch {
            if let fallback = cached() {
                console.warn("Using the cached fixes bundle: \(error.localizedDescription)")
                return fallback
            }
            throw error
        }
    }

    /// Read the manifest out of an unpacked bundle.
    func manifest(at directory: URL) throws -> MGVFManifest {
        let url = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else {
            throw MGVFBundleError.manifestUnreadable(url.lastPathComponent)
        }
        let manifest: MGVFManifest
        do {
            manifest = try JSONDecoder().decode(MGVFManifest.self, from: data)
        } catch {
            throw MGVFBundleError.manifestUnreadable(error.localizedDescription)
        }
        guard manifest.isSupported else {
            throw MGVFBundleError.unsupportedSchema(manifest.schema)
        }
        return manifest
    }

    // MARK: - Release resolution

    struct Release {
        let tag: String
        let tarball: URL
        let checksum: URL?
    }

    /// Ask GitHub for the newest release and pick the two assets we want.
    ///
    /// Every field is read as optional. The anonymous API allows 60 requests an
    /// hour and answers a rate limit with a JSON object that has a `message`
    /// and no `tag_name`; forcing that cast is how the DXMT path crashes the
    /// app rather than reporting a busy server.
    func latestRelease() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MGVFBundleError.noRelease("GitHub answered \(http.statusCode)")
        }
        return try Self.parseRelease(data)
    }

    /// Split out from the request so it can be tested against real payloads,
    /// including the ones that are not releases at all.
    static func parseRelease(_ data: Data) throws -> Release {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw MGVFBundleError.noRelease("the answer was not JSON")
        }
        if let message = root["message"] as? String, root["tag_name"] == nil {
            throw MGVFBundleError.noRelease(message)
        }
        guard let tag = root["tag_name"] as? String else {
            throw MGVFBundleError.noRelease("no tag in the answer")
        }
        let assets = (root["assets"] as? [[String: Any]]) ?? []
        func asset(matching test: (String) -> Bool) -> URL? {
            for a in assets {
                guard let name = a["name"] as? String, test(name),
                      let href = a["browser_download_url"] as? String,
                      let url = URL(string: href) else { continue }
                return url
            }
            return nil
        }
        guard let tarball = asset(matching: { $0.hasPrefix("fixes-") && $0.hasSuffix(".tar.gz") }) else {
            throw MGVFBundleError.noAsset(tag)
        }
        return Release(tag: tag,
                       tarball: tarball,
                       checksum: asset(matching: { $0.hasSuffix(".tar.gz.sha256") }))
    }

    // MARK: - Download and unpack

    private func download(_ release: Release) async throws -> URL {
        let (data, _) = try await session.data(from: release.tarball)

        // Verified BEFORE anything is unpacked. What comes out of this archive
        // is copied into the user's game folders, so an archive that is not
        // what the release says it is must never reach the disk it targets.
        if let checksumURL = release.checksum {
            let (checksumData, _) = try await session.data(from: checksumURL)
            let expected = Self.expectedChecksum(in: checksumData)
            let got = Self.sha256(of: data)
            guard let expected, expected.caseInsensitiveCompare(got) == .orderedSame else {
                throw MGVFBundleError.checksumMismatch(expected: expected ?? "none", got: got)
            }
        } else {
            console.warn("Release \(release.tag) publishes no checksum; the bundle cannot be verified")
        }

        return try unpack(data, tag: release.tag)
    }

    /// Unpack into a fresh directory and move it into place only once it is
    /// complete, so a partial extraction never reads as a usable bundle.
    func unpack(_ data: Data, tag: String) throws -> URL {
        let f = FileManager.default
        let staging = f.temporaryDirectory.appendingPathComponent("mgvf-\(UUID().uuidString)", isDirectory: true)
        try f.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? f.removeItem(at: staging) }

        let archive = staging.appendingPathComponent("bundle.tar.gz")
        try data.write(to: archive)

        let unpacked = staging.appendingPathComponent("x", isDirectory: true)
        try f.createDirectory(at: unpacked, withIntermediateDirectories: true)

        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", archive.path(percentEncoded: false),
                         "-C", unpacked.path(percentEncoded: false)]
        let errPipe = Pipe()
        tar.standardError = errPipe
        tar.standardOutput = FileHandle.nullDevice
        try tar.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            throw MGVFBundleError.extractionFailed(String(data: errData, encoding: .utf8) ?? "tar failed")
        }

        // The manifest is the marker of a complete bundle, the same way
        // .complete is for the staged codecs.
        guard f.fileExists(atPath: unpacked.appendingPathComponent("manifest.json").path(percentEncoded: false)) else {
            throw MGVFBundleError.manifestUnreadable("no manifest.json in the archive")
        }

        try f.createDirectory(at: root, withIntermediateDirectories: true)
        let target = directory(for: tag)
        if f.fileExists(atPath: target.path(percentEncoded: false)) {
            try? f.removeItem(at: target)
        }
        try f.moveItem(at: unpacked, to: target)
        return target
    }

    // MARK: - Small pure helpers, kept separate so they can be tested

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Read the digest out of a `shasum -a 256` line: "<hex>  <filename>".
    static func expectedChecksum(in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            if token.count == 64, token.allSatisfy({ $0.isHexDigit }) { return String(token) }
        }
        return nil
    }

    /// Compare tags like v4.8.10 and v4.8.2 by number, not by string.
    ///
    /// Lexicographically "v4.8.10" sorts before "v4.8.2", which would pick the
    /// older bundle as the newest cached one.
    static func compareTags(_ a: String, _ b: String) -> ComparisonResult {
        func parts(_ s: String) -> [Int] {
            s.drop(while: { !$0.isNumber })
                .split(whereSeparator: { !$0.isNumber })
                .compactMap { Int($0) }
        }
        let x = parts(a), y = parts(b)
        for i in 0 ..< max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
