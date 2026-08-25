//
//  GStreamerInstall.swift
//  Procyon
//
//  Fetches the official GStreamer runtime package and hands it to the system
//  installer.
//
//  Not redistributed: the bits come from gstreamer.freedesktop.org and the
//  install is approved by the user, because the package writes into
//  /Library/Frameworks and needs an administrator. What this removes is the
//  hunting -- three packages are published side by side per version and only
//  one of them is the runtime.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import AppKit

enum GStreamerInstallError: LocalizedError {
    case listingUnavailable(String)
    case noSuitableVersion(oldestSeries: Int)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .listingUnavailable(let why):
            return "Could not reach gstreamer.freedesktop.org: \(why)"
        case .noSuitableVersion(let series):
            return "No GStreamer 1.\(series) package is published any more"
        case .downloadFailed(let why):
            return "The GStreamer download failed: \(why)"
        }
    }
}

struct GStreamerInstall {
    static let base = "https://gstreamer.freedesktop.org/data/pkg/osx"

    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    /// The runtime package. Its neighbours -- `devel` and `debug` -- are not it,
    /// and picking the wrong one is the mistake this exists to prevent.
    static func packageURL(version: String) -> URL {
        URL(string: "\(base)/\(version)/gstreamer-1.0-\(version)-universal.pkg")!
    }

    /// Which version to offer, given what is published and which engines are in
    /// use.
    ///
    /// The newest release whose SERIES is not newer than the oldest engine on
    /// the machine. GStreamer grew its ABI by 200 symbols between 1.24 and
    /// 1.28 and removed none, so an older plugin under a newer core resolves
    /// and the reverse does not: a 1.28 plugin on CrossOver 26.3's 1.24.5 core
    /// fails to load and is blacklisted, and the only symptom is silent video.
    ///
    /// So this holds someone back only while something is holding them back.
    /// Drop the old engine and the answer moves on by itself.
    static func chooseVersion(available: [String], engineSeries: [Int]) -> String? {
        guard let oldest = engineSeries.min() else { return nil }
        let candidates = available.compactMap { v -> (String, [Int])? in
            let parts = v.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return (v, parts)
        }
        return candidates
            .filter { $0.1[1] <= oldest }
            .max { a, b in compare(a.1, b.1) }?
            .0
    }

    private static func compare(_ a: [Int], _ b: [Int]) -> Bool {
        for i in 0 ..< max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0, r = i < b.count ? b[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    /// Versions published on the site, read from its directory listing.
    ///
    /// Read rather than derived. A framework published as 1.24.13 reports a
    /// compatibility version that decodes to 1.24.14, and a URL built from
    /// that answers 404 -- so the list has to come from the site.
    func publishedVersions() async throws -> [String] {
        var request = URLRequest(url: URL(string: "\(Self.base)/")!)
        request.timeoutInterval = 20
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw GStreamerInstallError.listingUnavailable("HTTP \(http.statusCode)")
            }
            return Self.parseVersions(String(data: data, encoding: .utf8) ?? "")
        } catch let error as GStreamerInstallError {
            throw error
        } catch {
            throw GStreamerInstallError.listingUnavailable(error.localizedDescription)
        }
    }

    static func parseVersions(_ html: String) -> [String] {
        var found: Set<String> = []
        var current = ""
        for character in html {
            if character.isNumber || character == "." {
                current.append(character)
            } else {
                if current.split(separator: ".").count == 3,
                   current.split(separator: ".").allSatisfy({ Int($0) != nil }),
                   current.hasPrefix("1.") {
                    found.insert(current)
                }
                current = ""
            }
        }
        return Array(found)
    }

    /// Download the package and let the system installer take it from there.
    ///
    /// It is opened, not run: installing into /Library/Frameworks needs an
    /// administrator, and that prompt belongs to the user rather than to us.
    func downloadAndOpen(version: String) async throws {
        let url = Self.packageURL(version: version)
        do {
            let (temporary, response) = try await session.download(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw GStreamerInstallError.downloadFailed("HTTP \(http.statusCode)")
            }
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            await MainActor.run { NSWorkspace.shared.open(destination) }
        } catch let error as GStreamerInstallError {
            throw error
        } catch {
            throw GStreamerInstallError.downloadFailed(error.localizedDescription)
        }
    }
}
