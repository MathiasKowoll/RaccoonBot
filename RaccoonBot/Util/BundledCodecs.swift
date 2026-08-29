//
//  BundledCodecs.swift
//  RaccoonBot
//
//  The decoders this application carries and installs itself.
//
//  Before this, the plugins came out of whatever GStreamer the user had
//  installed under /Library/Frameworks. That route has two faults and both
//  are quiet. On a machine with no framework nothing is copied and the patch
//  finishes reporting success. On a machine with some other 1.24.x the copy
//  succeeds and the wrong build is loaded -- the plugin does not refuse, it
//  loads, and the failure arrives much later as a cutscene that plays black.
//
//  So we carry them. Twelve files, taken verbatim from CrossOver-winevideo-0.5
//  and pinned by hash, which makes this application a redistributor of other
//  people's LGPL and BSD binaries. `codecs/CODEC-LICENCES.md` travels in the
//  bundle beside them for exactly that reason: the notices and the offer of
//  corresponding source are part of shipping these, not paperwork to produce
//  if somebody asks.
//

import CryptoKit
import Foundation

nonisolated enum BundledCodecs {

    /// The folder inside our own Resources, copied in whole by the build.
    static let resourceDirectory = "codecs"

    /// The notices that have to travel with the binaries.
    static let licenceFile = "CODEC-LICENCES.md"

    struct Item: Sendable, Equatable, Hashable {
        let name: String
        /// A GStreamer plugin belongs beside the engine's own plugins; a
        /// library belongs one level up, where the loader will look for it.
        let isPlugin: Bool
        let sha256: String
    }

    /// What we carry, and what each file has to be.
    ///
    /// The hashes are the ones recorded in CODEC-LICENCES.md, which travels in
    /// the same folder; `BundledCodecsTests` reads that table and requires it
    /// to agree with this one, so the two cannot drift apart unnoticed.
    ///
    /// Note what is deliberately absent: a destination path. The licence table
    /// writes these as `lib64/...` because that is where they sit in a 26
    /// engine, but lib64 is a fact about that generation and not about the
    /// file. Where each one goes is asked of the engine at install time.
    static let items: [Item] = [
        Item(name: "libgstlibav.dylib", isPlugin: true,
             sha256: "b748843c176a4715d111036674cf6859d8f43fc6b4e98a3abaa5750d57233ac9"),
        Item(name: "libgstmatroska.dylib", isPlugin: true,
             sha256: "9e7d08da9252f30113732981c214323faa13f12648cf3a6bbb48ee88bce0c1b2"),
        Item(name: "libgstvpx.dylib", isPlugin: true,
             sha256: "2afef0cee64b0bd606660aaf2294dae7d68049e235814fa99dbd3fd1f1b7c14c"),
        Item(name: "libavcodec.60.dylib", isPlugin: false,
             sha256: "ea7e2f3022e14d5c1d4787c00f626f5185a15b76ac88ae0f5e74a297608e2601"),
        Item(name: "libavfilter.9.dylib", isPlugin: false,
             sha256: "ce46cb51430efb4152703e7b0b80361e6caaa90b746e5a7c1e49de3f7e901b6e"),
        Item(name: "libavformat.60.dylib", isPlugin: false,
             sha256: "e44d159a8b96360112bd5fd4c62f7a7d470b884b16452fc7b884330d2a5a62b3"),
        Item(name: "libavutil.58.dylib", isPlugin: false,
             sha256: "fac49f53ec9a7cdaee223d30ecf9038c372a3c88b3e62276c428cfdf7488bf33"),
        Item(name: "libbz2.1.dylib", isPlugin: false,
             sha256: "70e19fe6eb3cb98d24369de344622a4228cadb4dd6fc6888dcb404b14568685d"),
        Item(name: "liborc-0.4.0.dylib", isPlugin: false,
             sha256: "b79f70b7bcdf71fdb2b1a5b2155d3efc7766a6ef0f9b451437be9d2d0b363064"),
        Item(name: "libswresample.4.dylib", isPlugin: false,
             sha256: "6e705fe847c804dab38a1f408aae70c369ea7678b8ef568b4583d414e10ffad7"),
        Item(name: "libvpx.9.dylib", isPlugin: false,
             sha256: "516301130035afb711a427b4f4d9e53b9b7a16a34b0440ea0f0921d0b2d20b02"),
        Item(name: "libz.1.dylib", isPlugin: false,
             sha256: "ed695ed72de58ce69632c86b40dacb8e2bf61db469efccc2e99da62b5825c8fa"),
    ]

    enum Failure: LocalizedError, Equatable {
        case notBundled(String)
        case wrongContents(name: String, expected: String, found: String)
        case noPluginDirectory(String)
        case write(String)

        var errorDescription: String? {
            switch self {
            case .notBundled(let name):
                return "\(name) is not in this application's bundle"
            case .wrongContents(let name, let expected, let found):
                return "\(name) is not the file it should be: expected \(expected.prefix(12)), found \(found.prefix(12))"
            case .noPluginDirectory(let engine):
                return "\(engine) has no GStreamer plugin directory to install into"
            case .write(let why):
                return "Could not install the decoders: \(why)"
            }
        }
    }

    /// Our own folder, wherever the bundle put it.
    static func directory(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceDirectory, withExtension: nil)
    }

    /// Where a file of ours sits inside our folder. Plugins keep the
    /// `gstreamer-1.0` subfolder they arrived in.
    static func location(of item: Item, under root: URL) -> URL {
        item.isPlugin
            ? root.appendingPathComponent("gstreamer-1.0").appendingPathComponent(item.name)
            : root.appendingPathComponent(item.name)
    }

    /// Read a file all the way through and say what it is.
    ///
    /// Chunked because one of these is thirteen megabytes and there is no
    /// reason to hold it in memory to answer a question about it.
    static func digest(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Every file we carry, read and confirmed to be what the table says.
    ///
    /// All twelve are checked before any of them is copied. A payload that is
    /// wrong in one file is wrong, and half of it in an engine is worse than
    /// none of it: the engine's own plugins would then be loaded beside three
    /// libraries from somewhere else.
    static func verified(in bundle: Bundle = .main) throws -> [(item: Item, url: URL)] {
        guard let root = directory(in: bundle) else { throw Failure.notBundled(resourceDirectory) }
        return try verified(inDirectory: root)
    }

    /// The same, of a folder named outright, so a test can read the payload in
    /// the source tree and a corrupted copy of it without building a bundle.
    static func verified(inDirectory root: URL) throws -> [(item: Item, url: URL)] {
        var checked: [(item: Item, url: URL)] = []
        for item in items {
            let url = location(of: item, under: root)
            guard let found = digest(of: url) else { throw Failure.notBundled(item.name) }
            guard found == item.sha256 else {
                throw Failure.wrongContents(name: item.name, expected: item.sha256, found: found)
            }
            checked.append((item, url))
        }
        return checked
    }

    /// Put them into an engine.
    ///
    /// The destination is asked of the engine rather than assumed: a 26 keeps
    /// one lib64, a 27 keeps one directory per architecture under lib, and
    /// creating the wrong one is not a harmless miss. A 27's own `wine` sets
    /// GST_PLUGIN_SYSTEM_PATH to whichever directory exists and *replaces* the
    /// value, so a lib64 we invented would hide the twenty plugins it ships.
    ///
    /// Anything already in place is moved aside as `.orig`, once, the same way
    /// every other resource copied into an engine is handled.
    @discardableResult
    static func install(intoEngineAt path: String, from bundle: Bundle = .main) throws -> EngineCodecs.Installed {
        guard let root = directory(in: bundle) else { throw Failure.notBundled(resourceDirectory) }
        return try install(intoEngineAt: path, from: root)
    }

    @discardableResult
    static func install(intoEngineAt path: String, from root: URL) throws -> EngineCodecs.Installed {
        // Everything is read and confirmed before anything is written, so a
        // payload that is wrong in one file leaves the engine as it was.
        let payload = try verified(inDirectory: root)
        guard let dirs = EngineCodecs.directories(ofEngineAt: path) else {
            throw Failure.noPluginDirectory(URL(fileURLWithPath: path).lastPathComponent)
        }

        let f = FileManager.default
        func place(_ from: URL, _ to: URL) throws {
            if f.fileExists(atPath: to.path(percentEncoded: false)) {
                let orig = to.appendingPathExtension("orig")
                if f.fileExists(atPath: orig.path(percentEncoded: false)) {
                    try f.removeItem(at: to)
                } else {
                    try f.moveItem(at: to, to: orig)
                }
            }
            try f.copyItem(at: from, to: to)
        }

        var copied: [String] = []
        do {
            for (item, url) in payload {
                let into = item.isPlugin ? dirs.plugins : dirs.libs
                try place(url, into.appendingPathComponent(item.name))
                copied.append(item.name)
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.write(error.localizedDescription)
        }

        console.log("codecs installed into \(URL(fileURLWithPath: path).lastPathComponent): "
                    + "\(copied.count) files, all matching CODEC-LICENCES.md")
        return EngineCodecs.Installed(pluginDirectory: dirs.plugins.path(percentEncoded: false), copied: copied)
    }
}
