//
//  GStreamerStatus.swift
//  RaccoonBot
//
//  Whether the machine has what the staged codecs are made from, and whether
//  the engine in use has them staged.
//
//  Two separate questions that look like one. The framework is the user's own
//  install, borrowed from; the staging is a directory built against one
//  specific CrossOver. A machine can have the first and not the second, and a
//  game whose video is silent looks identical either way.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Nonisolated on purpose, and it matters.
///
/// Reading this runs otool and blocks on waitUntilExit(). OptionsView already
/// hands it to a Task.detached to keep that off the main thread -- but a
/// main-actor-isolated function hops straight back onto the main actor when
/// called, so the detachment was decoration and the block was still there. The
/// crash it caused was fixed by moving the call out of the body getter; this is
/// the other half of that fix.
nonisolated struct GStreamerStatus: Sendable {
    enum Framework: Equatable, Sendable {
        case missing
        case present(version: String)
    }

    let framework: Framework
    /// Architectures staged for the engine in use, e.g. ["x86_64", "aarch64"].
    let staged: [String]
    /// What each staged architecture was built against, keyed by architecture.
    ///
    /// Per architecture, not one value for the pair. It used to keep only the
    /// first it found, so a machine with a fresh x86_64 staging and a stale
    /// aarch64 one reported "current" -- and the ARM bottle, the one that
    /// actually needed saying, was the half nobody was told about.
    let builtAgainst: [String: String]
    /// The version that engine actually runs, to notice drift.
    let engineVersion: String?

    static let frameworkPath = "/Library/Frameworks/GStreamer.framework/Versions/1.0"
    /// Where the fixes application keeps them, named after the engine bundle.
    static let stagingRoot = "Library/Application Support/MacGameVideoFix/gst-codecs"

    var isUsable: Bool { !staged.isEmpty }

    /// The staging was built for a different build of this engine.
    ///
    /// Not fatal on its own -- GStreamer keeps its ABI across 1.x -- but it is
    /// how a working setup quietly stops working after a CrossOver update, so
    /// it is worth saying.
    var isStale: Bool { !staleArchitectures.isEmpty }

    /// The staged architectures built against something the engine no longer is.
    var staleArchitectures: [String] {
        guard let engineVersion else { return [] }
        return staged.filter { arch in
            guard let built = builtAgainst[arch] else { return false }
            return built != engineVersion
        }
    }

    static func read(engineAppPath: String?) -> GStreamerStatus {
        let f = FileManager.default
        var framework: Framework = .missing
        if f.fileExists(atPath: frameworkPath) {
            framework = .present(version: frameworkVersion() ?? "unknown")
        }

        guard let engineAppPath else {
            return GStreamerStatus(framework: framework, staged: [],
                                   builtAgainst: [:], engineVersion: nil)
        }
        let bundle = URL(fileURLWithPath: engineAppPath).deletingPathExtension().lastPathComponent
        let slug = String(bundle.map { c in
            c.isLetter || c.isNumber || c == "." || c == "_" || c == "-" ? c : "-"
        })
        let root = f.homeDirectoryForCurrentUser
            .appendingPathComponent(stagingRoot)
            .appendingPathComponent(slug)

        var staged: [String] = []
        var builtAgainst: [String: String] = [:]
        for arch in ["x86_64", "aarch64"] {
            let dir = root.appendingPathComponent(arch)
            // .complete is written last, precisely so a half-built directory
            // never reads as ready.
            guard f.fileExists(atPath: dir.appendingPathComponent(".complete").path(percentEncoded: false)) else { continue }
            staged.append(arch)
            builtAgainst[arch] = (try? String(contentsOf: dir.appendingPathComponent(".built-against"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let engineVersion = (NSDictionary(contentsOfFile: engineAppPath + "/Contents/Info.plist")?["CFBundleVersion"] as? String)

        return GStreamerStatus(framework: framework, staged: staged,
                               builtAgainst: builtAgainst, engineVersion: engineVersion)
    }

    /// The series, read from the library's compatibility version.
    /// The plist lies about this on some builds; the binary does not.
    /// The GStreamer series a core library belongs to, e.g. 24 or 28.
    static func series(ofCoreAt path: String) -> Int? {
        guard let text = compatibilityLine(path) else { return nil }
        return text / 100
    }

    private static func compatibilityLine(_ lib: String) -> Int? {
        guard FileManager.default.fileExists(atPath: lib) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        p.arguments = ["-L", lib]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) where line.contains("libgstreamer-1.0.0.dylib") {
            if let range = line.range(of: "compatibility version ") {
                return Int(line[range.upperBound...].prefix(while: { $0.isNumber }))
            }
        }
        return nil
    }

    private static func frameworkVersion() -> String? {
        let lib = frameworkPath + "/lib/libgstreamer-1.0.0.dylib"
        guard FileManager.default.fileExists(atPath: lib) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        p.arguments = ["-L", lib]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) where line.contains("libgstreamer-1.0.0.dylib") {
            // "compatibility version 2405.0.0" -> 1.24.5
            if let range = line.range(of: "compatibility version ") {
                let number = line[range.upperBound...].prefix(while: { $0.isNumber })
                // The SERIES only, never the patch.
                //
                // The compatibility version does not map cleanly onto the
                // release: a framework published as 1.24.13 reports 2414, so
                // deriving "1.24.14" from it names a version that does not
                // exist -- and a download URL built from it answers 404.
                // Measured against gstreamer.freedesktop.org, where 1.24.13 is
                // the last of its line.
                if let n = Int(number), n > 100 {
                    return "1.\(n / 100)"
                }
            }
        }
        return nil
    }

    var summary: String {
        switch framework {
        case .missing:
            return "GStreamer.framework is not installed — video fixes that need a decoder will not work"
        case .present(let version):
            if staged.isEmpty {
                return "GStreamer \(version) is installed, but no codecs are staged for this engine"
            }
            if isStale {
                let stale = staleArchitectures
                let built = stale.compactMap { builtAgainst[$0] }.first ?? "another build"
                let which = stale.count == staged.count ? "Codecs" : "\(stale.joined(separator: " and ")) codecs"
                return "\(which) staged for \(built) — this engine now runs \(engineVersion ?? "a different one")"
            }
            return "GStreamer \(version), codecs staged for \(staged.joined(separator: " and "))"
        }
    }

    var isOK: Bool {
        if case .present = framework { return isUsable && !isStale }
        return false
    }
}
