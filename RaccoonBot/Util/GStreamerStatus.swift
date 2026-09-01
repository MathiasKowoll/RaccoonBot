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
    /// The decoder plugins this engine carries itself, by file name.
    ///
    /// Read from the engine rather than from a directory of our own. The
    /// codecs used to be staged beside the engine and pointed at through
    /// GST_PLUGIN_PATH; they now live inside it, which is what winevideo does
    /// and what removes the one thing that arrangement could never fix -- a
    /// plugin built against one GStreamer core loading beside another.
    let engineDecoders: [String]
    /// The version that engine reports.
    let engineVersion: String?

    static let frameworkPath = "/Library/Frameworks/GStreamer.framework/Versions/1.0"

    /// The version the decoders are meant to come from.
    ///
    /// Not "any 1.24". winevideo's own requirements name it exactly:
    ///
    ///   Official GStreamer 1.24.13 is required for Nioh, Nioh 2, Persona 5
    ///   Strikers, Returnal, Ghostwire Tokyo, and WMV/VC-1 titles such as RE
    ///   Engine games. It is optional for supported UE5 ElectraPlayer titles
    ///   and is not required for Ninja Gaiden 4's bundled VP9 path.
    ///
    /// It is needed when an engine is patched, which is when the decoders are
    /// copied out of it -- not while a game runs, by which time they are
    /// inside the engine.
    static let expectedVersion = "1.24.13"

    /// The plugins whose absence is a silent video rather than a preference.
    ///
    /// libgstlibav is the one CrossOver genuinely does not ship: VC-1, WMV,
    /// WMA and software VP9 all come from it. Matroska it does ship.
    static let wanted = ["libgstlibav"]

    var isUsable: Bool { !engineDecoders.isEmpty }

    /// The staging was built for a different build of this engine.
/// Where an engine keeps its own GStreamer plugins.
    ///
    /// 26 keeps one lib64 and does not name the architecture; 27 keeps one
    /// per architecture under lib. Do not invent a lib64 on a 27 engine: its
    /// own `wine` sets GST_PLUGIN_SYSTEM_PATH to whichever of these exists and
    /// REPLACES the value, so a half-filled lib64 would hide the twenty
    /// plugins it ships.
    static func pluginDirectory(ofEngineAt path: String) -> URL? {
        let app = URL(fileURLWithPath: path)
        guard let layout = EngineLayout.of(app) else { return nil }
        for arch in ["x86_64", "aarch64"] {
            let dir = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
                .appendingPathComponent(layout.moltenVKRoot(arch: arch))
                .appendingPathComponent("gstreamer-1.0")
            if FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)) { return dir }
        }
        return nil
    }

    static func read(engineAppPath: String?) -> GStreamerStatus {
        let f = FileManager.default
        var framework: Framework = .missing
        if f.fileExists(atPath: frameworkPath) {
            framework = .present(version: frameworkVersion() ?? "unknown")
        }

        guard let engineAppPath else {
            return GStreamerStatus(framework: framework, engineDecoders: [], engineVersion: nil)
        }

        var found: [String] = []
        if let dir = pluginDirectory(ofEngineAt: engineAppPath) {
            for name in wanted
            where f.fileExists(atPath: dir.appendingPathComponent("\(name).dylib").path(percentEncoded: false)) {
                found.append(name)
            }
        }
        let engineVersion = (NSDictionary(contentsOfFile: engineAppPath + "/Contents/Info.plist")?["CFBundleVersion"] as? String)
        return GStreamerStatus(framework: framework, engineDecoders: found, engineVersion: engineVersion)
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

    /// The installed framework, when it is not the version the decoders are
    /// meant to come from. Nil when it is, or when there is none.
    ///
    /// No longer part of anything the panel says, and deliberately so: since
    /// 0.2.0 the decoders travel inside this application, so which GStreamer
    /// somebody has installed does not affect what a patch imports. Kept
    /// because it is still a true reading of the machine and 1.24.13 remains
    /// the provenance of these binaries -- but it drives nothing, and a reader
    /// who finds it should not conclude that it does.
    var frameworkMismatch: String? {
        guard case .present(let version) = framework, version != Self.expectedVersion else { return nil }
        return version
    }

    /// What the panel says about this engine's decoders.
    ///
    /// It used to say which GStreamer would be imported into the engine at the
    /// next patch, and which version was wanted. That stopped being true in
    /// 0.2.0: the twelve libraries travel inside this application and
    /// `make-engine-copy.sh` installs them from its own Resources. Nothing
    /// RaccoonBot runs reads `/Library/Frameworks/GStreamer.framework` --
    /// measured, by following every script it invokes.
    ///
    /// So the installed framework is no longer part of the answer, and saying
    /// its version here invited somebody to go and change a thing that changes
    /// nothing. What is left is the question the panel is actually for: does
    /// this engine have the decoders, and what happens if it does not.
    var summary: String {
        if isUsable {
            return "This CrossOver carries libav — the decoders for VC-1, WMV, WMA and software VP9"
        }
        return "This CrossOver has no libav — VC-1, WMV, WMA and software VP9 will be silent "
             + "or black until it is patched again, which installs the decoders this application carries"
    }

    /// The decoders being in the engine is what makes a video play. The
    /// framework matters when the engine is patched, not while a game runs.
    var isOK: Bool { isUsable }
}
