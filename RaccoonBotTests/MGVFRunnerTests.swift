//
//  MGVFRunnerTests.swift
//  RaccoonBotTests
//
//  These test the three things a naive runner gets wrong, and which are the
//  reason this runner exists at all: it deadlocks on a chatty script, it reads
//  the wrong word as the answer, and it cannot tell a failure from a success.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

private func makeScript(_ body: String) throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mgvf-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("install-fake.sh")
    try ("#!/bin/bash\n" + body).write(to: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    return path.path
}

struct MGVFStateWordTests {

    @Test func findsTheWordAmongWarnings() {
        // install-runtime-fix.sh and install-ng4-fix.sh print `warning:` lines
        // around the answer. A reader taking the first line came back with
        // "warning:" as the state, which is how a fix reported itself broken
        // for a reason nobody could see.
        let text = "warning: dstoragecore.dll is still in place\ninstalled\n"
        #expect(MGVFRunner.stateWord(in: text) == .installed)
    }

    @Test func readsTheWordFromStderrToo() {
        #expect(MGVFRunner.stateWord(in: "\nbroken\n") == .broken)
    }

    @Test func doesNotMatchASubstring() {
        // "not installed" contains "installed". A substring search would call
        // an absent fix installed, which is the single worst answer available.
        #expect(MGVFRunner.stateWord(in: "the bridge is not-installed-yet") == nil)
    }

    @Test func refusesWhenThereIsNoAnswer() {
        // A script that could not determine the state says nothing. That is not
        // `absent`; it is "we do not know", and the caller must see the
        // difference.
        let text = "install-nier-bridge.sh: line 40: HOME: this needs HOME\n"
        #expect(MGVFRunner.stateWord(in: text) == nil)
    }

    @Test func redactsTheHome() {
        let text = "cannot open \(NSHomeDirectory())/Library/Application Support/Steam"
        #expect(!MGVFRunner.redacted(text).contains(NSHomeDirectory()))
        #expect(MGVFRunner.redacted(text).hasPrefix("cannot open ~/"))
    }
}

struct MGVFRunnerProcessTests {

