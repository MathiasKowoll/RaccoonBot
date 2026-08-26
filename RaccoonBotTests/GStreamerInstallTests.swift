//
//  GStreamerInstallTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct GStreamerVersionChoiceTests {

    /// What the site actually publishes, read from it.
    let published = ["1.2.4", "1.4.4", "1.4.5", "1.6.4", "1.8.3", "1.12.4", "1.14.5",
                     "1.16.3", "1.18.6", "1.20.7", "1.22.12", "1.24.13",
                     "1.26.4", "1.26.11", "1.28.0", "1.28.5", "1.28.6", "1.29.1"]

    @Test func holdsAtTheOldestEngineOnTheMachine() {
        // CrossOver 26.3 runs a 1.24 core, so 1.24.13 -- the last of its line.
        // Offering 1.28 here would load a plugin that references 200 symbols
        // that core does not export, and the only symptom is silent video.
        #expect(GStreamerInstall.chooseVersion(available: published, engineSeries: [24, 28]) == "1.24.13")
    }

    @Test func movesOnWhenTheOldEngineIsGone() {
        // Nothing holding it back: the newest of the series it can use.
        #expect(GStreamerInstall.chooseVersion(available: published, engineSeries: [28]) == "1.28.6")
    }

    @Test func doesNotOfferADevelopmentSeries() {
        // 1.29 is odd-numbered and unstable; a 1.28 engine must not be sent
        // there just because it sorts higher.
        #expect(GStreamerInstall.chooseVersion(available: published, engineSeries: [28]) != "1.29.1")
    }

    @Test func refusesToGuessWithNoEngines() {
        #expect(GStreamerInstall.chooseVersion(available: published, engineSeries: []) == nil)
    }

    @Test func buildsTheRuntimePackageURL() {
        // The version changes in two places, and the neighbours -- devel and
        // debug -- are not the package we want.
        let url = GStreamerInstall.packageURL(version: "1.24.13").absoluteString
        #expect(url == "https://gstreamer.freedesktop.org/data/pkg/osx/1.24.13/gstreamer-1.0-1.24.13-universal.pkg")
        #expect(!url.contains("devel"))
        #expect(!url.contains("debug"))
    }

    @Test func readsVersionsOutOfTheListing() {
        let html = """
        <a href="1.24.13/">1.24.13/</a> <a href="1.28.6/">1.28.6/</a>
        <a href="latest/">latest/</a>
        """
        let versions = GStreamerInstall.parseVersions(html)
        #expect(versions.contains("1.24.13"))
        #expect(versions.contains("1.28.6"))
    }
}
