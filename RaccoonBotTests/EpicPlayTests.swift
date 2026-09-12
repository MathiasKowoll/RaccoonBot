//
//  EpicPlayTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// How an Epic title is started: by its launcher, through the launcher's
/// own URI, in the launcher's bottle.
struct EpicPlayTests {

    private func epicGame(id: String = "epic:ns1:item1:app1") -> Game {
        let installed = EpicInstalled(id: id, appName: "app1", catalogNamespace: "ns1", catalogItemId: "item1",
                                      title: "A Game", folder: URL(fileURLWithPath: "/tmp/x"),
                                      executable: URL(fileURLWithPath: "/tmp/x/AGame.exe"),
                                      version: "1", presence: .installed)
        return Game.epic(installed)
    }

    /// The form the launcher's own shortcuts use: three ids joined by an
    /// encoded colon, and silent so its window stays out of the way.
    @Test func theURIIsTheLaunchersOwn() {
        #expect(EpicLaunch.launchURI(forID: "epic:ns1:item1:app1")
                == "com.epicgames.launcher://apps/ns1%3Aitem1%3Aapp1?action=launch&silent=true")
    }

    @Test func onlyTheAppNameStillResolves() {
        #expect(EpicLaunch.launchURI(forID: "epic:::app1") == "com.epicgames.launcher://apps/app1?action=launch&silent=true")
    }

    @Test func notAnEpicIDIsNil() {
        #expect(EpicLaunch.launchURI(forID: "12345") == nil)
        #expect(EpicLaunch.launchURI(forID: "epic:ns:item:") == nil, "no AppName, nothing to launch")
        #expect(EpicLaunch.launchURI(forID: "steam:ns:item:app") == nil)
    }

    /// The card's Play used to be a sentence for Epic; now it is the gate
    /// every title passes, and it opens when a launcher is there to start it.
    @Test func playIsAllowedWithALauncher() {
        #expect(GameLauncher.outcome(for: epicGame(), isPlaying: false, needsFix: false, hasEpicLauncher: true) == .started)
    }

    @Test func playRefusesWithoutALauncher() {
        #expect(GameLauncher.outcome(for: epicGame(), isPlaying: false, needsFix: false, hasEpicLauncher: false) == .noExecutable)
    }

    /// The fix gate applies to an Epic title like any other: a game with an
    /// outdated codec patch is asked about first.
    @Test func theFixGateStillApplies() {
        #expect(GameLauncher.outcome(for: epicGame(), isPlaying: false, needsFix: true) == .needsFix)
        #expect(GameLauncher.outcome(for: epicGame(), isPlaying: true, needsFix: false) == .alreadyPlaying)
    }

    /// The game is followed by its own executable's name, as a custom title
    /// is, since Steam knows nothing about it.
    @Test func theTrackerKnowsTheExecutable() {
        #expect(epicGame().appNames == ["AGame.exe"])
    }

    /// No launcher in the bottle, no plan: the launcher is looked for where
    /// the manifest says, and a bottle that has none answers nil.
    @Test func noLauncherNoPlan() {
        let bottle = "file://" + NSTemporaryDirectory() + "nobottle-\(UUID().uuidString)"
        let settings = StoreSettings(bottle: bottle, clientPath: #"C:\nowhere\EpicGamesLauncher.exe"#)
        #expect(EpicLaunch.plan(for: epicGame(), settings: settings, selectedBottle: bottle) == nil)
    }
}
