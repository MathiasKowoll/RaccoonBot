//
//  QuitTeardownTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

@Suite("Closing a bottle before quitting")
struct QuitTeardownTests {

    private let steam = "file:///Users/someone/Library/Application%20Support/RaccoonBot/CXPBottles/Steam/"
    private let epic = "file:///Users/someone/Library/Application%20Support/RaccoonBot/CXPBottles/Epic/"

    // MARK: - Which bottles

    @Test func onlyABottleWithAServerUpIsClosed() {
        let up = QuitTeardown.bottlesToClose(candidates: [steam, epic]) { $0.lastPathComponent == "Steam" }
        #expect(up == [steam])
    }

    @Test func nothingUpClosesNothing() {
        #expect(QuitTeardown.bottlesToClose(candidates: [steam, epic]) { _ in false }.isEmpty)
    }

    /// The Epic launcher's bottle is the Steam one here, and it can be stored
    /// with or without the trailing slash.
    @Test func oneBottleNamedTwiceIsClosedOnce() {
        var looks = 0
        let up = QuitTeardown.bottlesToClose(candidates: [steam, String(steam.dropLast())]) { _ in
            looks += 1
            return true
        }
        #expect(up == [steam])
        #expect(looks == 1)
    }

    @Test func aBareNameOrAnEmptyEntryIsNeverClosed() {
        var looked: [URL] = []
        let up = QuitTeardown.bottlesToClose(candidates: ["", "Steam", steam]) { looked.append($0); return true }
        #expect(up == [steam])
        #expect(looked.count == 1)
    }

    @Test func theOrderGivenIsKept() {
        #expect(QuitTeardown.bottlesToClose(candidates: [epic, steam]) { _ in true } == [epic, steam])
    }

    // MARK: - What a quit does

    @Test func aQuitWithNothingUpGoesAtOnce() {
        #expect(QuitTeardown.decide(closing: false, cxAppPath: "/Applications/Engine.app", bottles: []) == .quitNow)
    }

    @Test func aQuitWithABottleUpClosesItFirst() {
        #expect(QuitTeardown.decide(closing: false, cxAppPath: "/Applications/Engine.app", bottles: [steam])
                == .closeFirst([steam]))
    }

    /// Nothing can be closed without an engine, and holding the quit for it
    /// would only hold it.
    @Test func withoutAnEngineAQuitGoesAtOnce() {
        #expect(QuitTeardown.decide(closing: false, cxAppPath: nil, bottles: [steam]) == .quitNow)
        #expect(QuitTeardown.decide(closing: false, cxAppPath: "", bottles: [steam]) == .quitNow)
    }

    @Test func aSecondQuitWhileClosingIsRefused() {
        #expect(QuitTeardown.decide(closing: true, cxAppPath: "/Applications/Engine.app", bottles: [steam]) == .refuse)
        #expect(QuitTeardown.decide(closing: true, cxAppPath: nil, bottles: []) == .refuse)
    }

    // MARK: - What the window says

    @Test func theWindowNamesTheBottleBeingClosed() {
        #expect(QuitTeardown.message(closing: ["Steam"]) == "Closing Steam before quitting…")
        #expect(QuitTeardown.message(closing: ["Steam", "Epic"]) == "Closing Steam and Epic before quitting…")
    }

    @Test func aBottleWithNoNameStillGetsALine() {
        #expect(QuitTeardown.message(closing: []) == "Closing Wine before quitting…")
        #expect(QuitTeardown.message(closing: [""]) == "Closing Wine before quitting…")
    }

    // MARK: - One reply

    @Test func theReplyIsClaimedOnce() {
        let reply = QuitTeardown.Reply()
        #expect(reply.claim())
        #expect(!reply.claim())
        #expect(!reply.claim())
    }

    @Test func theBoundLeavesRoomForTheSyncAndCloseBottle() {
        // closeBottle waits up to 30 s for the clients, and the exit-sync wait
        // is bounded in its own right; the quit's bound must be longer than
        // the first alone.
        #expect(QuitTeardown.bound > 30)
    }
}
