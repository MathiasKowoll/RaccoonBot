//
//  EngineCodecs.swift
//  RaccoonBot
//
//  Putting the decoders CrossOver does not ship inside CrossOver.
//
//  This replaces the staging that used to sit beside the engine and be pointed
//  at through GST_PLUGIN_PATH. That worked, and carried one flaw it could not
//  fix: the staging symlinked a GStreamer core out of one engine while the
//  pointer lived in a bottle, and nothing tied the two together. A bottle
//  carried to a different engine then loaded two cores in one process. Inside
//  the engine there is nothing to mismatch -- the plugin resolves against the
//  GStreamer the engine already has.
//
//  The bits come from the user's own GStreamer framework, the same place the
//  staging took them from. Nothing is redistributed.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated enum EngineCodecs {

    /// The user's own install, borrowed from.
    static let frameworkLib = "/Library/Frameworks/GStreamer.framework/Versions/1.0/lib"

    /// The plugin CrossOver genuinely lacks: VC-1, WMV, WMA and software VP9
    /// all come from it. Matroska it ships, so we leave that alone.
    static let plugins = ["libgstlibav.dylib"]

    enum Failure: LocalizedError, Equatable {
        case frameworkMissing
        case pluginMissing(String)
        case noPluginDirectory(String)
        case write(String)

        var errorDescription: String? {
            switch self {
            case .frameworkMissing:
                return "GStreamer.framework is not installed, so there is nothing to take the decoders from"
            case .pluginMissing(let name):
                return "\(name) is not in this GStreamer install"
            case .noPluginDirectory(let engine):
                return "\(engine) has no GStreamer plugin directory to add to"
            case .write(let why):
                return "Could not write into the engine: \(why)"
            }
        }
    }

    struct Installed: Equatable, Sendable {
        let pluginDirectory: String
        let copied: [String]
    }

    /// Where the engine keeps its own plugins, and beside it, its libraries.
    ///
    /// Found, never created. A 26 engine keeps one lib64; a 27 keeps one per
    /// architecture under lib. Creating the other one is not a fallback: a 27
    /// engine's own `wine` sets GST_PLUGIN_SYSTEM_PATH to whichever directory
    /// exists and REPLACES the value, so a half-filled lib64 would hide the
    /// twenty plugins it ships.
    static func directories(ofEngineAt path: String) -> (plugins: URL, libs: URL)? {
        let app = URL(fileURLWithPath: path)
        guard let layout = EngineLayout.of(app) else { return nil }
        for arch in ["x86_64", "aarch64"] {
            let libs = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
                .appendingPathComponent(layout.moltenVKRoot(arch: arch))
            let plugins = libs.appendingPathComponent("gstreamer-1.0")
            if FileManager.default.fileExists(atPath: plugins.path(percentEncoded: false)) {
                return (plugins, libs)
            }
        }
        return nil
    }

    /// Everything the plugins need that the engine does not already have.
    ///
    /// Walked over the file that will actually be loaded. The engine's own
    /// copy of a library is the one that will be used, so its dependencies are
    /// the ones that matter -- and they differ: the framework carries libffi.7
    /// where an engine carries libffi.8. Reading the framework all the way
    /// down asks for a library nothing wants and misses the one it does.
    static func missing(from framework: URL, engineLibs: URL) -> [String] {
        let f = FileManager.default
        var needed: [String] = []
        var seen = Set(plugins)
        var queue = plugins.flatMap { dependencies(of: framework.appendingPathComponent("gstreamer-1.0/\($0)")) }

        while let name = queue.first {
            queue.removeFirst()
            guard seen.insert(name).inserted else { continue }
            let inEngine = engineLibs.appendingPathComponent(name)
            if f.fileExists(atPath: inEngine.path(percentEncoded: false)) {
                queue.append(contentsOf: dependencies(of: inEngine))
                continue
            }
            let inFramework = framework.appendingPathComponent(name)
            guard f.fileExists(atPath: inFramework.path(percentEncoded: false)) else { continue }
            needed.append(name)
            queue.append(contentsOf: dependencies(of: inFramework))
        }
        return needed.sorted()
    }

    /// The @rpath dependencies a Mach-O records. An absolute /usr/lib path is
    /// the system's and is already where the loader will look.
    static func dependencies(of url: URL) -> [String] {
        let path = url.path(percentEncoded: false)
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

    /// Put them in.
    ///
    /// Anything already there is moved aside as `.orig` before it is replaced,
    /// once, the same way every other resource this application copies into an
    /// engine is handled. An engine can always be put back.
    @discardableResult
    static func install(intoEngineAt path: String) throws -> Installed {
        let f = FileManager.default
        let framework = URL(fileURLWithPath: frameworkLib)
        guard f.fileExists(atPath: frameworkLib) else { throw Failure.frameworkMissing }
        guard let dirs = directories(ofEngineAt: path) else {
            throw Failure.noPluginDirectory(URL(fileURLWithPath: path).lastPathComponent)
        }
        for plugin in plugins {
            guard f.fileExists(atPath: framework.appendingPathComponent("gstreamer-1.0/\(plugin)").path(percentEncoded: false))
            else { throw Failure.pluginMissing(plugin) }
        }

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
            for plugin in plugins {
                try place(framework.appendingPathComponent("gstreamer-1.0/\(plugin)"),
                          dirs.plugins.appendingPathComponent(plugin))
                copied.append(plugin)
            }
            for name in missing(from: framework, engineLibs: dirs.libs) {
                try place(framework.appendingPathComponent(name),
                          dirs.libs.appendingPathComponent(name))
                copied.append(name)
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.write(error.localizedDescription)
        }

        console.log("codecs installed into \(URL(fileURLWithPath: path).lastPathComponent): \(copied.count) files")
        return Installed(pluginDirectory: dirs.plugins.path(percentEncoded: false), copied: copied)
    }
}
