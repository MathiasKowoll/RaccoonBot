//
//  SafeShellTests.swift
//  RaccoonBotTests
//
//  Running a command must not mean waiting for it.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct SafeShellTests {

    /// The one that mattered: turning on logging made the application freeze,
    /// because debug mode routed the launch through a read that blocks until
    /// the child closes its output -- and the child is a game.
    @Test func aLongRunningCommandReturnsImmediately() throws {
        let started = Date()
        try safeShell("/bin/sleep 5")
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 1.5, "it waited \(elapsed)s for a command that runs for five")
    }

    @Test func aCommandThatWritesALotDoesNotStall() throws {
        // More than a pipe buffer. Nothing may read it in the normal path and
        // the debug path must read it as it arrives, not in one go at the end.
        let started = Date()
        try safeShell("/usr/bin/yes 'x' | /usr/bin/head -c 300000")
        #expect(Date().timeIntervalSince(started) < 2)
    }

    /// The blocking variant is for short commands and is still used. It must
    /// not die on output that is not valid UTF-8.
    @Test func outputThatIsNotTextComesBackRatherThanCrashing() throws {
        let out = try safeShellWithOutput("/bin/echo hello")
        #expect(out.contains("hello"))
        let binary = try safeShellWithOutput("/bin/echo '\\xff\\xfe' | /usr/bin/head -c 2")
        #expect(binary.count >= 0)
    }

    /// Deliberately not tested: that a bad command throws. `zsh -c` starts
    /// fine and reports the failure through an exit status nobody reads here,
    /// so claiming otherwise would be a test of a promise the function does
    /// not make.
}

/// The debug switch, which now lives in the window rather than only in the
/// environment.
///
/// Asking somebody to open a terminal and set a variable before they can tell
/// you what went wrong is asking too much -- of them, and of anyone giving
/// support.
struct DebugSwitchTests {

    private var key: String { namespacedKey("debugLogging", "app") }

    @Test func theSwitchTakesEffectWithoutARestart() {
        let before = debugLoggingEnabled
        defer { setDebugLogging(before); deleteUsrDefOption(key: key) }

        setDebugLogging(true)
        #expect(debugLoggingEnabled, "it was read once and cached")
        #expect(console.enableLogFile)

        // Only meaningful where the environment is not forcing it on.
        if !debugLoggingFromEnvironment {
            setDebugLogging(false)
            #expect(!debugLoggingEnabled)
        }
    }

    /// The environment still wins, because it is the only way to have logging
    /// from the first line, before any window exists.
    @Test func theEnvironmentCannotBeTurnedOffFromTheWindow() {
        guard debugLoggingFromEnvironment else { return }
        setDebugLogging(false)
        #expect(debugLoggingEnabled, "the switch overrode the environment")
    }

    @Test func theOldNameStillAnswers() {
        // DEBUG_ENABLED is used in a handful of places and must track the flag.
        #expect(DEBUG_ENABLED == debugLoggingEnabled)
    }
}
