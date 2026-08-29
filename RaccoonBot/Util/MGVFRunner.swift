//
//  MGVFRunner.swift
//  RaccoonBot
//
//  Runs a MacGameVideoFix installer and believes only what it can read back.
//
//  NOT safeShell. That interpolates the whole command into `zsh -c`, sends
//  stdout and stderr to nullDevice, and returns without waitUntilExit -- so an
//  installer that moved the original DLL aside and then failed to copy the
//  proxy is indistinguishable from one that succeeded. That is precisely the
//  state these scripts call `half`, and precisely the state a caller must not
//  mistake for success.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// What an installer says about a game folder.
///
/// Exactly these four words, and nothing else is an answer. A script that
/// cannot determine the state refuses instead of guessing -- so `unknown` here
/// means the run failed, never that the fix is absent.
enum FixState: String {
    case installed
    case broken
    case half
    case absent
}

struct MGVFResult {
    let state: FixState?
    let stdout: String
    let stderr: String
    let exitCode: Int32
    /// True when the script ran and answered. A false here with a non-nil
    /// state cannot happen; a true with a nil state means it ran and refused.
    var ran: Bool { exitCode != -1 }
}

enum MGVFError: LocalizedError {
    case notExecutable(String)
    case timedOut(String, seconds: Int)
    case busy(String)

    var errorDescription: String? {
        switch self {
        case .notExecutable(let p): return "Cannot run \(p)"
        case .timedOut(let p, let s): return "\(p) did not finish within \(s)s and was stopped"
        case .busy(let p): return "Another operation is already running on \(p)"
        }
    }
}

/// Runs the installers, one at a time, and never two on the same folder.
///
/// Serialised for a reason that is not hypothetical: the MacGameVideoFix
/// application can write the same game folder, and none of the installers take
/// a lock. Two writers renaming the same carrier DLL is how a folder ends up
/// with the proxy saved as the original.
final class MGVFRunner: @unchecked Sendable {
    static let shared = MGVFRunner()

    private let queue = DispatchQueue(label: "mgvf.runner")
    /// Separate from `queue` on purpose. The timeout used to be scheduled on
    /// the same serial queue that `execute` blocks with waitUntilExit, so it
    /// could not fire until the very thing it was meant to interrupt had
    /// finished. A hanging installer would have hung the app, quietly, and the
    /// test written to prove otherwise is what found it.
    private let timerQueue = DispatchQueue(label: "mgvf.timeout")
    private var busyFolders = Set<String>()
    private let busyLock = NSLock()

    private init() {}

    // MARK: - Verbs
    //
    // Install by OMITTING the verb. Not `--install`: install-ng4-fix.sh reads
    // `ACTION="${2:-install}"` and its case accepts a bare `install`, so a
    // caller passing `--install` prints the usage and exits 1 without touching
    // anything -- and under a runner that ignored exit codes, silently.
    //
    // MGVF_STATUS_ONLY is not a read-only guarantee either: that same script is
    // the one of eleven that does not read it, so with the variable set and no
    // verb it performs a real installation. Only `--status` is safe to ask.
    enum Verb {
        case install
        case status
        case restore

        var argument: String? {
            switch self {
            case .install: return nil
            case .status:  return "--status"
            case .restore: return "--restore"
            }
        }

        var writes: Bool { self != .status }
    }

