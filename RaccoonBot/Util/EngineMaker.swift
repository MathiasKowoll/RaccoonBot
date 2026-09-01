//
//  EngineMaker.swift
//  RaccoonBot
//
//  Making the patched CrossOver is MacGameVideoFix's job now.
//
//  Both applications are built in the same place, so one of them owning the
//  engine means one thing to validate instead of two -- that was the reason,
//  and it is why this replaces a patcher of our own that worked. What arrives
//  from here declares itself in mgvf-origin.json; what the old patcher made
//  declared 26.3p0.1.x and nothing else, which is how you can tell which one
//  built any copy on a machine.
//
//  The script is the one carried inside this application, not a downloaded
//  one, so the engine and the thing that knows how to make it ship together.
//

import Foundation

nonisolated enum EngineMaker {

    enum Failure: LocalizedError, Equatable {
        case scriptMissing
        case noBottlesRoot
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .scriptMissing:
                return "This build does not carry MacGameVideoFix's engine script."
            case .noBottlesRoot:
                return "Choose where the bottles live before making the engine."
            case .refused(let why):
                return why
            }
        }
    }

    /// `make-engine-copy.sh` inside the embedded application.
    static var script: URL? {
        guard let url = MGVFBundle.embeddedDirectory?.appendingPathComponent("make-engine-copy.sh"),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return nil }
        return url
    }

    /// Make the copy, and answer where it landed.
    ///
    /// `--bottle-path` is passed always and never defaulted, because that key
    /// is the isolation: an engine without it does not run out of bottles, it
    /// falls through to stock CrossOver's root and works on somebody else's.
    /// The script refuses when it is absent, and this refuses before asking.
    ///
    /// The toolkit is deliberately not passed. Omitted, the copy keeps what
    /// CrossOver shipped, and the generation a title wants is installed at
    /// launch as it always has been. Handing over that half is a separate
    /// change with a decision behind it.
    static func make(from source: URL,
                     bottlesRoot: String,
                     name: String? = nil,
                     replacing: Bool = false,
                     progress: @escaping @Sendable (Double, String) -> Void) async throws -> URL {
        guard let script else { throw Failure.scriptMissing }
        guard !bottlesRoot.trimmingCharacters(in: .whitespaces).isEmpty else { throw Failure.noBottlesRoot }

        var arguments = [script.path(percentEncoded: false),
                         "--from", source.path(percentEncoded: false),
                         "--bottle-path", bottlesRoot,
                         "--no-autoupdate"]
        if let name { arguments += ["--name", name] }
        if replacing { arguments.append("--force") }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = arguments
        // The same narrow child environment the fix installers get, plus the
        // flag saying a program is asking rather than a person.
        var environment = ["HOME": NSHomeDirectory(),
                           "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                           "LC_ALL": "C",
                           "MGVF_FRONTEND": "RaccoonBot"]
        if let user = ProcessInfo.processInfo.environment["USER"] { environment["USER"] = user }
        task.environment = environment

        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        task.standardInput = FileHandle.nullDevice

        // Read as it goes rather than at the end. The copy is about a
        // gigabyte; a progress bar that only moves when the work is over is
        // not a progress bar.
        let collected = Collected()
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            let text = String(decoding: chunk, as: UTF8.self)
            collected.append(text)
            for line in text.split(whereSeparator: \.isNewline) {
                if let step = Self.step(in: String(line)) {
                    progress(Double(step) / 6.0, String(line).trimmingCharacters(in: .whitespaces))
                }
            }
        }

        try task.run()
        task.waitUntilExit()
        out.fileHandleForReading.readabilityHandler = nil
        let stdout = collected.text + String(decoding: (try? out.fileHandleForReading.readToEnd()) ?? Data(), as: UTF8.self)
        let stderr = String(decoding: (try? err.fileHandleForReading.readToEnd()) ?? Data(), as: UTF8.self)

        guard task.terminationStatus == 0, let made = Self.readyPath(in: stdout) else {
            let why = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.refused(why.isEmpty ? "The engine was not made and said nothing about why." : why)
        }
        console.log("engine made by MacGameVideoFix at \(made)")
        return URL(fileURLWithPath: made)
    }

    /// `[3/6] winegstreamer` -> 3.
    static func step(in line: String) -> Int? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let inside = line[line.index(after: line.startIndex)..<close]
        guard let slash = inside.firstIndex(of: "/") else { return nil }
        return Int(inside[inside.startIndex..<slash])
    }

    /// The script's last word on success: `ready: <path>`.
    static func readyPath(in output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline).reversed() where line.hasPrefix("ready: ") {
            return String(line.dropFirst("ready: ".count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Somewhere to put the output that a concurrent handler may write to.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var value = ""
        var text: String { lock.lock(); defer { lock.unlock() }; return value }
        func append(_ more: String) { lock.lock(); value += more; lock.unlock() }
    }
}