    @Test func capturesBothStreamsWithoutDeadlocking() async throws {
        // A pipe buffer is 64 KB. Draining one stream to the end before the
        // other blocks forever as soon as the process fills the one nobody is
        // reading -- and these scripts do write to both.
        let script = try makeScript("""
        for i in $(seq 1 4000); do
          echo "stdout line $i padded to make this worth more than a buffer"
          echo "stderr line $i padded to make this worth more than a buffer" >&2
        done
        echo installed
        """)
        let result = try await MGVFRunner.shared.run(script: script,
                                                     target: "/tmp",
                                                     verb: .status,
                                                     timeout: 60)
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("stdout line 4000"))
        #expect(result.stderr.contains("stderr line 4000"))
        #expect(result.state == .installed)
    }

    /// The pin has to ARRIVE. This is the one part of the change with no
    /// symptom when it fails: the child environment is deliberately narrow --
    /// HOME, PATH, LC_ALL, USER -- so a variable that is not named here simply
    /// is not there, the installer finds MGVF_BOTTLE unset, and since 4.12.2
    /// it goes back to scanning for bottles exactly as 4.12.1 did, silently.
    /// So it is asserted by reading it out of a real child process rather than
    /// by reading our own source.
    @Test func thePinReachesTheScript() async throws {
        let script = try makeScript("""
        echo "bottle=[${MGVF_BOTTLE:-unset}]"
        echo "frontend=[${MGVF_FRONTEND:-unset}]"
        echo installed
        """)
        let result = try await MGVFRunner.shared.run(script: script,
                                                     target: "/tmp",
                                                     bottle: "/some/where/Steam",
                                                     verb: .status,
                                                     timeout: 60)
        #expect(result.stdout.contains("bottle=[/some/where/Steam]"))
        #expect(result.stdout.contains("frontend=[RaccoonBot]"))
    }

    /// A fix that touches no bottle names none -- and must not leak a stale one
    /// from the environment this process happens to be running in.
    @Test func aFixWithNoBottleLeavesThePinUnsetButStillDeclaresTheFrontend() async throws {
        let script = try makeScript("""
        echo "bottle=[${MGVF_BOTTLE:-unset}]"
        echo "frontend=[${MGVF_FRONTEND:-unset}]"
        echo installed
        """)
        let result = try await MGVFRunner.shared.run(script: script,
                                                     target: "/tmp",
                                                     verb: .status,
                                                     timeout: 60)
        #expect(result.stdout.contains("bottle=[unset]"))
        // Set even here: the flag describes the caller, not the fix. It is what
        // lets the installers treat a missing pin as an error for a program
        // while a person at a terminal still gets the scan.
        #expect(result.stdout.contains("frontend=[RaccoonBot]"))
    }

    @Test func reportsTheExitCodeOfAFailure() async throws {
        // The whole point. safeShell returns before the process does and sends
        // both streams to /dev/null, so this case looks exactly like success.
        let script = try makeScript("""
        echo "moved the original aside" >&2
        exit 3
        """)
        let result = try await MGVFRunner.shared.run(script: script,
                                                     target: "/tmp",
                                                     verb: .status,
                                                     timeout: 60)
        #expect(result.exitCode == 3)
        #expect(result.state == nil)
        #expect(result.stderr.contains("moved the original aside"))
    }

    @Test func survivesAFolderNameWithSpacesAndSymbols() async throws {
        // Real folder from this machine: "Middle-earth™ Shadow of Mordor™".
        // Interpolating that into a shell command breaks it; an argument array
        // does not care.
        let awkward = "/tmp/Middle-earth™ Shadow of Mordor™ 'quoted'"
        let script = try makeScript("""
        [ "$1" = "\(awkward)" ] && echo installed || echo absent
        """)
        let result = try await MGVFRunner.shared.run(script: script,
                                                     target: awkward,
                                                     verb: .status,
                                                     timeout: 60)
        #expect(result.state == .installed)
    }

    @Test func passesHomeAndAUsablePath() async throws {
        // Both are absent from the environment an app launched from the Finder
        // hands its children. Without HOME the installers refuse; without
        // /usr/bin in PATH they cannot find perl.
        let script = try makeScript("""
        [ -n "${HOME:-}" ] || { echo "no HOME" >&2; exit 1; }
        command -v perl >/dev/null || { echo "no perl" >&2; exit 1; }
        echo installed
        """)
        let result = try await MGVFRunner.shared.run(script: script,
                                                     target: "/tmp",
                                                     verb: .status,
                                                     timeout: 60)
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(result.state == .installed)
    }

    @Test func stopsAScriptThatHangs() async throws {
        let script = try makeScript("sleep 30\necho installed")
        await #expect(throws: MGVFError.self) {
            _ = try await MGVFRunner.shared.run(script: script,
                                                target: "/tmp",
                                                verb: .status,
                                                timeout: 2)
        }
    }

    @Test func refusesAScriptItCannotRun() async throws {
        await #expect(throws: MGVFError.self) {
            _ = try await MGVFRunner.shared.run(script: "/nonexistent/install-nope.sh",
                                                target: "/tmp",
                                                verb: .status,
                                                timeout: 5)
        }
    }

    @Test func installOmitsTheVerb() {
        // install-ng4-fix.sh reads ACTION="${2:-install}" and accepts a bare
        // `install`; passing --install prints the usage and exits 1 without
        // touching anything.
        #expect(MGVFRunner.Verb.install.argument == nil)
        #expect(MGVFRunner.Verb.status.argument == "--status")
        #expect(MGVFRunner.Verb.restore.argument == "--restore")
        #expect(MGVFRunner.Verb.status.writes == false)
        #expect(MGVFRunner.Verb.install.writes == true)
    }
}