    /// Run one installer against whatever it takes.
    ///
    /// - Parameters:
    ///   - script: absolute path to the install-*.sh, with its DLL and pe.pl
    ///     beside it -- the scripts resolve siblings through `dirname "$0"`.
    ///   - target: what the installer is given as its first argument. Almost
    ///     always the folder the game is installed in; for a bottle-scoped fix
    ///     it is the bottle. The serialisation below is right either way -- two
    ///     writers on one bottle registry is as bad as two on one game folder.
    ///   - timeout: seconds before the process is stopped. Installing copies a
    ///     few hundred KB and asks the registry, so this is a hang, not slowness.
    func run(script: String,
             target gameFolder: String,
             bottle: String? = nil,
             verb: Verb,
             timeout: Int = 120) async throws -> MGVFResult {
        guard FileManager.default.isExecutableFile(atPath: script) else {
            throw MGVFError.notExecutable(script)
        }
        if verb.writes {
            busyLock.lock()
            defer { busyLock.unlock() }
            guard !busyFolders.contains(gameFolder) else { throw MGVFError.busy(gameFolder) }
            busyFolders.insert(gameFolder)
        }
        defer {
            if verb.writes {
                busyLock.lock(); busyFolders.remove(gameFolder); busyLock.unlock()
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try self.execute(script: script,
                                                  gameFolder: gameFolder,
                                                  bottle: bottle,
                                                  verb: verb,
                                                  timeout: timeout)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - The actual run

    private func execute(script: String,
                         gameFolder: String,
                         bottle: String?,
                         verb: Verb,
                         timeout: Int) throws -> MGVFResult {
        let process = Process()
        // /bin/bash with the script as an argument, rather than executing the
        // script directly: a file extracted from a downloaded tarball may not
        // carry its executable bit, and bash reading it as data also sidesteps
        // the quarantine attribute a download arrives with.
        process.executableURL = URL(fileURLWithPath: "/bin/bash")

        var arguments = [script, gameFolder]
        if let verbArgument = verb.argument { arguments.append(verbArgument) }
        // An array, never an interpolated string. Game folders contain spaces,
        // apostrophes and trademark signs -- "Middle-earth™ Shadow of Mordor™"
        // is on this machine -- and every one of those breaks a quoted command.
        process.arguments = arguments

        // An explicit environment, which means every variable the scripts need
        // has to be named here. HOME is not optional: the bottle roots are
        // built from it, and under `set -u` its absence used to kill the lookup
        // while the script still printed a state word. PATH must include
        // /usr/bin for perl, sed, defaults and the CrossOver binaries -- an app
        // launched from the Finder inherits launchd's minimal one.
        var environment: [String: String] = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
        ]
        if let user = ProcessInfo.processInfo.environment["USER"] { environment["USER"] = user }
        // Which bottle, stated rather than left to be found.
        //
        // Since 4.12.2 the installers take MGVF_BOTTLE and use that bottle and
        // no other; an invalid value is an error at source time rather than a
        // fall back to scanning. But an UNSET value still scans, so this is not
        // an optimisation: a build that forgets to set it behaves exactly like
        // 4.12.1 did and nothing says so.
        //
        // Singular, and one character from its opposite: the same file also
        // reads MGVF_BOTTLES, plural, which ADDS a root to the scan.
        if let bottle, !bottle.isEmpty { environment["MGVF_BOTTLE"] = bottle }
        // Says a program is asking, not a person at a terminal.
        //
        // It is what lets the installers treat an UNSET MGVF_BOTTLE as an error
        // for us while a hand run still gets its scan. Without it a build that
        // forgot the pin would fail silently in exactly the way this is meant
        // to prevent, so it is set unconditionally -- including for a fix that
        // names no bottle, because the flag describes the CALLER and not the
        // fix. Set before the installers read it, which is deliberate: an
        // unknown variable is inert, and arriving late is the failure mode
        // that has no symptom.
        environment["MGVF_FRONTEND"] = "RaccoonBot"
        // A read-only pass says so structurally, not only positionally.
        //
        // The installers default to MODE=--install and switch to status only
        // when the literal string "--status" survives every hop from here to
        // argv. MGVF_STATUS_ONLY=1 forces the mode regardless of the argument,
        // so a mistake in building that argument cannot install something
        // during a survey -- and this application surveys a whole library at a
        // time. The valve protects us from our own error rather than from the
        // scripts.
        //
        // Not honoured by every installer: as of 4.12.3, install-ng3-fix.sh and
        // some others do not read it. So it is a second lock and never the only
        // one -- the verb still carries --status on its own.
        if !verb.writes { environment["MGVF_STATUS_ONLY"] = "1" }
        process.environment = environment

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        // Both pipes drained concurrently. Reading one to the end and then the
        // other deadlocks as soon as the process fills the buffer of the one
        // not being read, and these scripts write to both.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        let readQueue = DispatchQueue(label: "mgvf.read", attributes: .concurrent)
        group.enter()
        readQueue.async {
            outData = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        readQueue.async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        try process.run()

        var timedOut = false
        let deadline = DispatchWorkItem {
            if process.isRunning {
                timedOut = true
                process.terminate()
            }
        }
        timerQueue.asyncAfter(deadline: .now() + .seconds(timeout), execute: deadline)

        process.waitUntilExit()
        deadline.cancel()
        group.wait()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        if timedOut { throw MGVFError.timedOut(script, seconds: timeout) }

        return MGVFResult(state: Self.stateWord(in: stdout + "\n" + stderr),
                          stdout: stdout,
                          stderr: stderr,
                          exitCode: process.terminationStatus)
    }

    // MARK: - Reading the answer

    /// Find the state word, by WORD, anywhere in either stream.
    ///
    /// Not the first line, and not stdout alone. Two installers print
    /// `warning:` lines around the answer, and the ng4 one writes its warning
    /// to stderr -- a reader that took the first line of stdout once came back
    /// with "warning:" as the state. And not a substring search either:
    /// "not installed" contains "installed".
    static func stateWord(in text: String) -> FixState? {
        let separators = CharacterSet.whitespacesAndNewlines
        for token in text.components(separatedBy: separators) {
            let word = token.trimmingCharacters(in: .punctuationCharacters)
            if let state = FixState(rawValue: word) { return state }
        }
        return nil
    }

    /// Replace the user's home with ~ before anything is logged.
    ///
    /// The error paths in these scripts print absolute paths, and those name
    /// the user and the whole layout of their Steam library.
    static func redacted(_ text: String) -> String {
        text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
