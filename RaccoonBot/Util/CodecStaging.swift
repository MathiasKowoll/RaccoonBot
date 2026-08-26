//
//  CodecStaging.swift
//  RaccoonBot
//
//  Building the directory of decoders a bottle is pointed at.
//
//  This is the part of the fork that is the fork. CrossOver ships a GStreamer
//  core and most of its plugins, but not libgstlibav (VC-1, WMV, WMA, software
//  VP9) and not libgstmatroska (WebM). A game whose cutscene needs either gets
//  audio over a black rectangle, or exits.
//
//  The obvious fix -- drop the official GStreamer framework into the engine --
//  is the one the patcher used to do, and it is wrong: two cores in one process
//  is a dyld crash, and the workaround was a hand-written list of ~85 dylibs to
//  delete, each with `try?`, so a CrossOver that adds one brings the crash back
//  silently.
//
//  So instead: the two missing plugins are copied out of the user's own
//  framework into a directory of their own, everything they need that the
//  engine ALREADY HAS is symlinked back to the engine's copy, and only what the
//  engine genuinely lacks -- FFmpeg, zlib, bzip2 -- is copied. Exactly one
//  GStreamer core is ever loaded, and it is the engine's. Nothing inside the
//  engine is touched.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated enum CodecStaging {

    /// The user's own GStreamer install. Borrowed from, never redistributed.
    static let frameworkLib = "/Library/Frameworks/GStreamer.framework/Versions/1.0/lib"

    /// The two CrossOver genuinely does not ship.
    static let plugins = ["libgstlibav.dylib", "libgstmatroska.dylib"]

    /// How one library gets into the staging.
    enum Placement: String, Equatable, Sendable {
        /// The engine has it: link to the engine's, so one copy is loaded.
        case link
        /// The engine does not have it: copy it out of the framework.
        case copy
    }

    enum Failure: LocalizedError, Equatable {
        case frameworkMissing
        case pluginMissing(String)
        case engineHasNoLibraries(arch: String)
        case unwritable(String)

        var errorDescription: String? {
            switch self {
            case .frameworkMissing:
                return "GStreamer.framework is not installed, so there is nothing to stage from"
            case .pluginMissing(let name):
                return "\(name) is not in this GStreamer install"
            case .engineHasNoLibraries(let arch):
                return "This CrossOver has no \(arch) libraries"
            case .unwritable(let why):
                return "Could not write the staged codecs: \(why)"
            }
        }
    }

    struct Staged: Equatable, Sendable {
        let arch: String
        let copied: [String]
        let linked: [String]
        var total: Int { copied.count + linked.count }
    }

    // MARK: - Where things live

    /// The directory name for an engine.
    ///
    /// Named after the bundle, not the version: a patched copy declares the
    /// CFBundleVersion of the CrossOver it was copied from, so the version
    /// cannot tell a patched engine from its original.
    static func slug(forEngineAt path: String) -> String {
        let bundle = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return String(bundle.map { c in
            c.isLetter || c.isNumber || c == "." || c == "_" || c == "-" ? c : "-"
        })
    }

    /// Kept under MacGameVideoFix's name, not ours.
    ///
    /// The name is now wrong -- this application builds the directory and this
    /// application reads it. It stays because stagedCodecPath and
    /// GStreamerStatus both hardcode this path, and because moving it would
    /// orphan every staging already on a user's disk. Renaming it is a
    /// migration, not a constant.
    ///
    /// The `.map` file MacGameVideoFix leaves at the root is deliberately not
    /// written or removed here: nothing in this application reads it, and
    /// rewriting a file whose contract belongs to something else is how two
    /// programs start disagreeing about one directory.
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacGameVideoFix/gst-codecs")
    }

    /// `into` exists so a test can build a real staging somewhere disposable.
    /// Everything else passes the default, which is the directory
    /// stagedCodecPath reads.
    static func directory(engineAppPath: String, arch: String, into base: URL? = nil) -> URL {
        (base ?? root).appendingPathComponent(slug(forEngineAt: engineAppPath))
            .appendingPathComponent(arch)
    }

    /// The engine's own library directory for one architecture.
    ///
    /// 26 keeps one set in lib64 and does not name the architecture; 27 keeps
    /// one per architecture under lib. Same directory EngineLayout already
    /// describes for MoltenVK, because it is the same directory.
    static func engineLibrary(engineAppPath: String, arch: String) -> URL? {
        let app = URL(fileURLWithPath: engineAppPath)
        guard let layout = EngineLayout.of(app) else { return nil }
        let dir = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
            .appendingPathComponent(layout.moltenVKRoot(arch: arch))
        return FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)) ? dir : nil
    }

    /// The directory a bottle's GST_PLUGIN_PATH is pointed at.
    ///
    /// The one spelling. It used to be built independently here and in
    /// stagedCodecPath, and the two drifted: one grew a trailing slash from
    /// appendingPathComponent consulting the file system, the other did not,
    /// so the same directory went into cxbottle.conf two different ways.
    static func pluginPath(engineAppPath: String, arch: String, into base: URL? = nil) -> String {
        directory(engineAppPath: engineAppPath, arch: arch, into: base)
            .path(percentEncoded: false) + "/gstreamer-1.0"
    }

    /// Where this engine should keep its GStreamer plugin cache.
    ///
    /// One per engine and architecture. GStreamer's default is
    /// ~/.cache/gstreamer-1.0/registry.<arch>.bin -- a single file shared by
    /// the user's own framework and by every engine on the machine. Two
    /// engines with different plugin sets, which is exactly what staging
    /// creates, take turns writing one another's view of what exists. Nothing
    /// checks, and the symptom is a decoder that is there and then is not.
    static func registryPath(engineAppPath: String, arch: String, into base: URL? = nil) -> String {
        directory(engineAppPath: engineAppPath, arch: arch, into: base)
            .path(percentEncoded: false) + "/registry.bin"
    }

    /// Which architectures this engine can actually be staged for.
    static func architectures(ofEngineAt path: String) -> [String] {
        ["x86_64", "aarch64"].filter { engineLibrary(engineAppPath: path, arch: $0) != nil }
    }

    // MARK: - The closure, kept pure so it can be tested without a GStreamer install

    /// Everything the plugins need, and how each piece gets there.
    ///
    /// Walked over the file that will ACTUALLY be used, not the framework's
    /// copy of it. It matters: the framework carries libffi.7 and the engine
    /// carries libffi.8, and it is the engine's libgobject that will be loaded,
    /// so it is the engine's libffi that has to be found. Reading the
    /// framework's copy all the way down stages a library nothing asks for and
    /// misses the one that is wanted.
    static func closure(from roots: [String],
                        dependencies: (String) -> [String],
                        resolve: (String) -> (path: String, placement: Placement)?) -> [String: Placement] {
        var found: [String: Placement] = [:]
        var queue = roots.flatMap(dependencies)
        var visited = Set(roots)

        while let name = queue.first {
            queue.removeFirst()
            guard !visited.contains(name) else { continue }
            visited.insert(name)
            guard let (path, placement) = resolve(name) else { continue }
            found[name] = placement
            queue.append(contentsOf: dependencies(path))
        }
        return found
    }

    /// The @rpath dependencies a Mach-O records.
    ///
    /// Only @rpath ones: an absolute /usr/lib path is the system's and is
    /// already where the loader will look.
    static func dependencies(of path: String) -> [String] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        p.arguments = ["-L", path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).dropFirst().compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("@rpath/"),
                  let name = t.split(separator: " ").first?.dropFirst("@rpath/".count)
            else { return nil }
            return String(name)
        }
    }

    // MARK: - Building it

    /// Build the staging for one engine and one architecture.
    ///
    /// Blocking, and deliberately not main-actor: it runs otool a few dozen
    /// times and copies about 35MB.
    @discardableResult
    static func stage(engineAppPath: String, arch: String, into base: URL? = nil) throws -> Staged {
        let f = FileManager.default
        guard f.fileExists(atPath: frameworkLib) else { throw Failure.frameworkMissing }
        guard let engineLib = engineLibrary(engineAppPath: engineAppPath, arch: arch) else {
            throw Failure.engineHasNoLibraries(arch: arch)
        }
        let fw = URL(fileURLWithPath: frameworkLib)
        for plugin in plugins {
            guard f.fileExists(atPath: fw.appendingPathComponent("gstreamer-1.0/\(plugin)").path(percentEncoded: false))
            else { throw Failure.pluginMissing(plugin) }
        }

        let dest = directory(engineAppPath: engineAppPath, arch: arch, into: base)
        let marker = dest.appendingPathComponent(".complete")

        do {
            // Struck first, so an interrupted restage reads as unfinished
            // rather than as a staging that is ready and is not.
            try? f.removeItem(at: marker)
            try? f.removeItem(at: dest)
            try f.createDirectory(at: dest.appendingPathComponent("gstreamer-1.0"),
                                  withIntermediateDirectories: true)
            try f.createDirectory(at: dest.appendingPathComponent("lib"),
                                  withIntermediateDirectories: true)

            for plugin in plugins {
                try f.copyItem(at: fw.appendingPathComponent("gstreamer-1.0/\(plugin)"),
                               to: dest.appendingPathComponent("gstreamer-1.0/\(plugin)"))
            }

            let placements = closure(
                from: plugins.map { fw.appendingPathComponent("gstreamer-1.0/\($0)").path(percentEncoded: false) },
                dependencies: dependencies(of:),
                resolve: { name in
                    let inEngine = engineLib.appendingPathComponent(name).path(percentEncoded: false)
                    if f.fileExists(atPath: inEngine) { return (inEngine, .link) }
                    let inFramework = fw.appendingPathComponent(name).path(percentEncoded: false)
                    if f.fileExists(atPath: inFramework) { return (inFramework, .copy) }
                    return nil
                })

            var copied: [String] = [], linked: [String] = []
            for (name, placement) in placements.sorted(by: { $0.key < $1.key }) {
                let to = dest.appendingPathComponent("lib/\(name)")
                switch placement {
                case .link:
                    try f.createSymbolicLink(at: to,
                                             withDestinationURL: engineLib.appendingPathComponent(name))
                    linked.append(name)
                case .copy:
                    try f.copyItem(at: fw.appendingPathComponent(name), to: to)
                    copied.append(name)
                }
            }

            // What it was built against, so drift can be noticed later.
            let version = (NSDictionary(contentsOfFile: engineAppPath + "/Contents/Info.plist")?["CFBundleVersion"] as? String) ?? "unknown"
            try version.write(to: dest.appendingPathComponent(".built-against"),
                              atomically: true, encoding: .utf8)
            // Last, always. GStreamerStatus and stagedCodecPath both treat this
            // file as the whole answer to "is it ready".
            try ISO8601DateFormatter().string(from: Date())
                .write(to: marker, atomically: true, encoding: .utf8)

            console.log("staged \(copied.count + linked.count) libraries for \(slug(forEngineAt: engineAppPath))/\(arch)")
            return Staged(arch: arch, copied: copied, linked: linked)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.unwritable(error.localizedDescription)
        }
    }

    /// Build it for every architecture the engine has.
    ///
    /// Reports per architecture rather than as one pass/fail: an engine can
    /// have both and only one of them go wrong, and "it failed" would hide
    /// which half still works.
    static func stageAll(engineAppPath: String,
                         into base: URL? = nil,
                         onProgress: ((String) -> Void)? = nil) -> (staged: [Staged], failures: [(arch: String, reason: String)]) {
        var staged: [Staged] = []
        var failures: [(arch: String, reason: String)] = []
        for arch in architectures(ofEngineAt: engineAppPath) {
            onProgress?("Staging codecs for \(arch)…")
            do { staged.append(try stage(engineAppPath: engineAppPath, arch: arch, into: base)) }
            catch {
                let reason = (error as? Failure)?.errorDescription ?? error.localizedDescription
                console.error("staging \(arch) failed: \(reason)")
                failures.append((arch: arch, reason: reason))
            }
        }
        return (staged, failures)
    }
}
