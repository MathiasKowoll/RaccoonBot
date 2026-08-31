//
//  SteamBootFlagsTests.swift
//  RaccoonBotTests
//

import Testing
@testable import RaccoonBot

struct SteamBootFlagsTests {

    /// The default is unchanged, because almost every title is right on it and
    /// a fuller start costs seconds on every launch.
    @Test func theDefaultStillSkipsTheBootstrap() {
        #expect(steamBootFlags(fullBoot: false).contains("-skipinitialbootstrap"))
    }

    /// The exception drops exactly one flag.
    @Test func theFullerStartDropsOnlyTheBootstrapFlag() {
        let short = steamBootFlags(fullBoot: false).split(separator: " ").map(String.init)
        let full = steamBootFlags(fullBoot: true).split(separator: " ").map(String.init)
        #expect(Set(short).subtracting(full) == ["-skipinitialbootstrap"])
        #expect(Set(full).subtracting(short).isEmpty)
    }

    /// -no-browser and -no-cef-sandbox were never separated from the bootstrap
    /// flag by measurement, so they stay in both. Dropping three things to fix
    /// one makes the next failure unreadable.
    @Test func theUnmeasuredFlagsStayInBoth() {
        for flag in ["-no-browser", "-no-cef-sandbox", "-silent", "-nochatui", "-nofriendsui"] {
            #expect(steamBootFlags(fullBoot: true).contains(flag), "missing \(flag) in the full start")
            #expect(steamBootFlags(fullBoot: false).contains(flag), "missing \(flag) in the short start")
        }
    }
}
