//
//  BundledControllerBus.swift
//  RaccoonBot
//
//  The controller-bus set this application carries, and how it goes into an
//  engine and comes back out.
//
//  Four files MacGameVideoFix builds from the engine's own wine. Three are PE
//  and go to lib/wine/x86_64-windows/: winebus names the bus in its compatible
//  ids (mgvf-0002), setupapi answers CM_Get_Parent for a HID child
//  (mgvf-0003), and ntoskrnl refreshes a device's ids on every enumeration
//  (mgvf-0004). With them a Windows client learns that a DualSense is on
//  Bluetooth and speaks the pad's own protocol -- rumble, the PS button, the
//  touchpad and the adaptive triggers all work, measured on 2026-09-08.
//  Without them nothing on the Windows side ever learns the bus (see
//  DualSenseRoute), and the pad is sent through SDL as an Xbox-class pad with
//  some rumble and nothing else.
//
//  The fourth is winebus's unix half, a Mach-O rather than a PE, and it goes
//  to lib/wine/x86_64-unix/ -- a different directory, which is the one thing
//  about this set that cannot be guessed from the other three. It carries the
//  patches that act on the pad itself rather than on what Windows is told:
//  seizing a DualSense on Bluetooth so macOS and wine stop writing to it at
//  once (mgvf-0006), the two narrower answers for a pad that leaves
//  (mgvf-0007, mgvf-0008), and the vibration rewrite a title's own options ask
//  for (mgvf-0009). The two halves are built from one source tree and share a
//  struct, so a set with three of the four in place is not a supported
//  combination and the script says "broken" for it.
//
//  An improvement, not a fix. No title needs it and every one runs without
//  it, so unlike the media set it is a switch: on by default for an engine it
//  was built for, and off puts CodeWeavers' four files back. The switch runs
//  install-engine-controller.sh, which keeps each original beside its
//  replacement as .mgvf-stock, refuses an engine the set was not built for,
//  refuses while a bottle is up, and re-signs the engine after either
//  direction. Nothing here writes into an engine: the script does, and this
//  reads back what it says.
//
//  Verified before it runs, the way the codecs are, but not by hash. The
//  four are this project's own build rather than somebody else's binaries
//  carried under licence, and every rebuild changes their bytes; pinning them
//  would make every rebuild a change here too. What is checked is that all
//  five files are there, that each begins as the kind of binary it is meant to
//  be -- PE for the three, Mach-O for the unix half -- and that the stamp
//  beside them names an engine, and then, before anything is written, that the
//  engine is that one.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated enum BundledControllerBus {

    /// The installer. It names its files as `$HERE/<name>`, so they travel
    /// beside it and nowhere else.
    static let script = "install-engine-controller.sh"

    /// The three PE files, by the names they travel under. `engine-controller-`
    /// on purpose: the media installer picks its set by reading
    /// engine-built-for* and engine-winegstreamer*, and these must never be
    /// taken for one.
    static let peFiles = ["engine-controller-winebus.sys",
                          "engine-controller-setupapi.dll",
                          "engine-controller-ntoskrnl.exe"]

    /// winebus's unix half, which goes to a directory of its own. Named apart
    /// from the three because it is checked apart from them: it is a Mach-O
    /// library and does not begin as a PE does.
    static let unixFile = "engine-controller-winebus.so"

    /// All four, in the order the installer names them.
    static let files = peFiles + [unixFile]

    /// Which engine they were built for.
    static let stampFile = "engine-controller-built-for.json"

    /// The two bytes every PE begins with.
    static let peMagic = Data("MZ".utf8)

    /// The four a 64-bit Mach-O begins with: 0xfeedfacf, little endian. Four
    /// and not two, because the first two of them are shared with the 32-bit
    /// and the reversed-order forms, and the unix half is neither.
    static let machOMagic = Data([0xcf, 0xfa, 0xed, 0xfe])

    /// The stamp beside the files: the same four fields the media stamps carry.
    struct Stamp: Decodable, Equatable, Sendable {
        let app: String?
        let version: String?
        let wine: String?
        let patches: String?

        enum CodingKeys: String, CodingKey {
            case app = "engine_app"
            case version = "engine_version"
            case wine = "wine_build"
            case patches
        }

        /// Is this set meant for that engine?
        ///
        /// MGVFEnginePayload's rule: unknown is not yes. A stamp missing any of
        /// the three names nothing, and an engine that will not say its version
        /// or its wine gets nothing, because a winebus built from another wine
        /// does not degrade -- it fails in ways nobody would trace back here.
        ///
        /// The name is the field that tells a patched fork from stock: both
        /// report the same CFBundleVersion. It is compared against the bundle's
        /// own name and, failing that, against what the engine records it was
        /// copied from, the way install-engine-controller.sh does: a copy this
        /// project made is the same engine under another name, and the stamp
        /// names the original.
        func matches(_ engine: EngineIdentity) -> Bool {
            guard let app, let version, let wine else { return false }
            guard app == engine.app || app == engine.copiedFrom else { return false }
            guard let theirVersion = engine.version, theirVersion == version else { return false }
            guard let theirWine = engine.wine, theirWine == wine else { return false }
            return true
        }

        /// "CrossOver.app 26.3.0.39832", for a sentence.
        var described: String {
            [app, version].compactMap { $0 }.joined(separator: " ")
        }
    }

    /// Everything found, before anything runs.
    struct Payload {
        let script: URL
        let files: [URL]
        let stamp: Stamp
    }

    enum Failure: LocalizedError, Equatable {
        case notBundled(String)
        case notAPE(String)
        case notAMachO(String)
        case stampUnreadable(String)
        case wrongEngine(wanted: String, found: String)
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .notBundled(let name):
                return "\(name) is not in this application's bundle"
            case .notAPE(let name):
                return "\(name) is not a Windows binary: it does not begin with MZ"
            case .notAMachO(let name):
                return "\(name) is not a macOS library: it does not begin with a 64-bit Mach-O header"
            case .stampUnreadable(let why):
                return "The controller-bus set does not say which engine it was built for: \(why)"
            case .wrongEngine(let wanted, let found):
                return "The controller-bus set was built for \(wanted), and this engine is \(found)"
            case .refused(let why):
                return why
            }
        }
    }

    // MARK: - What we carry

    /// The script, the four files and the stamp, all present and all read
    /// before anything is run. A set that is wrong in one file is a wrong set,
    /// and the script would find that out after it had moved an original aside.
    static func verified(in root: URL? = MGVFBundle.embeddedDirectory) throws -> Payload {
        guard let root else { throw Failure.notBundled(script) }
        return try verified(inDirectory: root)
    }

    /// The same, of a folder named outright, so a test can read the payload in
    /// the source tree and a broken copy of it without building a bundle.
    static func verified(inDirectory root: URL) throws -> Payload {
        let f = FileManager.default
        let installer = root.appendingPathComponent(script)
        guard f.fileExists(atPath: installer.path(percentEncoded: false)) else {
            throw Failure.notBundled(script)
        }
        var found: [URL] = []
        for name in peFiles {
            let url = root.appendingPathComponent(name)
            guard let head = magic(of: url) else { throw Failure.notBundled(name) }
            guard head == peMagic else { throw Failure.notAPE(name) }
            found.append(url)
        }
        // The unix half, checked for what it is rather than for what the other
        // three are. Left out of the loop above rather than given a magic of
        // its own inside it: a set whose .so happened to begin with MZ would be
        // a PE in the place of a Mach-O, and the script would copy it into the
        // engine's x86_64-unix directory without looking.
        let unix = root.appendingPathComponent(unixFile)
        guard let unixHead = magic(of: unix, count: machOMagic.count) else { throw Failure.notBundled(unixFile) }
        guard unixHead == machOMagic else { throw Failure.notAMachO(unixFile) }
        found.append(unix)
        let stampURL = root.appendingPathComponent(stampFile)
        guard let data = f.contents(atPath: stampURL.path(percentEncoded: false)) else {
            throw Failure.notBundled(stampFile)
        }
        let stamp: Stamp
        do {
            stamp = try JSONDecoder().decode(Stamp.self, from: data)
        } catch {
            throw Failure.stampUnreadable(error.localizedDescription)
        }
        return Payload(script: installer, files: found, stamp: stamp)
    }

    /// The first bytes of a file; nil when there is no file to read. Two by
    /// default, which is a PE's whole magic; the unix half asks for four.
    static func magic(of url: URL, count: Int = 2) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: count)) ?? Data()
    }

    // MARK: - Running the script

    /// The argument list, verb included, every time.
    ///
    /// Unlike the per-title installers, this script's default verb is
    /// `install` -- so a verb dropped from one line of one caller would write
    /// into the engine. It is named on every call, and a read sets
    /// MGVF_STATUS_ONLY as well: structural beats positional, as in MGVFRunner.
    static func arguments(script: URL, engine: String, verb: MGVFRunner.Verb) -> [String] {
        [script.path(percentEncoded: false), engine, verb.argument ?? "install"]
    }

    /// Run the script against an engine and believe only what it says.
    ///
    /// Synchronous and blocking, like GStreamerStatus.read, and nonisolated
    /// for the same reason: the callers hand it to Task.detached, and a
    /// main-actor function would hop straight back. Not MGVFRunner.run, which
    /// serialises on a game folder and pins a bottle; this writes into an
    /// engine, which every bottle shares and no bottle argument describes.
    ///
    /// The timeout is MGVFRunner's. The script's slow step is re-signing the
    /// whole engine, and that was measured before the number was chosen: 1.0 s
    /// over a 1.1 GB copy on this machine, so 120 s is a hang, not slowness.
    static func run(_ verb: MGVFRunner.Verb,
                    onEngineAt engine: String,
                    script: URL,
                    timeout: Int = 120) throws -> MGVFResult {
        let process = Process()
        // bash with the script as an argument, as every other runner here: a
        // file inside a bundle need not carry its executable bit.
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments(script: script, engine: engine, verb: verb)

        // The same narrow environment EngineMaker gives make-engine-copy.sh,
        // plus the read-only valve for a read. MGVF_CX is not set: that names
        // the engine reg.exe runs under, and this script runs nothing.
        var environment = ["HOME": NSHomeDirectory(),
                           "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                           "LC_ALL": "C",
                           "MGVF_FRONTEND": "RaccoonBot"]
        if let user = ProcessInfo.processInfo.environment["USER"] { environment["USER"] = user }
        if !verb.writes { environment["MGVF_STATUS_ONLY"] = "1" }
        process.environment = environment

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        // Both pipes drained at once. Reading one to its end and then the other
        // deadlocks as soon as the process fills the one not being read, and
        // this script writes its notes to stderr and its answer to stdout.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        let readQueue = DispatchQueue(label: "controller-bus.read", attributes: .concurrent)
        group.enter()
        readQueue.async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        readQueue.async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        try process.run()
        var timedOut = false
        let deadline = DispatchWorkItem {
            if process.isRunning { timedOut = true; process.terminate() }
        }
        // Its own queue, never the one that waits below: a timer scheduled on
        // the queue that blocks in waitUntilExit fires when the wait is over.
        DispatchQueue(label: "controller-bus.timeout")
            .asyncAfter(deadline: .now() + .seconds(timeout), execute: deadline)
        process.waitUntilExit()
        deadline.cancel()
        group.wait()

        let stdout = String(decoding: outData, as: UTF8.self)
        let stderr = String(decoding: errData, as: UTF8.self)
        if timedOut { throw MGVFError.timedOut(script.lastPathComponent, seconds: timeout) }
        return MGVFResult(state: MGVFRunner.stateWord(in: stdout + "\n" + stderr),
                          stdout: stdout,
                          stderr: stderr,
                          exitCode: process.terminationStatus)
    }

    // MARK: - The three verbs

    /// What the engine holds, in the script's own word -- installed, broken or
    /// absent -- or nil when it could not be asked.
    static func status(ofEngineAt engine: String,
                       from root: URL? = MGVFBundle.embeddedDirectory) -> FixState? {
        guard let payload = try? verified(in: root) else { return nil }
        return (try? run(.status, onEngineAt: engine, script: payload.script))?.state
    }

    /// Put the set in, and answer what the engine then reports.
    ///
    /// The stamp is checked against the engine here as well as by the script.
    /// The script's refusal is the guard; this is the sentence on screen, and
    /// a mismatch is a fact about the engine rather than a fault of it.
    @discardableResult
    static func install(intoEngineAt engine: String,
                        from root: URL? = MGVFBundle.embeddedDirectory) throws -> FixState? {
        let payload = try verified(in: root)
        let identity = EngineIdentity(ofEngineAt: URL(fileURLWithPath: engine))
        guard payload.stamp.matches(identity) else {
            throw Failure.wrongEngine(wanted: payload.stamp.described, found: identity.described)
        }
        try believed(run(.install, onEngineAt: engine, script: payload.script))
        return (try? run(.status, onEngineAt: engine, script: payload.script))?.state
    }

    /// Take it out: the four .mgvf-stock originals go back and the script
    /// re-signs. Not checked against the stamp -- there is nothing to match,
    /// only originals to return -- and the script checks nothing there either.
    @discardableResult
    static func restore(fromEngineAt engine: String,
                        from root: URL? = MGVFBundle.embeddedDirectory) throws -> FixState? {
        let payload = try verified(in: root)
        try believed(run(.restore, onEngineAt: engine, script: payload.script))
        return (try? run(.status, onEngineAt: engine, script: payload.script))?.state
    }

    /// Exit zero, or the script's reason -- with the home path replaced, since
    /// the reason names the engine and the engine lives under it.
    private static func believed(_ result: MGVFResult) throws {
        guard result.exitCode == 0 else {
            let why = MGVFRunner.redacted(result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.refused(why.isEmpty ? "The script did not finish and said nothing about why." : why)
        }
    }
}
