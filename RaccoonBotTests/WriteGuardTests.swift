//
//  WriteGuardTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// The guard that decides whether a fix may be written.
///
/// It used to ask "does any command line contain `.exe`" and report the answer
/// as "a Windows game is running". Wine's own services carry that suffix, and
/// three of the installers create them by writing their per-application
/// overrides through `reg.exe` -- so a sweep patched six titles and reported
/// the remaining nine as blocked by a game, with nothing running but what the
/// sweep had started itself. These are about the difference between what was
/// measured and what was claimed.
///
/// Deliberately not `@MainActor`. Asking spawns pgrep and waits for it, and
/// doing that on the main thread while the rest of the suite runs made a
/// timing-sensitive test elsewhere fail every time -- measured: adding the
/// three tests here that ask took the suite from 408 passing to one failing,
/// and removing only those three put it back. The check is `nonisolated` for
/// the same reason.
struct WriteGuardTests {

    private typealias Running = MGVFCoordinator.Running

    /// The whole point: wine's furniture is not a game.
    @Test func wineOwnServicesAreNotAGame() {
        let running = Running(executables: ["services.exe", "winedevice.exe", "plugplay.exe"],
                              server: true, unknown: false)
        #expect(running.games.isEmpty)
    }

    /// And a game among the furniture is still a game. Refusing was never the
    /// defect; naming was.
    @Test func aGameAmongTheFurnitureIsStillFound() {
        let running = Running(executables: ["services.exe", "nioh.exe", "explorer.exe"],
                              server: true, unknown: false)
        #expect(running.games == ["nioh.exe"])
    }

    /// Steam is not furniture and not a game, and is reported by name rather
    /// than sorted into either. What was measured is that it is running.
    @Test func aLauncherIsNamedRatherThanClassified() {
        let running = Running(executables: ["steam.exe", "services.exe"],
                              server: true, unknown: false)
        #expect(running.games == ["steam.exe"])
    }

    /// `reg.exe` is furniture precisely because the installers run it. A sweep
    /// catching its own reg.exe is the fault this whole file exists for.
    @Test func theInstallersOwnRegExeIsFurniture() {
        #expect(Running.furniture.contains("reg.exe"))
        #expect(Running(executables: ["reg.exe"], server: true, unknown: false).games.isEmpty)
    }

    /// pgrep exists on every Mac, so on this machine the answer is never
    /// "could not ask". If this fails, the reading is broken rather than the
    /// machine being busy.
    @Test func askingWorksOnThisMachine() {
        #expect(MGVFCoordinator.whatIsRunning().unknown == false)
    }

    /// Nothing running, nothing refused. Asked of a state rather than of the
    /// machine: measuring and then asking again are two different instants,
    /// and a test written that way failed about one run in two while other
    /// tests in the suite were starting and ending processes of their own.
    @Test func nothingRunningMeansNothingRefused() {
        let quiet = Running(executables: [], server: false, unknown: false)
        #expect(MGVFCoordinator.reason(for: quiet) == nil)
    }

    /// A refusal says what it found, and never calls it a game.
    @Test func aRefusalNamesWhatItFound() {
        let reason = MGVFCoordinator.reason(for: Running(executables: ["nioh.exe", "services.exe"],
                                                         server: true, unknown: false))
        #expect(reason?.contains("nioh.exe") == true)
        #expect(reason?.contains("A Windows game is running") == false)
    }

    /// Wine's furniture alone still refuses -- the DLLs may be mapped -- but it
    /// is reported as an open bottle rather than as somebody playing.
    @Test func furnitureAloneRefusesWithoutBlamingAGame() {
        let reason = MGVFCoordinator.reason(for: Running(executables: ["services.exe"],
                                                         server: true, unknown: false))
        #expect(reason != nil)
        #expect(reason?.contains("bottle is still open") == true)
    }

    /// Not being able to look is not permission to write, and is not reported
    /// as having looked and found nothing.
    @Test func notBeingAbleToAskStillRefuses() {
        let reason = MGVFCoordinator.reason(for: Running(executables: [], server: false, unknown: true))
        #expect(reason?.contains("Could not check") == true)
    }

}
